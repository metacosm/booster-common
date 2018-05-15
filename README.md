# Scripts to process boosters

## `for-all-boosters`

A script that operates on all boosters under the `snowdrop` organization that have the `booster` topic attached to them 

Run `for-all-boosters.sh -h` for an overview of what the script can do and how to use it.

### Dependencies

* git
* perl
* mvn
* oc
* jq
* yq

## `sync-descriptors.sh`

A script that synchronizes YAML descriptors between booster branches. Here for historical reasons, shouldn't be needed anymore.

The script relies heavily on the `mvn` executable to determine the current version of the boosters (as well as the booster parent version)
therefore the boosters need to be valid maven projects in order to the various operations to work.
Furthermore, for the `redhat` branch, the local Red Hat maven repositories need to be setup correctly in order for maven to be able to
resolve all the dependencies. If in a such cases a custom `settings.xml` file is used, then the environment variable  
`MAVEN_SETTINGS` can be set to point to that file and all operations of this script will use that custom settings file. 