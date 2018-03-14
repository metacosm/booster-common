# Scripts to process boosters

## `for-all-boosters`

A script that operates on all boosters identified as sub-directories (named with the `spring-boot-*-booster` pattern) of the directory in which the script runs. 

Run `for-all-boosters.sh -h` for an overview of what the script can do and how to use it.

## `run_tests.sh`

Runs the integration tests on the identified boosters. See initial comment on script for more details. Note that this script will probably be merged into `for-all-boosters` at some point.

## `sync-descriptors.sh`

A script that synchronizes YAML descriptors between booster branches. Here for historical reasons, shouldn't be needed anymore.