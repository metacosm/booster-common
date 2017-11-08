#!/bin/bash
set -e

##
# TODO:
#  - parameterize Spring Boot version to use in booster.yaml via script param
#  - update booster-catalog with versions as we go
#  - better error handling
#  - automate booster catalog update:
#       - introduce map between booster git name and path in booster catalog
#           see: https://stackoverflow.com/questions/1494178/how-to-define-hash-tables-in-bash
#       - need to locate local booster-catalog copy
#       - update YAML files
#       - leave commit and push to remote as a manual step?


RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

if ((`git status -sb | wc -l` != 1)); then
    echo -e "${RED}You have uncommitted changes, please check (and stash) these changes before running this script${NC}"
    exit 1
fi

if [ -z "$CATALOG_FILE" ]; then
    CATALOG_FILE=/dev/null
fi

if [ -z "$BOOSTER" ]; then
    BOOSTER=$(basename `pwd`)
fi

# run mvn help:evaluate once first since it often needs to download stuff which screws up version parsing
mvn help:evaluate -Dexpression=project.version > /dev/null

# check that we have proper git information to automatically commit and push
# git status -sb has the following format: ## master...upstream/master when tracking a remote branch
GIT_STATUS=`git status -sb`
GIT_STATUS_PARTS=${GIT_STATUS//##/}
GIT_STATUS_PARTS=(${GIT_STATUS_PARTS//.../ })
GIT_BRANCH=${GIT_STATUS_PARTS[0]}
GIT_REMOTE=(${GIT_STATUS_PARTS[1]//\// })
if [[ "$GIT_REMOTE" == ?? ]]; then
    echo -e "${RED}Current ${YELLOW}${GIT_BRANCH}${RED} branch is not tracking a remote. Please make sure your branch is tracking a remote (git branch -u <remote name>/<remote branch name>)!${NC}"
    exit 1
fi
GIT_REMOTE=${GIT_REMOTE[0]}
GIT_BRANCH=${GIT_REMOTE[1]}

CURRENT_VERSION=`mvn help:evaluate -Dexpression=project.version | grep -e '^[^\[]'`
echo -e "${BLUE}CURRENT VERSION: ${YELLOW} ${CURRENT_VERSION} ${NC}"

if [[ "$CURRENT_VERSION" == *-SNAPSHOT ]]
then
    L=${#CURRENT_VERSION}
    PART=(${CURRENT_VERSION//-/ })
    NEW_VERSION_INT=${PART[0]}
    QUALIFIER=${PART[1]}
    SNAPSHOT=${PART[2]}
    if [[ "$SNAPSHOT" == SNAPSHOT ]]
    then
        PREVIOUS_VERSION="$(($NEW_VERSION_INT -1))-${QUALIFIER}"
        NEW_VERSION="${NEW_VERSION_INT}-${QUALIFIER}"
        NEXT_VERSION="$(($NEW_VERSION_INT +1))-${QUALIFIER}-SNAPSHOT"
    else
        PREVIOUS_VERSION="$(($NEW_VERSION_INT -1))"
        NEW_VERSION="${NEW_VERSION_INT}"
        NEXT_VERSION="$(($NEW_VERSION_INT +1))-SNAPSHOT"
    fi
else
    echo -e "${RED} The current version (${CURRENT_VERSION}) is not a SNAPSHOT ${NC}"
    exit 1
fi

# TODO: update booster.yaml if needed
#if [ -e "$1" ]; then
#    sed -i '' -e 's/name: \d.\d.\d./name: ${1}./g' .openshiftio/booster.yaml
#    if git diff-index --quiet HEAD --
#    then
#        echo -e "${BLUE}There was no changes to ${YELLOW}booster.yaml${BLUE}. Please check!${NC}"
#        exit 1
#    else
#        echo -e "${BLUE}Updating ${YELLOW}booster.yaml${NC}"
#        git commit -am "Updating booster.yaml to 1.5.8"
#    fi
#fi

echo -e "${BLUE}Moving templates from ${PREVIOUS_VERSION} version to ${NEW_VERSION} ${NC}"
for FILE in `find . -name "application.yaml"`
do
    # curl -s "https://raw.githubusercontent.com/openshiftio/launchpad-templates/master/scripts/create-launch-templates.sh" | bash
    echo -e "${BLUE}Updating ${YELLOW}${FILE}${BLUE} template to ${YELLOW}${NEW_VERSION}${BLUE} version${NC}"
    sed -i '' -e "s/:${PREVIOUS_VERSION}/:${NEW_VERSION}/g" $FILE
    sed -i '' -e "s/version: \"${PREVIOUS_VERSION}/version: \"${NEW_VERSION}/g" $FILE
    sed -i '' -e "s/var-version=${PREVIOUS_VERSION}/var-version=${NEW_VERSION}/g" $FILE
    sed -i '' -e "s/value: sb-1.5.x/value: master/g" $FILE
    sed -i '' -e "s/value: redhat/value: master/g" $FILE
done

# Open the current booster in Idea to double check
idea .

echo -e "${BLUE}Press a key to continue when you're done checking the templates or ctrl-c to abort.${NC}"
echo -e "${BLUE}If you abort, you can get back to starting status by calling: ${YELLOW}git reset --hard ${GIT_REMOTE}/${GIT_BRANCH}.${NC}"
read foo

# Only attempt committing if we have changes otherwise the script will exit
if ! git diff-index --quiet HEAD --
then
    echo -e "${BLUE}Committing changes${NC}"
    git commit -am "Updating templates to ${NEW_VERSION}"
fi


echo -e "${BLUE}Updating project version to: ${YELLOW} ${NEW_VERSION} ${NC}"
mvn versions:set -DnewVersion=${NEW_VERSION} > bump-version.log

echo -e "${BLUE}Issuing a verification build${NC}"
mvn clean verify > verification.log

echo -e "${BLUE}Committing changes${NC}"
git commit -am "Bumping version to ${NEW_VERSION}"

TAG="v${NEW_VERSION}"
echo -e "${BLUE}Creating the tag ${YELLOW}${TAG}${NC}"
git tag -a ${TAG} -m "Releasing ${TAG}"

echo -e "${BLUE}Updating project version to: ${YELLOW}${NEXT_VERSION}${NC}"
mvn versions:set -DnewVersion=${NEXT_VERSION} > bump-version-dev.log

echo -e "${BLUE}Committing changes${NC}"
git commit -am "Bumping version to ${NEXT_VERSION}"

echo -e "${BLUE}Pushing changes to ${YELLOW}${GIT_BRANCH}${BLUE} branch of ${YELLOW}${GIT_REMOTE}${BLUE} remote${NC}"
git push $GIT_REMOTE $GIT_BRANCH --tags

echo -e "${BLUE}Appending new version ${YELLOW}${NEW_VERSION}${BLUE} for ${YELLOW}${GIT_BRANCH}${BLUE} branch to ${YELLOW}${CATALOG_FILE}${NC}"
echo "${BOOSTER}: ${GIT_BRANCH} => ${NEW_VERSION}" >> "$CATALOG_FILE"

echo -e "DONE !"
rm *.log
find . -name "*.versionsBackup" -exec rm -f {} \;