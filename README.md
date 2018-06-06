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
* yq (see instructions to download [here](https://github.com/kislyuk/yq))

### Examples

* Setup all boosters locally without actually performing any operations on them

  `for-all-boosters.sh -p cmd "pwd"`
    
  The key flag here is `-p`, which forces the script to create a boosters locally. `cmd "pwd"` Makes the script execute the `pwd` command for each booster - effectively working as a noop
  
* Execute a simple version increment a on selected number of boosters for the `master` branch

  `./for-all-boosters.sh -b redhat -m cache,http change_version`    

  The `-b` flag ensures that only the `master` branch will be used while the `-m` flag ensures that only the `cache` and `http` boosters are used
  The `change_version` command will simply increment the version of each booster, for example from `1.5.10-1-redhat-SNAPSHOT` to ``1.5.10-2-redhat-SNAPSHOT``
  
* Execute a specific parent version increment on all boosters except the specified ones

  `./for-all-boosters.sh -x cache,http change_version -p 24`    

  The `-x` flag ensures that all boosters are used except `cache` and `http` boosters.
  The `change_version` command will set the parent version (because of the `-p` flag) of the boosters to `24` 
  
* Execute an arbitrary command on all boosters without commit and pushing changes to remote

  `./for-all-boosters.sh -d cmd "cp $(pwd)/.editorconfig . && git add .editorconfig"`
  
  The `-d` flag ensures that no changes are committed locally or pushed to the remote repos.
  The arbitrary command here adds the `.editorconfig` file (which is in the same directory as `for-all-boosters.sh`) to each booster and makes git track it   

* Execute a custom script for each booster on some branch ignoring whatever changes exist locally

  `./for-all-boosters.sh -f -m foo cmd -p "Made some change" "/home/scripts/adhoc.py"`
  
  Due to the presense of the `-f` flag, before running the command the script will show a warning if local changes exist (to remove the warning add the `-n` flag)
  Any changes that the `adhoc.py` script makes to the booster files will automatically be committed using the message specified in `-p` and pushed to the `foo` branch (which needs to exist)   

* Execute one of the script's functions of a specific booster and branch

  `./for-all-boosters.sh -m redhat -b crud fn fmp_deploy`
  
  This command will execute the `fmp_deploy` function found in the script on the `redhat` branch of the `crud` booster
  
  



## `sync-descriptors.sh`

A script that synchronizes YAML descriptors between booster branches. Here for historical reasons, shouldn't be needed anymore.

The script relies heavily on the `mvn` executable to determine the current version of the boosters (as well as the booster parent version)
therefore the boosters need to be valid maven projects in order to the various operations to work.
Furthermore, for the `redhat` branch, the local Red Hat maven repositories need to be setup correctly in order for maven to be able to
resolve all the dependencies. If in a such cases a custom `settings.xml` file is used, then the environment variable  
`MAVEN_SETTINGS` can be set to point to that file and all operations of this script will use that custom settings file.

## `src/update-pom.groovy`

A Groovy script that checks the `properties` and updates those values with the corresponding dependency version in the upstream Spring Boot BOM.

An example invocation that includes all the available features would be:

`groovy update-pom.groovy /path/to/pom.xml 1.5.13 "hibernate.version=,tomcat.version=8.5.29"`

To see more information about the script invoke:

`groovy update-pom.groovy`

## Important Notes on development

When developing new features for any of these scripts, it is very important to test both with single module and multi module projects.
Multi-module Maven projects are often a source of bugs in the scripts  


## Steps to almost complete automated release

An ideal scenario would be to create a script that would do: `spring-boot-release.sh 1.5.13` and perform all the required steps
to release a new version of the Spring Boot runtime based on the specified target Spring Boot release.

- Get the target Spring Boot version from the user. Maybe have some leeway: `1.5.13` would be assumed to be `1.5.13.RELEASE`?
- Based on that version, retrieve the associated `spring-boot-dependencies` POM (e.g. https://github.com/spring-projects/spring-boot/blob/v1.5.13.RELEASE/spring-boot-dependencies/pom.xml, the URL should be buildable from the given version) and process it to extract the
version properties we use in our BOM with the new values
- Use this new BOM version to create a new booster parent version and release a new parent SNAPSHOT
- Update the boosters to use the new parent SNAPSHOT, change their version accordingly and run the tests. This can already be 
done automatically using `for-all-boosters`.
- Assuming all goes well, release the community boosters. Maybe wait for QE feedback, first? This can already be done
automatically.
- ...
 

### Ideas

- When the script is run, it should record where in the process it is in a file so that it can be executed in several steps and
restart the process at the next step instead of the beginning.
- Remove parent and instead create a maven POM template from which the boosters' POM could be derived?
