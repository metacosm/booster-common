#!/usr/bin/env bash

# Meant to be used to run all tests locally
# ./run_tests.sh branch-name (default is master)
# Assumes that the user has logged in to the required cluster before executing

branch=${1:-master}

cd $(mktemp -d)

declare -a boosters=( "http" "health-check" "crud" "configmap" "circuit-breaker" )
declare -a failed=( )

for booster in "${boosters[@]}"
do
    echo "Cloning booster ${booster}"

    booster_git_name=spring-boot-${booster}-booster
    git clone -q -b ${branch} https://github.com/snowdrop/${booster_git_name}

    cd ${booster_git_name}

    echo "Running tests of booster ${booster}"

    mvn -q -B clean verify -Popenshift,openshift-it ${MAVEN_EXTRA_OPTS:-}
    if [ $? -eq 0 ]; then
        echo "Successfully tested ${booster}"
    else
        echo "Tests of ${booster} failed"
        failed+=( ${booster} )
    fi

    cd ../
done

echo "Done testing"
if [ ${#failed[@]} -eq 0 ]; then
    echo "All tests passes"
else
    echo "The following tests failed: "$(IFS=,; echo "${failed[*]}")
fi