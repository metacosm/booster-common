#!/bin/bash

# A script to process boosters
set -e

# Defining some colors for output
RED='\033[0;31m'
NC='\033[0m' # No Color
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'

simple_log () {
    echo -e "${BLUE}${1}${NC}"
}

# create a temporary directory WORK_DIR to be removed at the exit of the script
# see: https://stackoverflow.com/questions/4632028/how-to-create-a-temporary-directory
# Note: this is currently unused and uses a nested function as seen here: https://stackoverflow.com/a/31316688
# ====
create_auto_deleted_temp_dir() (

    WORK_DIR=$(mktemp -d)
    simple_log "Created temp working directory $WORK_DIR"

# check if tmp dir was created
    if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    simple_log "Could not create temp directory"
    exit 1
    fi

# deletes the temp directory
    function cleanup {
    rm -rf "$WORK_DIR"
    simple_log "Deleted temp working directory $WORK_DIR"
}

# register the cleanup function to be called on the EXIT signal
    trap cleanup EXIT
)
# ====


# script-wide toggle controlling pushes from functions
PUSH='on'

# script-wide toggle controlling commits from functions
COMMIT='on'

# script-wide toggle to bypass local changes check
IGNORE_LOCAL_CHANGES='off'

# script-wide toggle to bypass checking out boosters from github
PERFORM_BOOSTER_LOCAL_SETUP='off'

# script-wide toggle to bypass branch existence check, needed to be able to create branches
CREATE_BRANCH='off'

# script-wide toggle to controlling whether input-confirmation will be shown or not
CONFIRMATION_NEEDED='on'

# script-wide toggle to control whether the tests should be executed or not
RUN_TESTS='on'

# boosters directory (where all the local booster copies are located), defaults to working dir
BOOSTERS_DIR=$(pwd)

# failed boosters
declare -a failed=( )

# skipped boosters
declare -a ignored=( )

# processed boosters
declare -a processed=( )

maven_settings() {
    if [[ -z "${MAVEN_SETTINGS}" ]]; then
      echo ""
    else
      echo " --settings ${MAVEN_SETTINGS} "
    fi
}

maven_tests_expression() {
  if [[ "$RUN_TESTS" == on ]]; then
    echo ""
  else
    echo " -DskipTests "
  fi
}

evaluate_mvn_expr() {
    # Evaluate the given maven expression, cf: https://stackoverflow.com/questions/3545292/how-to-get-maven-project-version-to-the-bash-command-line
    result=$(mvn $(maven_settings) -q -Dexec.executable="echo" -Dexec.args='${'${1}'}' --non-recursive exec:exec)
    echo ${result}
}

current_branch() {
    currentBranch=${branch:-$BRANCH}
    echo ${currentBranch}
    unset currentBranch
}

log() {
    echo -e "\t${GREEN}$(current_branch)${BLUE}: ${1}${NC}"
}

log_without_branch() {
    echo -e "\t${BLUE}${1}${NC}"
}

log_ignored() {
   log "${MAGENTA}${1}${MAGENTA}. Ignoring."
   ignoredItem="$(current_branch):${BOOSTER}:\"${1}\""
   ignored+=( "${ignoredItem}" )
}

log_failed() {
   log "${RED}ERROR: ${1}${RED}"
   failedItem="$(current_branch):${BOOSTER}:\"${1}\""
   failed+=( "${failedItem}" )
}

push_to_remote() {
    currentBranch=${branch:-$BRANCH}
    local remoteToPushTo=${1}
    options=${2:-}

    if [[ "$PUSH" == on ]]; then
        if git push ${options} "${remoteToPushTo}" "${currentBranch}" > /dev/null; then
            log "Pushed to ${remoteToPushTo}"
        else
            log_ignored "Failed to push to ${remoteToPushTo}"
        fi
    fi
    unset currentBranch
}

commit() {
    if [[ "$COMMIT" == on ]]; then
        log "Commit: '${1}'"
        git commit -q -am "${1}"
    fi
}

compute_new_version() {
    version_expr=${1:-project.version}
    current_version=$(evaluate_mvn_expr ${version_expr})

    parts=( ${current_version//-/ } )
    sb_version=${parts[0]}
    version_int=${parts[1]}
    qualifier=${parts[2]}
    snapshot=${parts[3]}

    # to output parts:
    # echo "${parts[@]}"

    if [[ "$snapshot" == SNAPSHOT ]]
    then
        new_version="${sb_version}-$((version_int +1))-${qualifier}-${snapshot}"
    else
        if [ -n "${qualifier}" ]
        then
            new_version="${sb_version}-$((version_int +1))-${qualifier}"
        else
            new_version="${sb_version}-$((version_int +1))"
        fi
    fi

    echo ${new_version}
}

get_latest_tag() {
    local latestTag
    latestTag=$(git describe --tags --abbrev=0 2> /dev/null)
    if [  $? -eq 0  ]; then
        echo ${latestTag}
    else
        echo "Not tagged yet"
    fi
}

# check that first arg is contained in array second arg
# see: https://stackoverflow.com/a/8574392
element_in() {
    local e match="$1"
    shift
    for e; do
        [[ "$e" == "$match" ]] && return 0;
    done
    return 1
}

verify_maven_project_setup() {
    mvn $(maven_settings) dependency:analyze > /dev/null
    if [ $? -ne 0 ]; then
      log_failed "Unable to verify that the booster was setup correctly locally - some dependencies seem to be missing"
      # Definitely not the optimal solution for handling errors
      # If we were however to do proper error handling for each booster / branch combination
      # we would need to propagate errors (and perhaps the error types) all the way up the call stack
      # to the main booster / branch control loop
      exit 1
    fi
}

change_version() {
    # The first thing we do is make sure the project's dependencies are valid
    # This is done because if it were not,
    # the change_version function would try to interpret the Maven errors as a Maven version
    # resulting in weird behavior for code that uses the results of changes_version
    # The final error messages that are printed in the console do not provide the user of the script
    # with a clear indication of what went wrong
    verify_maven_project_setup

    newVersion=${1:-compute}
    targetParent=${2:-false}

    # if we provide a 3rd arg, switch to parent processing instead
    expr="project.version"
    target="project"
    if [ "${targetParent}" == true ]; then
        expr="project.parent.version"
        target="parent"
    fi

    # if provided version is "compute" then compute the new version :)
    if [[ "${newVersion}" == compute ]]; then
        newVersion=$(compute_new_version ${expr})
    fi

    currentVersion=$(evaluate_mvn_expr ${expr})
    local cmd="mvn $(maven_settings) versions:set -DnewVersion=${newVersion} > /dev/null"
    if [ "${targetParent}" == true ]; then
        local escapedCurrent=$(sed 's|[]\/$*.^[]|\\&|g' <<< ${currentVersion})
        # see: https://unix.stackexchange.com/a/92907
        cmd="perl -pi -e 's/<version>${escapedCurrent}</<version>${newVersion}</g' pom.xml"
    fi
    
    if eval ${cmd}; then
        # Only attempt committing if we have changes otherwise the script will exit
        if [[ $(git status --porcelain) ]]; then
            log "Updated ${target} from ${YELLOW}${currentVersion}${BLUE} to ${YELLOW}${newVersion}"
            log "Running verification build"
            if mvn $(maven_settings) $(maven_tests_expression) clean verify > build.log; then
                log "Build ${YELLOW}OK"
                rm build.log

                if [ -n "$3" ]; then
                    jira=${3}": "
                else
                    jira=""
                fi
                commit ${jira}"Update ${target} version to ${newVersion}"

                push_to_remote "${remote}"

                # When dry-run is enabled, revert local changes in order leave things the way we found them :)
                if [[ "$COMMIT" == off ]]; then
                  CONFIRMATION_NEEDED='off'
                  revert
                fi
            else
                log_failed "Build failed! Check ${YELLOW}build.log"
                log "You will need to reset the branch or explicitly set the parent before running this script again."
            fi

        else
            log_ignored "Version was already at ${YELLOW}${newVersion}"
        fi

        find . -name "*.versionsBackup" -delete
    else
        log_failed "Couldn't set version. Reverting to remote ${remote} version."
        git reset --hard "${remote}"/"${BRANCH}"
    fi
}

setup_booster_locally () {
    local booster_name=${1}
    local booster_git_url=${2}

    log_without_branch "Setting up locally"

    if [ ! -d "${booster_name}" ]; then
      git clone -q -o ${remote} ${booster_git_url} > /dev/null 2>&1
      pushd ${booster_name} > /dev/null
    else
      pushd ${booster_name} > /dev/null
      git fetch -q ${remote}
      BRANCH=$(git rev-parse --abbrev-ref HEAD)
      revert
      unset BRANCH
    fi

    for branch in ${branches[@]}
    do
      if git show-ref -q refs/heads/${branch}; then
        git checkout -q ${branch}
        git reset -q --hard ${remote}/${branch}
        git clean -f -d
      else
        if git ls-remote --heads --exit-code ${booster_git_url} ${branch} > /dev/null; then
          git checkout -q --track ${remote}/${branch}
        fi
      fi
    done

    popd > /dev/null
    unset branch
}

create_branch() {
    branch=${1:-$BRANCH}

    if git ls-remote --heads "${remote}" "${branch}" | grep "${branch}" > /dev/null;
    then
        log_ignored "Branch already exists on remote"
    else
        if ! git checkout -b ${branch} > /dev/null 2> /dev/null;
        then
            log_failed "Couldn't create branch"
            unset branch # unset to avoid side-effects in log
            return 1
        fi
    fi

    unset branch # unset to avoid side-effects in log
}

delete_branch() {
    branch=${1:-$BRANCH}

    if element_in "${branch}" "${default_branches[@]}"; then
        log_failed "Cannot delete protected branch"
        unset branch # unset to avoid side-effects in log
        return 1
    fi

    if git ls-remote --heads "${remote}" "${branch}" | grep "${branch}" > /dev/null;
    then
        log "Are you sure you want to delete ${YELLOW}${branch}${BLUE} branch on remote ${YELLOW}${remote}${BLUE}?"
        log "Press any key to continue or ctrl-c to abort."
        read foo

        push_to_remote "${remote}" "--delete"
    else
        log_ignored "Branch doesn't exist on remote"
    fi

    if ! git branch -D "${branch}" > /dev/null 2> /dev/null;
    then
        log_ignored "Branch doesn't exist locally"
    fi

    unset branch # unset to avoid side-effects in log
}

release() {
    current_version=$(evaluate_mvn_expr 'project.version')

    if [[ "${current_version}" != *-SNAPSHOT ]]; then
        log_ignored "Cannot release a non-snapshot version"
        return 1
    fi

    versionRE='([1-9].[0-9].[0-9]+)-([0-9]+)-?(rhoar|redhat)?-?(SNAPSHOT)?'
    if [[ "${current_version}" =~ ${versionRE} ]]; then
        sbVersion=${BASH_REMATCH[1]}
        versionInt=${BASH_REMATCH[2]}
        newVersionInt=$(($versionInt +1))
        qualifier=${BASH_REMATCH[3]}
        snapshot=${BASH_REMATCH[4]}

        releaseVersion="${sbVersion}-${versionInt}"
        if [[ -n "${qualifier}" ]]; then
            releaseVersion="${releaseVersion}-${qualifier}"
        fi

        nextVersion="${sbVersion}-${newVersionInt}"
        if [[ -n "${qualifier}" ]]; then
            nextVersion="${nextVersion}-${qualifier}"
        fi
        nextVersion="${nextVersion}-SNAPSHOT"

    fi

    if git ls-remote --tags "${remote}" "${releaseVersion}" | grep "${releaseVersion}" > /dev/null;
    then
      log_ignored "Tag ${releaseVersion} already exists. Please make sure that the booster version is set correctly"
      return 1
    fi

    runtime=${1:-'1.3-5'}
    
    # replace template placeholders if they exist
    templates=($(find . -path "*/.openshiftio/application.yaml"))
    if [ ${#templates[@]} != 0 ]; then
        for file in ${templates[@]}
        do
            sed -i.bak -e "s/RUNTIME_VERSION/${runtime}/g" ${file}
            log "${YELLOW}${file}${BLUE}: Replaced RUNTIME_VERSION token by ${runtime}"

            sed -i.bak -e "s/BOOSTER_VERSION/${releaseVersion}/g" ${file}
            log "${YELLOW}${file}${BLUE}: Replaced BOOSTER_VERSION token by ${releaseVersion}"

            rm ${file}.bak
        done
        if [[ $(git status --porcelain) ]]; then
            commit "Replaced templates placeholders: RUNTIME_VERSION -> ${runtime}, BOOSTER_VERSION -> ${releaseVersion}"
        else
            # if no changes were made it means that templates don't contain tokens and should be fixed
            log_ignored "Couldn't replace tokens in templates"
            return 1
        fi
    fi

    # switch off pushing since we'll do it at the end
    PUSH='off'
    change_version ${releaseVersion}

    log "Creating tag ${YELLOW}${releaseVersion}"
    git tag -a ${releaseVersion} -m "Releasing ${releaseVersion}" > /dev/null

    if [ ${#templates[@]} != 0 ]; then
        # restore template placeholders
        for file in ${templates[@]}
        do
            sed -i.bak -e "s/${runtime}/RUNTIME_VERSION/g" ${file}
            log "${YELLOW}${file}${BLUE}: Restored RUNTIME_VERSION token"

            sed -i.bak -e "s/${releaseVersion}/BOOSTER_VERSION/g" ${file}
            log "${YELLOW}${file}${BLUE}: Restored BOOSTER_VERSION token"

            rm ${file}.bak
        done
        commit "Restored templates placeholders: ${runtime} -> RUNTIME_VERSION, ${releaseVersion} -> BOOSTER_VERSION"
    fi

    change_version ${nextVersion}

    # switch pushing back on and push
    PUSH='on'
    push_to_remote "${remote}" "--tags"

    # todo: update launcher catalog instead
    log "Appending new version ${YELLOW}${releaseVersion}${BLUE} to ${YELLOW}${CATALOG_FILE}"
    echo "${BOOSTER}: ${BRANCH} => ${releaseVersion}" >> "$CATALOG_FILE"
}

revert() {
    if [[ $(git status --porcelain) ]]; then
        log "${RED}DANGER: YOU HAVE UNCOMMITTED CHANGES:"
        git status --porcelain
    fi

    local answer='N'
    if [[ "$CONFIRMATION_NEEDED" == on ]]; then
      log "Are you sure you want to revert ${YELLOW}${BRANCH}${BLUE} branch to the ${YELLOW}${remote}${BLUE} remote state?"
      log "${RED}YOU WILL LOSE ALL UNPUSHED LOCAL COMMITS SO BE CAREFUL!"
      log "Press ${RED}Y to revert${BLUE} or ${YELLOW}any other key to leave the booster as-is."
      read answer
    else
      answer='Y'
    fi

    if [ "${answer}" == Y ]; then
        log "Resetting to remote ${remote} state"
        git reset --hard "${remote}"/"${BRANCH}"
        git clean -f -d
    else
        log "Leaving as-is"
    fi
}

run_tests() {
    if [[ "$RUN_TESTS" == on ]]; then
      local canonical_name="${BOOSTER}"

      log "Running tests of booster ${canonical_name} from directory: ${PWD}"

      oc delete project ${canonical_name} --ignore-not-found=true
      sleep 10
      oc new-project ${canonical_name} > /dev/null
      mvn $(maven_settings) -q -B clean verify -Popenshift,openshift-it ${MAVEN_EXTRA_OPTS:-}
      if [ $? -eq 0 ]; then
          echo
          log "Successfully tested"
          #Delete the project since there is no need to inspect the results when everything is OK
          oc delete project ${canonical_name} > /dev/null
      else
          log_failed "Tests failed: inspecting the '${canonical_name}' namespace might provide some insights"

          #We don't delete the project because it could be needed for a postmortem inspection
      fi
    fi
}

run_smoke_tests() {
    if [[ "$RUN_TESTS" == on ]]; then
      log "Running tests of booster from directory: ${PWD}"
      mvn $(maven_settings) -q -B clean verify ${MAVEN_EXTRA_OPTS:-}
      if [ $? -eq 0 ]; then
          log "Successfully tested"
      else
          log_failed "Tests failed"
      fi
    fi
}

catalog() {
    # todo: update launcher catalog instead
    echo "${BOOSTER}: ${BRANCH} => $(get_latest_tag)" >>"$CATALOG_FILE"
}

trim() {
    # trim leading and trailing whitespaces using https://stackoverflow.com/a/3232433
    local toTrim=$(echo "$@")
    echo -e "${toTrim}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

run_cmd() {
    # build command: since arguments are passed unquoted, we need a separator to mark the command from the commit message
    # we use ---- as separator so we expect arguments to be in the form "cmd ---- msg"
    # first build a string from all arguments
    local cmdAndMsg=$(echo "$@")
    # then we extract parts using https://stackoverflow.com/a/10520718 trimming leading and trailing whitespaces
    local cmd=$(trim ${cmdAndMsg%----*})
    local msg=$(trim ${cmdAndMsg##*----})

    log "Executing ${YELLOW}'${cmd}'"

    if ! eval ${cmd}; then
        log_failed "${cmd} command failed"
        return 1
    fi

    if [ -n "$msg" ]; then
        # we have a commit message so commit and push result of command if that resulted in local changes
        if [[ $(git status --porcelain) ]]; then
            commit "${msg}"
            push_to_remote
        fi
    fi
}

show_help () {
    simple_log "This scripts executes the given command on all local boosters (identified by the 'spring-boot-*-booster' pattern) found in the current directory."
    simple_log "Usage:"
    simple_log "    -b                            A comma-separated list of branches. For example -b branch1,branch2. Defaults to $(IFS=,; echo "${default_branches[*]}"). Note that this option is mandatory to create / delete branches."
    simple_log "    -d                            Toggle dry-run mode: no commits or pushes. This operation is not compatible with the release command"
    simple_log "    -f                            Bypass check for local changes, forcing execution if changes exist."
    simple_log "    -h                            Display this help message."
    simple_log "    -l                            Specify where the local copies of the boosters should be found. Defaults to current working directory."
    simple_log "    -m                            The boosters to operate on (comma separated value). The name of each booster can either be the full booster name, or the simple booster name (for example: circuit-breaker) Not selecting this option means that all boosters will be operated on."
    simple_log "    -n                            Skip confirmation dialogs"
    simple_log "    -p                            Perform booster local setup"
    simple_log "    -r                            The name of the git remote to use for the boosters, for example upstream or origin. The default value is ${default_remote}"
    simple_log "    -s                            Skip the test execution"
    simple_log "    release                       Release the boosters."
    simple_log "    change_version <args>         Change the project or parent version. Run with -h to see help."
    simple_log "    run_tests                     Run the integration tests on an OpenShift cluster. Requires to be logged in to the required cluster before executing"
    simple_log "    create_branch <branch name>   Create a branch."
    simple_log "    delete_branch <branch name>   Delete a branch."
    simple_log "    cmd <command>                 Execute the provided shell command."
    simple_log "    fn <function name>            Execute the specified function. This allows to call internal functions. Make sure you know what you're doing!"
    simple_log "    revert                        Revert the booster state to the last remote version."
    simple_log "    script <path to script>       Run provided script."
    simple_log "    smoke_tests                   Run the unit tests locally."
    simple_log "    catalog                       Re-generate the catalog file."
    echo
}

show_change_version_help() {
    simple_log "change_version command changes the project's (or parent's, if -p flag is set) version"
    simple_log "Usage:"
    simple_log "    -h                            Display this help message."
    simple_log "    -p                            Optional: change parent version instead of project version."
    simple_log "    -v <version name>             Optional: specify which version to use. Version is computed otherwise."
    simple_log "    -m <commit prefix>            Optional: specify a commit message prefix (e.g. JIRA / github ticket number) to prepend to commit messages. Empty otherwise."
}

show_cmd_help() {
    simple_log "cmd command executes the specified command on the project, optionally committing and pushing the changes to the remote repository"
    simple_log "Usage:"
    simple_log "    -h                            Display this help message."
    simple_log "    -p <commit message>           Optional: commit the changes (if any) and pushes them to the remote repository."
}

error() {
    echo -e "${RED}Error: ${1}${NC}"
    local help=${2:-show_help}
    ${help}
    exit ${3:-1}
}


if [ $# -eq 0 ]; then
    show_help
fi

readonly default_branches=("master" "redhat")
branches=("${default_branches[@]}")

readonly default_remote=upstream
remote=${default_remote}

declare -a explicitly_selected_boosters=( )

# See https://sookocheff.com/post/bash/parsing-bash-script-arguments-with-shopts/
while getopts ":hdnfspb:r:m:l:" opt; do
    case ${opt} in
        h)
            show_help
            exit 0
        ;;
        d)
            echo -e "${YELLOW}== DRY-RUN MODE ACTIVATED: no commits or pushes will be issued ==${NC}"
            echo
            PUSH='off'
            COMMIT='off'
        ;;
        f)
            echo -e "${YELLOW}== BYPASSING CHECK FOR LOCAL CHANGES ==${NC}"
            echo
            IGNORE_LOCAL_CHANGES='on'
        ;;
        l)
            # check that target directory exists, if not create it
            if [ ! -d "$OPTARG" ]; then
                mkdir -p $OPTARG
            fi
            # See https://stackoverflow.com/questions/11621639/how-to-expand-relative-paths-in-shell-script/11621788 on how to
            # resolve relative directories to the current working dir.
            BOOSTERS_DIR=$(cd $OPTARG; pwd)
            echo -e "${YELLOW}== Will use directory ${BLUE}${BOOSTERS_DIR}${YELLOW} as the booster parent directory ==${NC}"
            echo
        ;;
        b)
            IFS=',' read -r -a branches <<< "$OPTARG"
            echo -e "${YELLOW}== Will use '${BLUE}$OPTARG${YELLOW}' branch(es) instead of the default ${BLUE}'$(IFS=,; echo "${default_branches[*]}")${YELLOW}' ==${NC}"
            echo
        ;;
        p)
            echo -e "${YELLOW}== Will clone boosters from GitHub - This will result in the loss of any local changes to the boosters ==${NC}"
            echo
            PERFORM_BOOSTER_LOCAL_SETUP='on'
        ;;
        r)
            echo -e "${YELLOW}== Will use '${BLUE}$OPTARG${YELLOW}' as the git remote instead of the default of ${BLUE}'${default_remote}${YELLOW}' ==${NC}"
            echo
            remote=$OPTARG
        ;;
        n)
            echo -e "${YELLOW}== SKIP CONFIRMATION DIALOGS ACTIVATED: no confirmation will be requested from the user for any potentially destructive operations ==${NC}"
            echo
            CONFIRMATION_NEEDED='off'
        ;;
        s)
            echo -e "${YELLOW}== SKIPPING TEST EXECUTION. No tests will be run for boosters ==${NC}"
            echo
            RUN_TESTS='off'
        ;;
        m)
            IFS=',' read -r -a explicitly_selected_boosters <<< "$OPTARG"
            echo -e "${YELLOW}== Will use '${BLUE}$OPTARG${YELLOW}' booster(s) ==${NC}"
            echo
        ;;
        \?)
            error "Invalid option: -$OPTARG" 1>&2
        ;;
    esac
done
shift $((OPTIND - 1))

subcommand=$1
cmd=""
case "$subcommand" in
    release)
        if [[ "$COMMIT" == off ]]; then
            log_failed "The dry-run option is not supported for the release command"
            exit 1
        fi

        CATALOG_FILE=${BOOSTERS_DIR}"/booster-catalog-versions.txt"
        rm -f "$CATALOG_FILE"
        touch "$CATALOG_FILE"

        cmd="release"
    ;;
    catalog)
        CATALOG_FILE=${BOOSTERS_DIR}"/booster-catalog-versions.txt"
        rm -f "$CATALOG_FILE"
        touch "$CATALOG_FILE"
        simple_log "Re-generating catalog file ${YELLOW}${CATALOG_FILE}${NC}"
        cmd="catalog"
    ;;
    create_branch)
        CREATE_BRANCH='on'
        cmd="create_branch"
    ;;
    delete_branch)
        cmd="delete_branch"
    ;;
    change_version)
        # Needed in order to "reset" the options processing for the subcommand
        OPTIND=2
        # Process options of subcommand
        while getopts ":hpv:m:" opt2; do
            case ${opt2} in
                h)
                    show_change_version_help
                    exit 0
                ;;
                p)
                    targetParent=true
                ;;
                v)
                    version=$OPTARG
                ;;
                m)
                    jira=$OPTARG
                ;;
                \?)
                    error "Invalid change_version option: -$OPTARG" "show_change_version_help" 1>&2
                ;;
                :)
                    error "Invalid change_version option: -$OPTARG requires an argument" "show_change_version_help" 1>&2
                ;;
            esac
        done
        shift $((OPTIND - 1))

        cmd="change_version ${version:-compute} ${targetParent:-off} ${jira:-}"
    ;;
    script)
        shift
        if [ -n "$1" ]; then
            cmd="source $1"
        else
            error "Must provide a script to execute"
        fi
    ;;
    revert)
        IGNORE_LOCAL_CHANGES='on'
        cmd="revert"
    ;;
    run_tests)
        cmd="run_tests"
    ;;
    smoke_tests)
        cmd="run_smoke_tests"
    ;;
    cmd)
        # Needed in order to "reset" the options processing for the subcommand
        OPTIND=2
        # Process options of subcommand
        while getopts ":hp:" opt2; do
            case ${opt2} in
                h)
                    show_cmd_help
                    exit 0
                ;;
                p)
                    message=$OPTARG
                ;;
                \?)
                    error "Invalid cmd option: -$OPTARG" "show_cmd_help" 1>&2
                ;;
                :)
                    error "Invalid cmd option: -$OPTARG requires an argument" "show_cmd_help" 1>&2
                ;;
            esac
        done
        shift $((OPTIND - 1))
        if [ -n "$1" ]; then
            cmd="run_cmd $1 ---- ${message}"
        else
            error "Must provide a command to execute"
        fi
    ;;
    fn)
        shift
        if [ -n "$1" ]; then
            cmd="$1" # record command name
            shift # remove command name from args
            cmd="${cmd} $@" # append args
        else
            error "Must provide a function to execute"
        fi
    ;;
    *)
        error "Unknown command: '${subcommand}'" 1>&2
    ;;
esac

# The following populates the array with entries like:
# spring-boot-cache-booster,git@github.com:snowdrop/spring-boot-cache-booster.git
# spring-boot-circuit-breaker-booster,git@github.com:snowdrop/spring-boot-circuit-breaker-booster.git
all_boosters_from_github=($(curl -s https://api.github.com/search/repositories\?q\=org:snowdrop+topic:booster | jq -j '.items[] | .name, ",", .ssh_url, "\n"' | sort))
if [ ${#all_boosters_from_github[@]} == 0 ]; then
    echo -e "${RED}No boosters matching the query were found on GitHub${NC}"
    exit 1
fi
pushd ${BOOSTERS_DIR} > /dev/null

for booster_line in ${all_boosters_from_github[@]}
do
    IFS=',' read -r -a booster_parts <<< "${booster_line}"
    BOOSTER=${booster_parts[0]}
    BOOSTER_GIT_URL=${booster_parts[1]}
    if [[ ${BOOSTER} =~ spring-boot-(.*)-booster ]]; then #this will always be true, but is used in order to capture the simple name
        booster_simple_name=${BASH_REMATCH[1]}

        # The following matches if no explicit boosters have been set
        # or if the simple booster name (meaning the part without 'spring-boot-' and '-booster')
        # matches one of the explicitly selected boosters
        # For example if the explicitly selected boosters are circuit-breaker and http then
        # then spring-boot-circuit-breaker-booster would match,
        # while spring-boot-crud-booster would not
        if [ ${#explicitly_selected_boosters[@]} -eq 0 ] || [[ "${explicitly_selected_boosters[@]}" =~ "${booster_simple_name}" ]]; then
          echo -e "${BLUE}> ${YELLOW}${BOOSTER}${BLUE}${NC}"

          if [[ "$PERFORM_BOOSTER_LOCAL_SETUP" == on ]]; then
            setup_booster_locally ${BOOSTER} ${BOOSTER_GIT_URL}
          fi

          pushd ${BOOSTER} > /dev/null

          if [ ! -d .git ]; then
              msg="Not under git control"
              echo -e "${MAGENTA}${msg}${MAGENTA}. Ignoring.${NC}"
              ignoredItem="${BOOSTER}:\"${msg}\""
              ignored+=( "${ignoredItem}" )
          else
              for BRANCH in "${branches[@]}"
              do
                  bypassUpdate='off'
                  # check if branch exists, otherwise skip booster
                  if [ "$CREATE_BRANCH" != on ] && ! git show-ref --verify --quiet refs/heads/${BRANCH}; then
                      # check if a remote but not locally present branch exist and check it out if it does
                      if git ls-remote --heads "${remote}" "${BRANCH}" | grep "${BRANCH}" > /dev/null; then
                          git checkout -b "${BRANCH}" "${remote}"/"${BRANCH}"
                          bypassUpdate='on'
                      else
                          log_ignored "Branch does not exist"
                          continue
                      fi
                  fi

                  if [ "$bypassUpdate" == off ]; then
                      if [ "$IGNORE_LOCAL_CHANGES" != on ]; then
                          # if booster has uncommitted changes, skip it
                          if [[ $(git status --porcelain) ]]; then
                              log_ignored "You have uncommitted changes, please stash these changes"
                              continue
                          fi

                          git fetch -q "${remote}" > /dev/null

                          git checkout -q "${BRANCH}" > /dev/null && git rebase "${remote}"/"${BRANCH}" > /dev/null
                      else
                          git checkout -q "${BRANCH}" > /dev/null
                      fi
                  fi


                  # if we need to replace a multi-line match in the pom file of each booster, for example:
                  # perl -pi -e 'undef $/; s/<properties>\s*<\/properties>/replacement/' pom.xml

                  # if we need to execute sed on the result of find:
                  # find . -name "application.yaml" -exec sed -i '' -e "s/provider: fabric8/provider: snowdrop/g" {} +

                  log "Executing '${YELLOW}${cmd}${BLUE}'"
                  # let the command fail without impacting the main loop, let the command decide on what to log / fail / ignore
                  if ! ${cmd}; then
                      log "Done"
                      echo
                      continue
                  fi

                  log "Done"
                  processedItem="${BRANCH}:${BOOSTER}"
                  processed+=( "${processedItem}" )
                  echo
              done
          fi

          echo -e "----------------------------------------------------------------------------------------\n"
          popd > /dev/null

        fi
    fi
done

popd > /dev/null

if [ ${#processed[@]} != 0 ]; then
    echo -e "${BLUE}${#processed[@]} booster/branch combinations were processed:${YELLOW}"
    printf '\t%s\n' "${processed[@]}"
fi

if [ ${#failed[@]} != 0 ]; then
    echo -e "${BLUE}${#failed[@]} booster/branch combinations failed:${RED}"
    printf '\t%s\n' "${failed[@]}"
fi

if [ ${#ignored[@]} != 0 ]; then
    echo -e "${BLUE}${#ignored[@]} booster/branch combinations  were skipped:${MAGENTA}"
    printf '\t%s\n' "${ignored[@]}"
fi
