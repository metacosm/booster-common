#!/bin/bash
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

# DANGER: THIS SCRIPT WILL AUTOMATICALLY MODIFY PARENT AND PUSH MODIFICATIONS IF NO ARGUMENT IS PROVIDED. USE WITH CARE!

# Retrieve current parent version
PARENT_VERSION=`mvn help:evaluate -Dexpression=project.parent.version | grep -e '^[^\[]'`
parts=(${PARENT_VERSION//-/ })
sb_version=${parts[0]}
version_int=${parts[1]}
qualifier=${parts[2]}
snapshot=${parts[3]}

# to output parts:
# echo "${parts[@]}"

given_version=$2

# todo: use getopts instead
# arguments from parent are passed to this script so $2 corresponds to the first param *after* the name of this script
if [ -n "$given_version" ]; then
    echo -e "${BLUE}The current parent version (${YELLOW}${PARENT_VERSION}${BLUE}) will be replaced by new version: ${YELLOW}${given_version}${NC}"
    NEW_VERSION=${given_version}
else
    if [[ "$snapshot" == SNAPSHOT ]]
    then
        NEW_VERSION="${sb_version}-$(($version_int +1))-${qualifier}-${snapshot}"
    else
        NEW_VERSION="${sb_version}-$(($version_int +1))"
    fi
fi

echo -e "${BLUE}Updating parent from ${YELLOW}${PARENT_VERSION}${BLUE} to ${YELLOW}${NEW_VERSION}${BLUE} for ${YELLOW}${BOOSTER}${BLUE}.${NC}"
sed -i '' -e "s/<version>${PARENT_VERSION}</<version>${NEW_VERSION}</g" pom.xml

# Only attempt committing if we have changes otherwise the script will exit
if [[ `git status --porcelain` ]]; then
    echo -e "${BLUE}Running verification build.${NC}"
    mvn clean install

    echo -e "${BLUE}Committing and pushing${NC}"
    git add pom.xml
    git ci -m "Update to parent ${NEW_VERSION}"
    git push upstream ${BRANCH}
else
    echo -e "${BLUE}Parent was already at ${YELLOW}${NEW_VERSION}${BLUE}. Ignoring.${NC}"
fi