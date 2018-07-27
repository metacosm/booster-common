#!/usr/bin/env bash
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

simple_log "Script to release the boosters once QA has validated them with the prod BOM."
simple_log "You need to be connected to the VPN to be able to successfully run this script."

declare -r sbVersion=${1?"Must provide a target Spring Boot version in the x.y.zz form"}
for-all-boosters.sh -pn -l ${WORK_DIR}/boosters-release release ${sbVersion}
for-all-boosters.sh -f -l ${WORK_DIR}/boosters-release catalog ${sbVersion}
