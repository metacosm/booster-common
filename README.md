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

## `src/update-pom.groovy`

A Groovy script that checks the `properties` and updates those values with the corresponding dependency version in the upstream Spring Boot BOM
An example invocation that includes all the available features would be:

`groovy update-pom.groovy /path/to/pom.xml 1.5.13 "hibernate.version=,tomcat.version=8.5.29"`

To see more information about the script invoke:

`groovy update-pom.groovy` 


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