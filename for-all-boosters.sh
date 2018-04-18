#!/bin/bash

# A script to process boosters
set -e

# Defining some colors for output
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

simple_log () {
    echo -e "${BLUE}${1}${NC}"
}

# create a temporary directory WORK_DIR to be removed at the exit of the script
# see: https://stackoverflow.com/questions/4632028/how-to-create-a-temporary-directory
# Note: this is currently unused and uses a nested function as seen here: https://stackoverflow.com/a/31316688
# ====
create_auto_deleted_temp_dir() (

    WORK_DIR=$(mktemp -d)
    simple_log "Created temp working directory $WORK_DIR"

# check if tmp dir was created
    if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    simple_log "Could not create temp directory"
    exit 1
    fi

# deletes the temp directory
    function cleanup {
    rm -rf "$WORK_DIR"
    simple_log "Deleted temp working directory $WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
    trap cleanup EXIT
)
# ====


# script-wide toggle controlling pushes from functions
PUSH='on'

# script-wide toggle controlling commits from functions
COMMIT='on'

# script-wide toggle to bypass local changes check
IGNORE_LOCAL_CHANGES='off'

# script-wide toggle to bypass branch existence check, needed to be able to create branches
CREATE_BRANCH='off'

# failed boosters
declare -a failed=( )

# skipped boosters
declare -a ignored=( )

# processed boosters
declare -a processed=( )

evaluate_mvn_expr() {
    # Evaluate the given maven expression, cf: https://stackoverflow.com/questions/3545292/how-to-get-maven-project-version-to-the-bash-command-line
    result=$(mvn -q -Dexec.executable="echo" -Dexec.args='${'${1}'}' --non-recursive exec:exec)
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
   ignored+=( "${ignoredItem}" )
}

log_failed() {
   log "${RED}ERROR: ${1}${RED}"
   failedItem="$(current_branch):${BOOSTER}:\"${1}\""
   failed+=( "${failedItem}" )
}

push_to_remote() {
    currentBranch=${branch:-$BRANCH}
    local remoteToPushTo=${1}
    options=${2:-}

    if [[ "$PUSH" == on ]]; then
        if git push ${options} "${remoteToPushTo}" "${currentBranch}" > /dev/null; then
            log "Pushed to ${remoteToPushTo}"
        else
            log_ignored "Failed to push to ${remoteToPushTo}"
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
        new_version="${sb_version}-$((version_int +1))-${qualifier}-${snapshot}"
    else
        if [ -n "${qualifier}" ]
        then
            new_version="${sb_version}-$((version_int +1))-${qualifier}"
        else
            new_version="${sb_version}-$((version_int +1))"
        fi
    fi

    echo ${new_version}
}

# check that first arg is contained in array second arg
# see: https://stackoverflow.com/a/8574392
element_in() {
    local e match="$1"
    shift
    for e; do
        [[ "$e" == "$match" ]] && return 0;
    done
    return 1
}

change_version() {
    newVersion=${1:-compute}
    targetParent=${2:-false}

    # if we provide a 3rd arg, switch to parent processing instead
    expr="project.version"
    target="project"
    if [ "${targetParent}" == true ]; then
        expr="project.parent.version"
        target="parent"
    fi

    # if provided version is "compute" then compute the new version :)
    if [[ "${newVersion}" == compute ]]; then
        newVersion=$(compute_new_version ${expr})
    fi

    currentVersion=$(evaluate_mvn_expr ${expr})
    local cmd="mvn versions:set -DnewVersion=${newVersion} > /dev/null"
    if [ "${targetParent}" == true ]; then
        local escapedCurrent=$(sed 's|[]\/$*.^[]|\\&|g' <<< ${currentVersion})
        # see: https://unix.stackexchange.com/a/92907
        cmd="perl -pi -e 's/<version>${escapedCurrent}</<version>${newVersion}</g' pom.xml"
    fi
    
    if eval ${cmd}; then
        # Only attempt committing if we have changes otherwise the script will exit
        if [[ $(git status --porcelain) ]]; then
            log "Updated ${target} from ${YELLOW}${currentVersion}${BLUE} to ${YELLOW}${newVersion}"
            log "Running verification build"
            if mvn clean verify > build.log; then
                log "Build ${YELLOW}OK"
                rm build.log

                if [ -n "$3" ]; then
                    jira=${3}": "
                else
                    jira=""
                fi
                commit ${jira}"Update ${target} version to ${newVersion}"

                push_to_remote "${remote}"
            else
                log_failed "Build failed! Check ${YELLOW}build.log"
                log "You will need to reset the branch or explicitly set the parent before running this script again."
            fi

        else
            log_ignored "Version was already at ${YELLOW}${newVersion}"
        fi

        find . -name "*.versionsBackup" -delete
    else
        log_failed "Couldn't set version. Reverting to remote ${remote} version."
        git reset --hard "${remote}"/"${BRANCH}"
    fi
}

create_branch() {
    branch=${1:-$BRANCH}

    if git ls-remote --heads "${remote}" "${branch}" | grep "${branch}" > /dev/null;
    then
        log_ignored "Branch already exists on remote"
    else
        if ! git checkout -b ${branch} > /dev/null 2> /dev/null;
        then
            log_failed "Couldn't create branch"
            unset branch # unset to avoid side-effects in log
            return 1
        fi
    fi

    unset branch # unset to avoid side-effects in log
}

delete_branch() {
    branch=${1:-$BRANCH}

    if element_in "${branch}" "${default_branches[@]}"; then
        log_failed "Cannot delete protected branch"
        unset branch # unset to avoid side-effects in log
        return 1
    fi

    if git ls-remote --heads "${remote}" "${branch}" | grep "${branch}" > /dev/null;
    then
        log "Are you sure you want to delete ${YELLOW}${branch}${BLUE} branch on remote ${YELLOW}${remote}${BLUE}?"
        log "Press any key to continue or ctrl-c to abort."
        read foo

        push_to_remote "${remote}" "--delete"
    else
        log_ignored "Branch doesn't exist on remote"
    fi

    if ! git branch -D "${branch}" > /dev/null 2> /dev/null;
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
        if [[ $(git status --porcelain) ]]; then
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
    push_to_remote "${remote}" "--tags"

    # todo: update launcher catalog instead
    log "Appending new version ${YELLOW}${releaseVersion}${BLUE} to ${YELLOW}${CATALOG_FILE}"
    echo "${BOOSTER}: ${BRANCH} => ${releaseVersion}" >> "$CATALOG_FILE"
}

revert () {
    if [[ $(git status --porcelain) ]]; then
        log "${RED}DANGER: YOU HAVE UNCOMMITTED CHANGES:"
        git status --porcelain
    fi

    log "Are you sure you want to revert ${YELLOW}${BRANCH}${BLUE} branch to the ${YELLOW}${remote}${BLUE} remote state?"
    log "${RED}YOU WILL LOSE ALL UNPUSHED LOCAL COMMITS SO BE CAREFUL!"
    log "Press ${RED}Y to revert${BLUE} or ${YELLOW}any other key to leave the booster as-is."
    read answer
    if [ "${answer}" == Y ]; then
        log "Resetting to remote ${remote} state"
        git reset --hard "${remote}"/"${BRANCH}"
        git clean -f -d
    else
        log "Leaving as-is"
    fi
}

run_tests() {
    local canonical_name="${BOOSTER}"

    log "Running tests of booster ${canonical_name} from directory: ${PWD}"

    oc delete project ${canonical_name} --ignore-not-found=true
    sleep 10
    oc new-project ${canonical_name} > /dev/null
    mvn -q -B clean verify -Popenshift,openshift-it ${MAVEN_EXTRA_OPTS:-}
    if [ $? -eq 0 ]; then
        echo
        log "Successfully tested"
        #Delete the project since there is no need to inspect the results when everything is OK
        oc delete project ${canonical_name} > /dev/null
    else
        log_failed "Tests failed: inspecting the '${canonical_name}' namespace might provide some insights"

        #We don't delete the project because it could be needed for a postmortem inspection
    fi
}

run_smoke_tests() {
    log "Running tests of booster from directory: ${PWD}"
    mvn -q -B clean verify ${MAVEN_EXTRA_OPTS:-}
    if [ $? -eq 0 ]; then
        log "Successfully tested"
    else
        log_failed "Tests failed"
    fi

}

show_help () {
    simple_log "This scripts executes the given command on all local boosters (identified by the 'spring-boot-*-booster' pattern) found in the current directory."
    simple_log "Usage:"
    simple_log "    -h                            Display this help message."
    simple_log "    -d                            Toggle dry-run mode: no commits or pushes. This operation is not compatible with the release command"
    simple_log "    -f                            Bypass check for local changes, forcing execution if changes exist."
    simple_log "    -b                            A comma-separated list of branches. For example -b branch1,branch2. Defaults to $(IFS=,; echo "${default_branches[*]}"). Note that this option is mandatory to create / delete branches."
    simple_log "    -r                            The name of the git remote to use for the boosters, for example upstream or origin. The default value is ${default_remote}"
    simple_log "    create_branch <branch name>   Create a branch."
    simple_log "    delete_branch <branch name>   Delete a branch."
    simple_log "    change_version <args>         Change the project or parent version. Run with -h to see help."
    simple_log "    cmd <command>                 Execute the provided command."
    simple_log "    fn <function name>            Execute the specified function. This allows to call internal functions. Make sure you know what you're doing!"
    simple_log "    release                       Release the boosters."
    simple_log "    revert                        Revert the booster state to the last remote version."
    simple_log "    run_tests                     Run the integration tests on an OpenShift cluster. Requires to be logged in to the required cluster before executing"
    simple_log "    script <path to script>       Run provided script."
    simple_log "    smoke_tests                   Run the unit tests locally."
    echo
}

show_change_version_help() {
    simple_log "change_version command changes the project's (or parent's, if -p flag is set) version"
    simple_log "Usage:"
    simple_log "    -h                            Display this help message."
    simple_log "    -p                            Optional: change parent version instead of project version."
    simple_log "    -v <version name>             Optional: specify which version to use. Version is computed otherwise."
    simple_log "    -m <commit prefix>            Optional: specify a commit message prefix (e.g. JIRA / github ticket number) to prepend to commit messages. Empty otherwise."
}

error() {
    echo -e "${RED}Error: ${1}${NC}"
    local help=${2:-show_help}
    ${help}
    exit ${3:-1}
}


boosters=( $(find . -name "spring-boot-*-booster" -type d -exec basename {} \; | sort))
if [ ${#boosters[@]} == 0 ]; then
    echo -e "${RED}No boosters named spring-boot-*-booster could be found in $(pwd)${NC}"
    exit 1
fi

if [ $# -eq 0 ]; then
    show_help
fi

readonly default_branches=("master" "redhat")
branches=("${default_branches[@]}")

readonly default_remote=upstream
remote=${default_remote}

# See https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/
while getopts ":hdfb:r:" opt; do
    case ${opt} in
        h)
            show_help
            exit 0
        ;;
        d)
            echo -e "${YELLOW}== DRY-RUN MODE ACTIVATED: no commits or pushes will be issued ==${NC}"
            echo
            PUSH='off'
            COMMIT='off'
        ;;
        f)
            echo -e "${YELLOW}== BYPASSING CHECK FOR LOCAL CHANGES ==${NC}"
            echo
            IGNORE_LOCAL_CHANGES='on'
        ;;
        b)
            IFS=',' read -r -a branches <<< "$OPTARG"
            echo -e "${YELLOW}== Will use '${BLUE}$OPTARG${YELLOW}' branch(es) instead of the default ${BLUE}'$(IFS=,; echo "${default_branches[*]}")${YELLOW}' ==${NC}"
            echo
        ;;
        r)
            echo -e "${YELLOW}== Will use '${BLUE}$OPTARG${YELLOW}' as the git remote instead of the default of ${BLUE}'${default_remote}${YELLOW}' ==${NC}"
            echo
            remote=$OPTARG
        ;;
        \?)
            error "Invalid option: -$OPTARG" 1>&2
        ;;
    esac
done
shift $((OPTIND - 1))

subcommand=$1
cmd=""
case "$subcommand" in
    release)
        if [[ "$COMMIT" == off ]]; then
            log_failed "The dry-run option is not supported for the release command"
            exit 1
        fi

        CURRENT_DIR=$(pwd)
        CATALOG_FILE=$CURRENT_DIR"/booster-catalog-versions.txt"
        rm -f "$CATALOG_FILE"
        touch "$CATALOG_FILE"

        cmd="release"
    ;;
    create_branch)
        CREATE_BRANCH='on'
        cmd="create_branch"
    ;;
    delete_branch)
        cmd="delete_branch"
    ;;
    change_version)
        # Needed in order to "reset" the options processing for the subcommand
        OPTIND=2
        # Process options of subcommand
        while getopts ":hpv:m:" opt2; do
            case ${opt2} in
                h)
                    show_change_version_help
                    exit 0
                ;;
                p)
                    targetParent=true
                ;;
                v)
                    version=$OPTARG
                ;;
                m)
                    jira=$OPTARG
                ;;
                \?)
                    error "Invalid change_version option: -$OPTARG" "show_change_version_help" 1>&2
                ;;
                :)
                    error "Invalid change_version option: -$OPTARG requires an argument" "show_change_version_help" 1>&2
                ;;
            esac
        done
        shift $((OPTIND - 1))

        cmd="change_version ${version:-compute} ${targetParent:-off} ${jira:-}"
    ;;
    script)
        shift
        if [ -n "$1" ]; then
            cmd="source $1"
        else
            error "Must provide a script to execute"
        fi
    ;;
    revert)
        IGNORE_LOCAL_CHANGES='on'
        cmd="revert"
    ;;
    run_tests)
        cmd="run_tests"
    ;;
    smoke_tests)
        cmd="run_smoke_tests"
    ;;
    cmd)
        shift
        if [ -n "$1" ]; then
            cmd="$1"
        else
            error "Must provide a command to execute"
        fi
    ;;
    fn)
        shift
        if [ -n "$1" ]; then
            cmd="$1" # record command name
            shift # remove command name from args
            cmd="${cmd} $@" # append args
        else
            error "Must provide a function to execute"
        fi
    ;;
    *)
        error "Unknown command: '${subcommand}'" 1>&2
    ;;
esac


for BOOSTER in ${boosters[@]}
do
    #if [ "$BOOSTER" != spring-boot-circuit-breaker-booster ] && [ "$BOOSTER" != spring-boot-configmap-booster ] && [ "$BOOSTER" != spring-boot-crud-booster ]; then
    if true; then
        pushd ${BOOSTER} > /dev/null

        echo -e "${BLUE}> ${YELLOW}${BOOSTER}${BLUE}${NC}"

        if [ ! -d .git ]; then
            msg="Not under git control"
            echo -e "${MAGENTA}${msg}${MAGENTA}. Ignoring.${NC}"
            ignoredItem="${BOOSTER}:\"${msg}\""
            ignored+=( "${ignoredItem}" )
        else
            for BRANCH in "${branches[@]}"
            do
                # check if branch exists, otherwise skip booster
                if [ "$CREATE_BRANCH" != on ] && ! git show-ref --verify --quiet refs/heads/${BRANCH}; then
                    log_ignored "Branch does not exist"
                    continue
                fi

                if [ "$IGNORE_LOCAL_CHANGES" != on ]; then
                    # if booster has uncommitted changes, skip it
                    if [[ $(git status --porcelain) ]]; then
                        log_ignored "You have uncommitted changes, please stash these changes"
                        continue
                    fi

                    git fetch -q "${remote}" > /dev/null

                    git checkout -q "${BRANCH}" > /dev/null && git rebase "${remote}"/"${BRANCH}" > /dev/null
                else
                    git checkout -q "${BRANCH}" > /dev/null
                fi


                # if we need to replace a multi-line match in the pom file of each booster, for example:
                # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

                # if we need to execute sed on the result of find:
                # find . -name "application.yaml" -exec sed -i '' -e "s/provider: fabric8/provider: snowdrop/g" {} +

                log "Executing '${YELLOW}${cmd}${BLUE}'"
                # let the command fail without impacting the main loop, let the command decide on what to log / fail / ignore
                if ! ${cmd}; then
                    log "Done"
                    echo
                    continue
                fi

                log "Done"
                processedItem="${BRANCH}:${BOOSTER}"
                processed+=( "${processedItem}" )
                echo
            done
        fi

        echo -e "----------------------------------------------------------------------------------------\n"
        popd > /dev/null
    fi
done

if [ ${#processed[@]} != 0 ]; then
    echo -e "${BLUE}${#processed[@]} booster/branch combinations were processed:${YELLOW}"
    printf '\t%s\n' "${processed[@]}"
fi

if [ ${#failed[@]} != 0 ]; then
    echo -e "${BLUE}${#failed[@]} booster/branch combinations failed:${RED}"
    printf '\t%s\n' "${failed[@]}"
fi

if [ ${#ignored[@]} != 0 ]; then
    echo -e "${BLUE}${#ignored[@]} booster/branch combinations  were skipped:${MAGENTA}"
    printf '\t%s\n' "${ignored[@]}"
fi
