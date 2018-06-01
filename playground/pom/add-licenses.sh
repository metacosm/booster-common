#!/usr/bin/env bash

####
# Sets the license section of a POM if needed
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

if ! grep --quiet '<licenses>' pom.xml; then
cat > licenses.xml << EOF
    <license>
      <name>Apache License, Version 2.0</name>
      <url>https://www.apache.org/licenses/LICENSE-2.0.txt</url>
      <distribution>repo</distribution>
      <comments>A business-friendly OSS license</comments>
    </license>
EOF

  # add licenses section after properties
  perl -pi.bak -e "!\$x && s/<\/properties>/<\/properties>\n\n  <licenses>REPLACEME\n  <\/licenses>/g && (\$x=1)" pom.xml

  ## populate dependencyManagement section
  sed -i '/REPLACEME/{
      s/REPLACEME//g
      r licenses.xml
  }' pom.xml

  rm pom.xml.bak licenses.xml
fi




if [ -n "${POM_DIRECTORY}" ]; then
  popd > /dev/null
fi