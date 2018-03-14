#!/bin/bash
set -e

RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

CURRENT_DIR=`pwd`

if [ -z "$1" ]; then
    echo -e "${RED}You must provide a branch name from which descriptor changes will be applied to the current branch${NC}"
    exit 1
fi

if ((`git status -sb | wc -l` != 1)); then
    echo -e "${RED}You have uncommitted changes, please check (and stash) these changes before running this script${NC}"
    exit 1
fi


HAS_SUB_MODULES=0
if ((`find . -name "pom.xml" | wc -l` > 1)); then
    HAS_SUB_MODULES=1
    echo -e "${YELLOW}/!\/!\/!\ You have submodules, this script might not work properly. Changes will thus not be pushed automatically so you can review them first.${NC}"
    echo ""
fi


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

if ((`git branch --list -r "${GIT_REMOTE}/${1}" | wc -l` != 1)); then
    echo -e "${YELLOW}${GIT_REMOTE}/${1}${RED} does not exist. Please check the origin name and try again.${NC}"
    exit 1
fi

REMOTE=$(git remote get-url $GIT_REMOTE)
echo -e "${BLUE}Cloned ${YELLOW}${REMOTE}${BLUE} repository and checked out ${YELLOW}$1${BLUE} branch to apply changes to its YAML files to the current ${YELLOW}${GIT_BRANCH}${BLUE}.${NC}"
rm -rf /tmp/yaml-sync && git clone -q "${REMOTE}" /tmp/yaml-sync
pushd /tmp/yaml-sync
git checkout $1
NEW_YAML_FILES=(`find . -name "*.yaml"`)
popd

for FILE in `find . -name "*.yaml"`
do
    git rm $FILE
done

ptouch() {
  for p do
    _dir="$(dirname -- "$p")"
    mkdir -p -- "$_dir" &&
      touch -- "$p"
  done
}

for FILE in ${NEW_YAML_FILES[*]}
do
    echo -e "${BLUE}Copying ${YELLOW}${FILE}${BLUE} file.${NC}"

    # make sure target file exists otherwise copy will fail
    ptouch $FILE
    cp /tmp/yaml-sync/$FILE $FILE 2>/dev/null || :

    # If we passed a second argument to this script, attempt to interpret it as a script to run on each synced file.
    # Note that variables defined in this script will be available to the specified one. So, for example, the following script:
    # #!/bin/bash
    # sed -i '' -e 's/1.4.1/1.5.7/g' ${FILE}
    # will change all instances of the 1.4.1 string to 1.5.7 in the specified file
    if [ -e "$2" ]; then
        echo -e "${BLUE}Running ${YELLOW}${2}${BLUE} script on ${YELLOW}${FILE}${BLUE} file.${NC}"
        source $2
    fi

    git add $FILE
done


git commit -m "Updated YAML files based on $1 branch"

if ((${HAS_SUB_MODULES} == 0)); then
    echo -e "${BLUE}Pushing to ${YELLOW}${GIT_BRANCH}${BLUE} branch of ${YELLOW}${GIT_REMOTE}${BLUE} remote${NC}"
    git push $GIT_REMOTE $GIT_BRANCH
else
    echo -e "${BLUE}Please review your changes before pushing to ${YELLOW}${GIT_BRANCH}${BLUE} branch of ${YELLOW}${GIT_REMOTE}${BLUE} remote${NC}"
fi

rm -rf /tmp/yaml-sync
