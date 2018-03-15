#!/usr/bin/env bash

# Meant to be used to run all tests locally
# ./run_tests.sh branch-name (default is master)
# Assumes that the user has logged in to the required cluster before executing


declare -a boosters_to_test=( "http" "health-check" "crud" "configmap" "circuit-breaker" )
declare -a failed_tests=( )

execute_test() {
    local canonical_name=$1
    local git_name=$2

    cd ${git_name}

    echo "Running tests of booster ${canonical_name} from directory: ${PWD}"

    oc delete project ${canonical_name} --ignore-not-found=true
    sleep 10
    oc new-project ${canonical_name} > /dev/null
    mvn -q -B clean verify -Popenshift,openshift-it ${MAVEN_EXTRA_OPTS:-}
    if [ $? -eq 0 ]; then
        echo "Successfully tested ${canonical_name}"
        #Delete the project since there is no need to inspect the results when everything is OK
        oc delete project ${canonical_name}
    else
        echo "Tests of ${canonical_name} failed"
        failed_tests+=( ${canonical_name} )

        #We don't delete the project because it could be needed for a postmortem inspection
    fi

    cd ../
}

execute_all_tests() {
    pushd $(mktemp -d) > /dev/null

    local branch=${1:-master}

    for booster in "${boosters_to_test[@]}"
    do
        echo "Cloning booster ${booster}"

        booster_git_name=spring-boot-${booster}-booster
        git clone -q -b ${branch} https://github.com/snowdrop/${booster_git_name}

        execute_test ${booster} ${booster_git_name}

    done

    echo "Done testing"
    if [ ${#failed_tests[@]} -eq 0 ]; then
        echo "All tests passes"
    else
        echo "The following tests failed: "$(IFS=,; echo "${failed_tests[*]}")
        echo "Each booster was executed in a dedicated namespace whose name matches the name of the booster"
        echo "Please inspect the namespace for details of why the tests failed"
    fi

    popd > /dev/null
}

# Execute the tests if this script was called directly (i.e. not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    execute_all_tests "$@"
fi