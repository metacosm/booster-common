#!/usr/bin/env bash

# Releases a new BOM based on a new Spring Boot version
# Updates the boosters for this new BOM so that they can be tested
set -e

# Defining some colors for output
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

simple_log() {
    echo -e "${BLUE}${1}${NC}"
}

# get the directory of the script
CMD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)"

# create a temporary directory WORK_DIR to be removed at the exit of the script
# see: https://stackoverflow.com/questions/4632028/how-to-create-a-temporary-directory
# ====
WORK_DIR=$(mktemp -d)

# check if tmp dir was created
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    simple_log "Could not create temp directory"
    exit 1
fi

# deletes the temp directory
function cleanup {
    rm -rf "$WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
trap cleanup EXIT
# ====


error() {
    echo -e "${RED}Error: ${1}${NC}"
    exit ${2:-1}
}

# compute BOM branch based on provided SB version
simple_log "Releases a new BOM based on the specified Spring Boot version in the x.y.zz form."
simple_log "Updates the boosters for this new BOM so that they can be tested."
declare -r sbVersion=${1?"Must provide a target Spring Boot version in the x.y.zz form"}
if [[ ${sbVersion} =~ ([1-9].[0-9]).([0-9]+) ]]; then
    sbMajorVersion="${BASH_REMATCH[1]}"
    bomBranch="sb-${sbMajorVersion}.x"
    nextBOMVersion="${sbMajorVersion}.$((${BASH_REMATCH[2]} + 1))-SNAPSHOT"
else
    error "Unsupported Spring Boot version: ${sbVersion}" 1>&2
fi

# Clone BOM project in temp dir
cd ${WORK_DIR}
git clone git@github.com:snowdrop/spring-boot-bom.git >/dev/null 2>/dev/null
pushd spring-boot-bom
git checkout ${bomBranch}

# update the BOM based on SB version (presumably other dependencies have already been updated)
pushd ${CMD_DIR}/src/
groovy update-pom.groovy ${WORK_DIR}/spring-boot-bom/pom.xml ${sbVersion} "hibernate.version=,hibernate-validator.version="
popd
mvn install

# release the BOM
releaseVersion="${sbVersion}.Final"
mvn -B release:prepare -Prelease -Dtag="${releaseVersion}" -DreleaseVersion="${releaseVersion}" -DdevelopmentVersion="${nextBOMVersion}"
mvn release:perform -Prelease
popd

# update the boosters for the new SB version
./for-all-boosters.sh -pn -l boosters-release set_maven_property -v "spring-boot-bom.version" "${releaseVersion}"
./for-all-boosters.sh -f -l boosters-release set_maven_property -v "spring-boot.version" "${sbVersion}"
./for-all-boosters.sh -f -l boosters-release change_version -v "${sbVersion}-1-SNAPSHOT"




