#!/usr/bin/env bash

####
# Sets the dependencyManagement section of a POM to include the dependencies of `newDeps` - the scripts works correctly whether or not the pom
# contains a dependencyManagement section
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


#these are the dependencies that need to be added to the dependencyManagement section
newDeps='[ { "groupId": "me.snowdrop", "artifactId": "spring-boot-bom", "version": "${spring-boot-bom.version}", "type": "pom", "scope": "import" }, { "groupId": "org.jboss.arquillian", "artifactId": "arquillian-bom", "version": "${arquillian.version}", "type": "pom", "scope": "import" }, { "groupId": "junit", "artifactId": "junit", "version": "${junit.version}", "scope": "test" } ]'

#read the existing dependency management section in pom
existingDM=$(xq -c '.project.dependencyManagement.dependencies.dependency' pom.xml)
existingDMFirstChar=${existingDM:0:1}

finalDeps=""

if [[ "$existingDMFirstChar" == 'n' ]] # no dm section exists
then
    finalDeps=${newDeps}
elif [[ "$existingDMFirstChar" == '{' ]] # dm section exists and has a single dep
then
    finalDeps=$(echo ${newDeps} | jq '. += ['"${existingDM}"']')
else # dm section exists and has multiple deps
    finalDeps=$(echo ${newDeps} | jq '. += '"${existingDM}"'')
fi

dmJson="{ \"dependencyManagement\": { \"dependencies\": { \"dependency\": ${finalDeps} } } }"

# get the xml content of the new dependencyManagement section
xq '.project * '"${dmJson}"' | .dependencyManagement' pom.xml -x | sed -e 's/^/    /' > dm-content.xml

#delete any existing dependency management section
perl -i -pe 'BEGIN{undef $/;} s/<dependencyManagement>.*<\/dependencyManagement>//smg' pom.xml

# add dependency management section after properties
perl -pi.bak -e '!$x && s/<\/properties>/<\/properties>\n\n  <dependencyManagement>REPLACEME\n  <\/dependencyManagement>/g && ($x=1)' pom.xml

## populate dependencyManagement section
sed -i.bak '/REPLACEME/{
    s/REPLACEME//g
    r dm-content.xml
}' pom.xml


#remove trash
rm pom.xml.bak dm-content.xml

if [ -n "${POM_DIRECTORY}" ]; then
  popd > /dev/null
fi