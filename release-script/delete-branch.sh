#!/bin/bash
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
BLUE='\033[0;34m'


if git ls-remote --heads upstream ${BRANCH} | grep ${BRANCH} >/dev/null ;
then
  echo -e "${BLUE}Are you sure you want to delete ${YELLOW}${BRANCH}${BLUE} branch on remote ${YELLOW}upstream${BLUE} for ${YELLOW}${BOOSTER}${BLUE}?${NC}"
  echo -e "${BLUE}Press any key to continue or ctrl-c to abort.${NC}"
  read foo

  git push -d upstream ${BRANCH}
else
  echo -e "${BLUE}Branch ${YELLOW}${BRANCH}${BLUE} doesn't exist on remote ${YELLOW}upstream${BLUE} of ${YELLOW}${BOOSTER}${BLUE}. Ignoring.${NC}"
fi

if ! git branch -D ${BRANCH} >/dev/null 2>/dev/null;
then
  echo -e "${BLUE}Branch ${YELLOW}${BRANCH}${BLUE} doesn't exist locally for ${YELLOW}${BOOSTER}${BLUE}. Ignoring.${NC}"
fi
