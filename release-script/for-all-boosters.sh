#!/bin/bash

set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'

CURRENT_DIR=`pwd`
CATALOG_FILE=$CURRENT_DIR"/booster-catalog-versions.txt"
rm "$CATALOG_FILE"
touch "$CATALOG_FILE"

evaluate_mvn_expr() {
    # Evaluate the given maven expression, cf: https://stackoverflow.com/questions/3545292/how-to-get-maven-project-version-to-the-bash-command-line
    result=`mvn -q -Dexec.executable="echo" -Dexec.args='${'${1}'}' --non-recursive exec:exec`
    echo $result
}

log() {
    currentBranch=${2:-$BRANCH}
    echo -e "\t${GREEN}${currentBranch}${BLUE}: ${1}${NC}"
}

log_branch() {
    log ${1} ${branch}
}

update_parent() {
    # Retrieve current parent version
    PARENT_VERSION=$(evaluate_mvn_expr "project.parent.version")
    parts=( ${PARENT_VERSION//-/ } )
    sb_version=${parts[0]}
    version_int=${parts[1]}
    qualifier=${parts[2]}
    snapshot=${parts[3]}

    # to output parts:
    # echo "${parts[@]}"

    given_version=$1

    # todo: use getopts instead
    # arguments from parent are passed to this script so $2 corresponds to the first param *after* the name of this script
    if [ -n "$given_version" ]; then
        log "Current parent (${YELLOW}${PARENT_VERSION}${BLUE}) will be replaced by version: ${YELLOW}${given_version}"
        NEW_VERSION=${given_version}
    else
        if [[ "$snapshot" == SNAPSHOT ]]
        then
            NEW_VERSION="${sb_version}-$(($version_int +1))-${qualifier}-${snapshot}"
        else
            if [ -n "${qualifier}" ]
            then
                NEW_VERSION="${sb_version}-$(($version_int +1))-${qualifier}"
            else
                NEW_VERSION="${sb_version}-$(($version_int +1))"
            fi
        fi
    fi

    log "Updating parent from ${YELLOW}${PARENT_VERSION}${BLUE} to ${YELLOW}${NEW_VERSION}"

    sed -i '' -e "s/<version>${PARENT_VERSION}</<version>${NEW_VERSION}</g" pom.xml

    # Only attempt committing if we have changes otherwise the script will exit
    if [[ `git status --porcelain` ]]; then

        log "Running verification build"
        if mvn clean verify > build.log; then
            log "Build ${YELLOW}OK"
            rm build.log

            log "Committing and pushing"
            git add pom.xml
            git ci -m "Update to parent ${NEW_VERSION}"
            git push upstream ${BRANCH}
        else
            log "Build ${RED}failed${BLUE}! Check build.log file."
            log "You will need to reset the branch or explicitly set the parent before running this script again."
        fi

    else
        log "Parent was already at ${YELLOW}${NEW_VERSION}${BLUE}. Ignoring."
    fi
}

change_version() {
    if [ -n "$1" ]; then
        newVersion=$1
        if mvn versions:set -DnewVersion=${newVersion} > /dev/null; then
            if [[ `git status --porcelain` ]]; then
                log "Changed version to ${YELLOW}${newVersion}"
                log "Running verification build"
                if mvn clean verify > build.log; then
                    log "Build ${YELLOW}OK"
                    rm build.log

                    log "Committing and pushing"

                    if [ -n "$2" ]; then
                        jira=${2}": "
                    else
                        jira=""
                    fi

                    git ci -am ${jira}"Update version to ${newVersion}"
                    git push upstream ${BRANCH}
                else
                    log "Build ${RED}failed${BLUE}! Check build.log file."
                    log "You will need to reset the branch or explicitly set the parent before running this script again."
                fi

            else
                log "Version was already at ${YELLOW}${newVersion}${BLUE}. Ignoring."
            fi

            find . -name "*.versionsBackup" -delete
        else
            log "${RED}Couldn't set version. Reverting to upstream version."
            git reset --hard upstream/${BRANCH}
        fi
    fi
}

declare -a failed=( )
for BOOSTER in `ls -d spring-boot-*-booster`
do
    #if [ "$BOOSTER" != spring-boot-circuit-breaker-booster ] && [ "$BOOSTER" != spring-boot-configmap-booster ] && [ "$BOOSTER" != spring-boot-crud-booster ]
    if true; then
        pushd ${BOOSTER} > /dev/null

        echo -e "${BLUE}> ${YELLOW}${BOOSTER}${BLUE}${NC}"

        for BRANCH in "master" "redhat"
        do
            # assumes "official" remote is named 'upstream'
            git fetch upstream > /dev/null

            # check if branch exists, otherwise skip booster
            if ! git show-ref --verify --quiet refs/heads/${BRANCH}; then
                log "${RED}Branch doesn't exist. Skipping."
            else
                git co -q ${BRANCH} > /dev/null && git rebase upstream/${BRANCH} > /dev/null

                # if we need to replace a multi-line match in the pom file of each booster, for example:
                # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

                if [ -e "$1" ]; then
                    script=$1
                    log "Running ${YELLOW}${script}${BLUE} script"
                    if ! source $1; then
                        log "${RED}Error running script"
                        failed+=( ${BOOSTER} )
                    fi
                else
                    log "No script provided. Only refreshed code."

                fi
            fi
        done

        echo -e "----------------------------------------------------------------------------------------\n"
        popd > /dev/null
    fi
done

if [ ${#failed[@]} != 0 ]; then
    echo -e "${RED}The following boosters were in error: ${YELLOW}"$(IFS=,; echo "${failed[*]}")
fi
