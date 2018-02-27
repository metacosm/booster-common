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
    # run evaluate once first to avoid downloading artifacts interfering with expected results, expression should fail fast
    mvn help:evaluate -Dexpression=a >/dev/null

    # Retrieve current parent version
    result=`mvn help:evaluate -Dexpression=${1} | grep -e '^[^\[]'`
    echo $result
}

log () {
    echo -e "\t${GREEN}${BRANCH}${BLUE}: ${1}${NC}"
}
for BOOSTER in `ls -d spring-boot-*-booster`
do
    #if [ "$BOOSTER" != spring-boot-circuit-breaker-booster ] && [ "$BOOSTER" != spring-boot-configmap-booster ] && [ "$BOOSTER" != spring-boot-crud-booster ]
    if true ;
    then
        pushd $BOOSTER >/dev/null

        echo -e "${BLUE}> ${YELLOW}${BOOSTER}${BLUE}${NC}"

        for BRANCH in redhat master
        do
            # assumes "official" remote is named 'upstream'
            git fetch upstream >/dev/null

            # check if branch exists, otherwise skip booster
            if ! git show-ref --verify --quiet refs/heads/${BRANCH}; then
                log "${RED}Branch doesn't exist. Skipping."
            else
                git co -q ${BRANCH} >/dev/null && git rebase upstream/${BRANCH} >/dev/null

                # if we need to replace a multi-line match in the pom file of each booster, for example:
                # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

                if [ -e "$1" ]; then
                    log "Running ${YELLOW}${1}${BLUE} script"
                    source $1
                else
                    log "No script provided. Only refreshed code."
                fi
            fi
        done

        echo -e "----------------------------------------------------------------------------------------\n"
        popd >/dev/null
    fi
done
