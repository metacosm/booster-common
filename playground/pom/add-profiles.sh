#!/usr/bin/env bash

####
# Safely sets the profiles section of a POM.
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

licensePlugin='{"id":"licenses","build":{"plugins":{"plugin":[{"groupId":"org.codehaus.mojo","artifactId":"license-maven-plugin"},{"groupId":"org.codehaus.mojo","artifactId":"xml-maven-plugin"}]}}}'
openshiftPlugin='{"id":"openshift","build":{"plugins":{"plugin":{"groupId":"io.fabric8","artifactId":"fabric8-maven-plugin","executions":{"execution":{"id":"fmp","goals":{"goal":["resource","build"]}}}}}}}'
openshiftItPlugin='{"id":"openshift-it","build":{"plugins":{"plugin":{"groupId":"org.apache.maven.plugins","artifactId":"maven-failsafe-plugin"}}}}'

## declare an array variable holding the names of the vars above
declare -a pluginsToPotentiallyAdd=("licensePlugin" "openshiftPlugin" "openshiftItPlugin")

# add the build section if it doesn't exist
if ! xq -e '.project.profiles' pom.xml > /dev/null; then
  sed -i.bak 's/<\/project>/  <profiles>\n  <\/profiles>\n<\/project>/g' pom.xml
fi

numberOfProfileTags=$(grep '<profiles>' pom.xml | wc -l)
if [ ${numberOfProfileTags} = 1 ]; then

  # In order to be able always use the same xq query on profiles (no matter what the actual cardinality of the profiles is)
  # We add two dummy profiles that will be removed at the end of the process
cat > dummy.xml << EOF
    <profile>
      <id>dummy</id>
    </profile>
EOF

  for i in $(seq 1 2)
  do
      # add a placeholder for the dummy plugin
      perl -pi.bak -e "!\$x && s/<\/profiles>/REPLACEME\n  <\/profiles>/g && (\$x=1)" pom.xml

      ## add the dummy plugin
      sed -i '/REPLACEME/{
          s/REPLACEME//g
          r dummy.xml
      }' pom.xml
  done

  allPluginsInPomJson=$(xq -c '.project.profiles' pom.xml)
  finalPluginsJsonToBeInPom=${allPluginsInPomJson}
  allPluginIdsInPom=$(xq '.project.profiles.profile[] | .id' pom.xml)


  ## now loop through the above array
  for plugin in "${pluginsToPotentiallyAdd[@]}"
  do
      pluginJson="${!plugin}"
      pluginId=$(echo ${pluginJson} | jq -r '.id')
      # add the plugin if it doesn't exist
      if ! echo ${allPluginIdsInPom} | grep --quiet -w "\"${pluginId}\""; then
        finalPluginsJsonToBeInPom=$(echo ${finalPluginsJsonToBeInPom} | jq '.profile += ['"${pluginJson}"']')
      fi
  done

  #drop dummy plugins
  finalPluginsJsonToBeInPom='{"profiles": {"profile":'$(echo ${finalPluginsJsonToBeInPom} | jq '.profile[] | select(.id != "dummy")' | jq --slurp '.')'}}'

  # create the final XML content of the profile section
  echo '<project><dummy></dummy></project>' | xq '.project *'"${finalPluginsJsonToBeInPom}"' | .profiles' -x | sed -e 's/^/  /' | sed 's/<\/profile><profile>/<\/profile>\n    <profile>/g' > profiles-content.xml

  #clear out the content of the profiles section to make way for the new content
  perl -i -pe 'BEGIN{undef $/;} s/<profiles>.*<\/profiles>/<profiles>\nREPLACEME\n  <\/profiles>/smg' pom.xml

  ## set final profiles content
  sed -i '/REPLACEME/{
      s/REPLACEME//g
      r profiles-content.xml
  }' pom.xml

  rm pom.xml.bak dummy.xml profiles-content.xml
else
  echo "Pom ${pom_directory}/pom.xml needs manual updates since we can't safely replace"
fi

if [ -n "${POM_DIRECTORY}" ]; then
  popd > /dev/null
fi