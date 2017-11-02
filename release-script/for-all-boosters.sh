#!/bin/bash
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

for BOOSTER in `ls -d spring-boot-*-booster`
do
    #if [ "$BOOSTER" != spring-boot-circuit-breaker-booster ] && [ "$BOOSTER" != spring-boot-configmap-booster ] && [ "$BOOSTER" != spring-boot-crud-booster ]
    if true ;
    then
        pushd $BOOSTER
        for BRANCH in {redhat,sb-1.5.x}
        do
            if [ -e "$1" ]; then
                echo -e "${BLUE}Running ${YELLOW}${1}${BLUE} script on ${YELLOW}${BRANCH}${BLUE} of ${YELLOW}${BOOSTER}.${NC}"
                git fetch upstream && git co $BRANCH && git rebase upstream/$BRANCH
                source $1
            fi
        done
        popd
    fi
done
