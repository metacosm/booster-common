#!/usr/bin/env bash

####
# Safely sets the build section of a POM. Safely means that it only applies section that we know don't exist in the boosters
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


# add the build section if it doesn't exist
if ! xq -e '.project.build' pom.xml > /dev/null; then
  if xq -e '.project.profiles' pom.xml > /dev/null; then
    # add an build section right before the dependencies section
    perl -pi.bak -e '!$x && s/<profiles>/<build>\n  <\/build>\n\n  <profiles>/g && ($x=1)' pom.xml
  else
    # add at the end of the project
    sed -i.bak 's/<\/project>/  <build>\n  <\/build>\n<\/project>/g' pom.xml
  fi
fi

# we are able to accurately determine the position of the top level build tag
# by controlling the indentation of xq and matching only those lines that contain the build tag and start with the specified indentation
topLevelBuildTagLineNumber=$(xq --indent 1 '.project' pom.xml | grep -n '^ "build' | cut -f1 -d:)

# default very large number that will be used if profiles don't exist
# we use a very large value as the default since we will be comparing topLevelProfilesTagLineNumber to topLevelBuildTagLineNumber
# and when the latter is smaller we know that we can safely replace
topLevelProfilesTagLineNumber=999999
if xq -e '.project.profiles' pom.xml > /dev/null; then
  topLevelProfilesTagLineNumber=$(xq --indent 1 '.project' pom.xml | grep -n '^ "profiles' | cut -f1 -d:)
fi

# we can only safely replace if the build section if found before the profiles section (or if the latter doesn't exist)
if [ "$topLevelBuildTagLineNumber" -lt "$topLevelProfilesTagLineNumber" ]; then

  needsManualUpdate=false

  if ! xq -e '.project.build.testResources' pom.xml > /dev/null; then
cat > testResources.xml << EOF
      <testResource>
        <directory>src/test/resources</directory>
        <filtering>true</filtering>
      </testResource>
EOF
    # add testResources section as first section of build
    perl -pi.bak -e "!\$x && s/<build>/<build>\n    <testResources>REPLACEME\n    <\/testResources>/g && (\$x=1)" pom.xml
    ## populate testResources section
    sed -i '/REPLACEME/{
        s/REPLACEME//g
        r testResources.xml
    }' pom.xml
  else
     needsManualUpdate=true
  fi



  if ! xq -e '.project.build.resources' pom.xml > /dev/null; then
cat > resources.xml << EOF
      <resource>
        <directory>src/main/resources</directory>
        <filtering>true</filtering>
      </resource>
EOF
    # add resources section as first section of build
    perl -pi.bak -e "!\$x && s/<build>/<build>\n    <resources>REPLACEME\n    <\/resources>/g && (\$x=1)" pom.xml
    ## populate testResources section
    sed -i '/REPLACEME/{
        s/REPLACEME//g
        r resources.xml
    }' pom.xml
  else
     needsManualUpdate=true
  fi


  if ! xq -e '.project.build.pluginManagement' pom.xml > /dev/null; then
cat > pluginManagement.xml << EOF
      <plugins>
        <plugin>
          <groupId>org.springframework.boot</groupId>
          <artifactId>spring-boot-maven-plugin</artifactId>
          <version>\${spring-boot.version}</version>
          <configuration>
            <classifier>exec</classifier>
          </configuration>
          <executions>
            <execution>
              <goals>
                <goal>repackage</goal>
              </goals>
            </execution>
          </executions>
        </plugin>
        <plugin>
          <groupId>org.apache.maven.plugins</groupId>
          <artifactId>maven-failsafe-plugin</artifactId>
          <executions>
            <execution>
              <goals>
                <goal>integration-test</goal>
                <goal>verify</goal>
              </goals>
            </execution>
          </executions>
        </plugin>
      </plugins>
EOF
    # add pluginManagement section as last section of build
    perl -pi.bak -e "!\$x && s/<\/build>/  <pluginManagement>REPLACEME\n    <\/pluginManagement>\n  <\/build>/g && (\$x=1)" pom.xml
    ## populate pluginManagement section
    sed -i '/REPLACEME/{
        s/REPLACEME//g
        r pluginManagement.xml
    }' pom.xml
  else
     needsManualUpdate=true
  fi



  if ! xq -e '.project.build.plugins' pom.xml > /dev/null; then
cat > plugins.xml << EOF
      <plugin>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-maven-plugin</artifactId>
      </plugin>
EOF
    # add plugins section as last section of build
    perl -pi.bak -e "!\$x && s/<\/build>/  <plugins>REPLACEME\n    <\/plugins>\n  <\/build>/g && (\$x=1)" pom.xml
    ## populate plugins section
    sed -i '/REPLACEME/{
        s/REPLACEME//g
        r plugins.xml
    }' pom.xml
  else
     needsManualUpdate=true
  fi



  if [ "$needsManualUpdate" = true ] ; then
    echo "Pom ${pom_directory}/pom.xml might need manual updates"
  fi

  rm pom.xml.bak testResources.xml resources.xml pluginManagement.xml plugins.xml 2> /dev/null

else
  echo "Pom ${pom_directory}/pom.xml needs manual updates since we can't safely replace"
fi


if [ -n "${POM_DIRECTORY}" ]; then
  popd > /dev/null
fi