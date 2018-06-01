#!/usr/bin/env bash

####
# Changes groupId of parent and adds groupId to the pom
#
# args: The directory where the pom is to be located as POM_DIRECTORY. If not supplied it's assumed to be the current directory is assumed
#
# Dependencies: yq, perl, sed
#
# Prerequisites: a properties section needs to exist in the pom
####

pom_directory=${POM_DIRECTORY:-$(pwd)}


pomFileCount=`ls -1 ${pom_directory}/pom.xml 2>/dev/null | wc -l`
if [ "$pomFileCount" == 0 ]
then
  echo "No pom.xml found in $pom_directory"
  return 1
fi

if [ -n "${POM_DIRECTORY}" ]; then
  pushd ${pom_directory} > /dev/null
fi


# fix parent groupId
perl -pi.bak -e "!\$x && s/<groupId>io.openshift.booster<\/groupId>/<groupId>io.openshift<\/groupId>/g && (\$x=1)" pom.xml

# add groupId if it doesn't exist
if ! xq -e '.project.groupId' pom.xml > /dev/null; then
    # add an build section right before the name section
    perl -pi.bak -e '!$x && s/<name>/<groupId>io.openshift.booster<\/groupId>\n  <name>/g && ($x=1)' pom.xml
fi

rm pom.xml.bak

if [ -n "${POM_DIRECTORY}" ]; then
  popd > /dev/null
fi