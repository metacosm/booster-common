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

for BOOSTER in `ls -d spring-boot-*-booster`
do
    #if [ "$BOOSTER" != spring-boot-circuit-breaker-booster ] && [ "$BOOSTER" != spring-boot-configmap-booster ] && [ "$BOOSTER" != spring-boot-crud-booster ]
    if true ;
    then
        pushd $BOOSTER >/dev/null

        echo -e "${BLUE}> ${YELLOW}${BOOSTER}${BLUE}${NC}"

        for BRANCH in redhat
        do
            # assumes "official" remote is named 'upstream'
            git fetch upstream >/dev/null

            # check if branch exists, otherwise skip booster
            if ! git show-ref --verify --quiet refs/heads/${BRANCH}; then
                echo -e "\t${GREEN}${BRANCH}${BLUE}: ${RED}Branch doesn't exist. Skipping.${NC}"
            else
                git co -q ${BRANCH} >/dev/null && git rebase upstream/${BRANCH} >/dev/null

                # if we need to replace a multi-line match in the pom file of each booster, for example:
                # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

                if [ -e "$1" ]; then
                    echo -e "\t${GREEN}${BRANCH}${BLUE}: Running ${YELLOW}${1}${BLUE} script.${NC}"
                    source $1
                else
                    echo -e "\t${GREEN}${BRANCH}${BLUE}: No script provided. Only refreshed code.${NC}"
                fi
            fi
        done

        echo -e "----------------------------------------------------------------------------------------\n"
        popd >/dev/null
    fi
done
