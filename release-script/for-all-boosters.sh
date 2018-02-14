#!/bin/bash
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
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
        for BRANCH in {redhat,master}
        do
            # assumes "official" remote is named 'upstream'
            git fetch upstream >/dev/null && git co $BRANCH >/dev/null && git rebase upstream/$BRANCH >/dev/null

            # if we need to replace a multi-line match in the pom file of each booster, for example:
            # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

            if [ -e "$1" ]; then
                echo -e "${BLUE}Running ${YELLOW}${1}${BLUE} script on ${YELLOW}${BRANCH}${BLUE} branch of ${YELLOW}${BOOSTER}.${NC}"
                source $1
            else
                echo -e "${BLUE}No script was provided or ${YELLOW}${1}${BLUE} doesn't exist in ${YELLOW}`pwd`${BLUE} directory.${NC}"
                echo -e "${BLUE}Only refreshed local code.${NC}"
            fi
        done
        popd >/dev/null
        echo -e "${BLUE}==> Processing ${YELLOW}${BRANCH}${BLUE} branch of ${YELLOW}${BOOSTER}${BLUE} finished.${NC}"
    fi
done
