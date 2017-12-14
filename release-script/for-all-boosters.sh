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
        pushd $BOOSTER
        for BRANCH in {redhat,master}
        do
            git fetch upstream && git co $BRANCH && git rebase upstream/$BRANCH
            if [ -e "$1" ]; then
                echo -e "${BLUE}Running ${YELLOW}${1}${BLUE} script on ${YELLOW}${BRANCH}${BLUE} of ${YELLOW}${BOOSTER}.${NC}"
                source $1
            else
                echo -e "${BLUE}No script was provided or ${YELLOW}${1}${BLUE} doesn't exist in ${YELLOW}`pwd`${BLUE} directory.${NC}"
                echo -e "${BLUE}Only refreshed local code.${NC}"
            fi
        done
        popd
    fi
done
