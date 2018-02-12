#!/bin/bash
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
BLUE='\033[0;34m'


if git ls-remote --heads upstream ${BRANCH} | grep ${BRANCH} >/dev/null ;
then
  echo -e "${BLUE}A ${YELLOW}${BRANCH}${BLUE} branch already exists on remote ${YELLOW}upstream${BLUE} for ${YELLOW}${BOOSTER}${BLUE}. Ignoring.${NC}"
else
  if ! git co -b ${BRANCH} >/dev/null 2>/dev/null;
  then
    echo -e "${BLUE}Couldn't create ${YELLOW}${BRANCH}${BLUE} for ${YELLOW}${BOOSTER}${BLUE}. Ignoring.${NC}"
  fi

#  If changes are needed in the pom of the new branch, e.g. to change the version of the booster parent… ;)
#  sed -i '' -e "s/<version>1.5.10.Beta2</<version>1.5.10-2</g" pom.xml
  
  echo -e "${BLUE}Created branch ${YELLOW}${BRANCH}${BLUE} and pushed it to remote ${YELLOW}upstream${BLUE} of ${YELLOW}${BOOSTER}${BLUE}.${NC}"
  git push upstream ${BRANCH}
fi

