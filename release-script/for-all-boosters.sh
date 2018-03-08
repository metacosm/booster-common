#!/bin/bash

set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

CURRENT_DIR=`pwd`
CATALOG_FILE=$CURRENT_DIR"/booster-catalog-versions.txt"
rm -f "$CATALOG_FILE"
touch "$CATALOG_FILE"

# script-wide toggle controlling pushes from functions
PUSH='on'

# script-wide toggle controlling commits from functions
COMMIT='on'

# failed boosters
declare -a failed=( )

# skipped boosters
declare -a ignored=( )

evaluate_mvn_expr() {
    # Evaluate the given maven expression, cf: https://stackoverflow.com/questions/3545292/how-to-get-maven-project-version-to-the-bash-command-line
    result=`mvn -q -Dexec.executable="echo" -Dexec.args='${'${1}'}' --non-recursive exec:exec`
    echo ${result}
}

current_branch() {
    currentBranch=${branch:-$BRANCH}
    echo ${currentBranch}
    unset currentBranch
}

log() {
    echo -e "\t${GREEN}$(current_branch)${BLUE}: ${1}${NC}"
}

log_ignored() {
   log "${MAGENTA}${1}${MAGENTA}. Ignoring."
   ignoredItem="$(current_branch):${BOOSTER}:\"${1}\""
   ignored+=( ${ignoredItem} )
}

log_failed() {
   log "${RED}ERROR: ${1}${RED}"
   ignoredItem="$(current_branch):${BOOSTER}:\"${1}\""
   ignored+=( ${ignoredItem} )
}

error() {
    echo -e "${RED}Error: ${1}${NC}"
    exit ${2:-1}
}

push_to_remote() {
    currentBranch=${branch:-$BRANCH}
    remote=${1:-upstream}
    options=${2:-}

    if [[ "$PUSH" == on ]]; then
        if git push ${options} ${remote} ${currentBranch} > /dev/null; then
            log "Pushed to ${remote}"
        else
            log_ignored "Failed to push to ${remote}"
        fi
    fi
    unset currentBranch
}

commit() {
    if [[ "$COMMIT" == on ]]; then
        log "Commit"
        git commit -q -am "${1}"
    fi
}

compute_new_version() {
    version_expr=${1:-project.version}
    current_version=$(evaluate_mvn_expr ${version_expr})

    parts=( ${current_version//-/ } )
    sb_version=${parts[0]}
    version_int=${parts[1]}
    qualifier=${parts[2]}
    snapshot=${parts[3]}

    # to output parts:
    # echo "${parts[@]}"

    if [[ "$snapshot" == SNAPSHOT ]]
    then
        new_version="${sb_version}-$(($version_int +1))-${qualifier}-${snapshot}"
    else
        if [ -n "${qualifier}" ]
        then
            new_version="${sb_version}-$(($version_int +1))-${qualifier}"
        else
            new_version="${sb_version}-$(($version_int +1))"
        fi
    fi

    echo ${new_version}
}

update_parent() {
    change_version $1 $2 parent
}

change_version() {
    newVersion=${1:-compute}

    # if we provide a 3rd arg, switch to parent processing instead
    expr="project.version"
    target="project"
    if [ -n "$3" ]; then
        expr="project.parent.version"
        target="parent"
    fi

    # if provided version is "compute" then compute the new version :)
    if [[ "${newVersion}" == compute ]]; then
        newVersion=$(compute_new_version ${expr})
    fi

    currentVersion=$(evaluate_mvn_expr ${expr})
    cmd="mvn versions:set -DnewVersion=${newVersion} > /dev/null"
    if [ -n "$3" ]; then
        cmd="sed -i '' -e 's/<version>${currentVersion}</<version>${newVersion}</g' pom.xml"
    fi

    if eval ${cmd}; then
        # Only attempt committing if we have changes otherwise the script will exit
        if [[ `git status --porcelain` ]]; then
            log "Updated ${target} from ${YELLOW}${currentVersion}${BLUE} to ${YELLOW}${newVersion}"
            log "Running verification build"
            if mvn clean verify > build.log; then
                log "Build ${YELLOW}OK"
                rm build.log

                if [ -n "$2" ]; then
                    jira=${2}": "
                else
                    jira=""
                fi
                commit ${jira}"Update ${target} version to ${newVersion}"

                push_to_remote
            else
                log_failed "Build failed! Check ${YELLOW}build.log"
                log "You will need to reset the branch or explicitly set the parent before running this script again."
            fi

        else
            log_ignored "Version was already at ${YELLOW}${newVersion}"
        fi

        find . -name "*.versionsBackup" -delete
    else
        log_failed "Couldn't set version. Reverting to upstream version."
        git reset --hard upstream/${BRANCH}
    fi

    echo $newVersion
}

create_branch() {
    branch=$1

    if git ls-remote --heads upstream ${branch} | grep ${branch} > /dev/null;
    then
        log_ignored "Branch already exists on remote"
    else
        if ! git co -b ${branch} > /dev/null 2> /dev/null;
        then
            log_failed "Couldn't create branch"
            return 1
        fi
    fi

    unset branch # unset to avoid side-effects in log
}

delete_branch() {
    branch=$1

    if git ls-remote --heads upstream ${branch} | grep ${branch} > /dev/null;
    then
        log "Are you sure you want to delete ${YELLOW}${branch}${BLUE} branch on remote ${YELLOW}upstream${BLUE}?"
        log "Press any key to continue or ctrl-c to abort."
        read foo

        push_to_remote upstream -d
    else
        log_ignored "Branch doesn't exist on remote"
    fi

    if ! git branch -D ${branch} > /dev/null 2> /dev/null;
    then
        log_ignored "Branch doesn't exist locally"
    fi

    unset branch # unset to avoid side-effects in log
}

release() {
    current_version=$(evaluate_mvn_expr 'project.version')

    if [[ "${current_version}" != *-SNAPSHOT ]]; then
        log_ignored "Cannot release a non-snapshot version"
        return 1
    fi

    versionRE='([1-9].[0-9].[0-9]+)-([0-9]+)-?(rhoar|redhat)?-?(SNAPSHOT)?'
    if [[ "${current_version}" =~ ${versionRE} ]]; then
        sbVersion=${BASH_REMATCH[1]}
        versionInt=${BASH_REMATCH[2]}
        newVersionInt=$(($versionInt +1))
        qualifier=${BASH_REMATCH[3]}
        snapshot=${BASH_REMATCH[4]}

        releaseVersion="${sbVersion}-${versionInt}"
        if [[ -n "${qualifier}" ]]; then
            releaseVersion="${releaseVersion}-${qualifier}"
        fi

        nextVersion="${sbVersion}-${newVersionInt}"
        if [[ -n "${qualifier}" ]]; then
            nextVersion="${nextVersion}-${qualifier}"
        fi
        nextVersion="${nextVersion}-SNAPSHOT"

    fi

    runtime=${1:-'1.2-7'}
    
    # replace template placeholders if they exist
    templates=($(find . -name "application.yaml"))
    if [ ${#templates[@]} != 0 ]; then
        for file in ${templates[@]}
        do
            sed -i '' -e "s/RUNTIME_VERSION/${runtime}/g" ${file}
            log "${YELLOW}${file}${BLUE}: Replaced RUNTIME_VERSION token by ${runtime}"

            sed -i '' -e "s/BOOSTER_VERSION/${releaseVersion}/g" ${file}
            log "${YELLOW}${file}${BLUE}: Replaced BOOSTER_VERSION token by ${releaseVersion}"
        done
        if [[ `git status --porcelain` ]]; then
            commit "Replaced templates placeholders: RUNTIME_VERSION -> ${runtime}, BOOSTER_VERSION -> ${releaseVersion}"
        else
            # if no changes were made it means that templates don't contain tokens and should be fixed
            log_ignored "Couldn't replace tokens in templates"
            return 1
        fi
    fi

    # switch off pushing since we'll do it at the end
    PUSH='off'
    change_version ${releaseVersion}

    log "Creating tag ${YELLOW}${releaseVersion}"
    git tag -a ${releaseVersion} -m "Releasing ${releaseVersion}" > /dev/null

    if [ ${#templates[@]} != 0 ]; then
        # restore template placeholders
        for file in ${templates[@]}
        do
            sed -i '' -e "s/${runtime}/RUNTIME_VERSION/g" ${file}
            log "${YELLOW}${file}${BLUE}: Restored RUNTIME_VERSION token"

            sed -i '' -e "s/${releaseVersion}/BOOSTER_VERSION/g" ${file}
            log "${YELLOW}${file}${BLUE}: Restored BOOSTER_VERSION token"
        done
        commit "Restored templates placeholders: ${runtime} -> RUNTIME_VERSION, ${releaseVersion} -> BOOSTER_VERSION"
    fi

    change_version ${nextVersion}

    # switch pushing back on and push
    PUSH='on'
    push_to_remote "upstream" "--tags"

    log "Appending new version ${YELLOW}${releaseVersion}${BLUE} to ${YELLOW}${CATALOG_FILE}"
    echo "${BOOSTER}: ${BRANCH} => ${releaseVersion}" >> "$CATALOG_FILE"
}

boosters=( $(find . -name "spring-boot-*-booster" -type d -exec basename {} \; | sort))
if [ ${#boosters[@]} == 0 ]; then
    echo -e "${RED}No boosters named spring-boot-*-booster could be found in $(pwd)${NC}"
    exit 1
fi

for BOOSTER in ${boosters[@]}
do
    #if [ "$BOOSTER" != spring-boot-circuit-breaker-booster ] && [ "$BOOSTER" != spring-boot-configmap-booster ] && [ "$BOOSTER" != spring-boot-crud-booster ]
    if true; then
        pushd ${BOOSTER} > /dev/null

        echo -e "${BLUE}> ${YELLOW}${BOOSTER}${BLUE}${NC}"

        if [ ! -d .git ]; then
            msg="Not under git control"
            echo -e "${MAGENTA}${msg}${MAGENTA}. Ignoring.${NC}"
            ignoredItem="${BOOSTER}:\"${msg}\""
            ignored+=( ${ignoredItem} )
        else
            for BRANCH in "master" "redhat"
            do
                # check if branch exists, otherwise skip booster
                if ! git show-ref --verify --quiet refs/heads/${BRANCH}; then
                    log_ignored "Branch does not exist"
                    continue
                fi

                # if booster has uncommitted changes, skip it
                if [[ `git status --porcelain` ]]; then
                    log_ignored "You have uncommitted changes, please stash these changes"
                    continue
                fi

                # assumes "official" remote is named 'upstream'
                git fetch -q upstream > /dev/null

                git co -q ${BRANCH} > /dev/null && git rebase upstream/${BRANCH} > /dev/null

                # if we need to replace a multi-line match in the pom file of each booster, for example:
                # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

                # if we need to execute sed on the result of find:
                # find . -name "application.yaml" -exec sed -i '' -e "s/provider: fabric8/provider: snowdrop/g" {} +

                if [ -e "$1" ]; then
                    script=$1
                    log "Running ${YELLOW}${script}${BLUE} script"
                    if ! source $1; then
                        log_failed "Error running script"
                    fi
                else
                    log "No script provided. Only refreshed code."
                fi
            done
        fi


        echo -e "----------------------------------------------------------------------------------------\n"
        popd > /dev/null
    fi
done

if [ ${#failed[@]} != 0 ]; then
    echo -e "${BLUE}The following boosters failed:${RED}"
    printf '\t%s\n' "${failed[*]}" #todo: figure out how to output each on its own line
fi

if [ ${#ignored[@]} != 0 ]; then
    echo -e "${BLUE}The following boosters were skipped:${MAGENTA}"
    printf '\t%s\n' "${ignored[*]}" #todo: figure out how to output each on its own line
fi
