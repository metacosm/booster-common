remove_classifier() {
    # uses http://xmlstar.sourceforge.net/ for XML manipulation
    local -r branchName="remove-classifier"
    git checkout -b "${branchName}" > /dev/null 2> /dev/null

    # update the templates so that they use the proper jar name without the classifier
    templates=( $(find_openshift_templates) )
    if [ ${#templates[@]} != 0 ]; then
        for file in ${templates[@]}
        do
            replace ${file} "value: '*-exec.jar'" "value: '*.jar'"
        done
    fi

    local -r failsafePluginXPath="/m:project/m:profiles/m:profile[m:id = 'openshift-it']/m:build/m:plugins/m:plugin[m:artifactId = 'maven-failsafe-plugin']"
    local -r mvnNS="http://maven.apache.org/POM/4.0.0"

    # remove the classifier, some booster have the configuration in pluginManagement, some in plugin directly…
    xml ed -N m=${mvnNS} -d "/m:project/m:build/m:plugins/m:plugin[m:artifactId = 'spring-boot-maven-plugin']/m:configuration/m:classifier" pom.xml > pom.mod.xml
    mv pom.mod.xml pom.xml

    xml ed -N m=${mvnNS} -d "/m:project/m:build/m:pluginManagement/m:plugins/m:plugin[m:artifactId = 'spring-boot-maven-plugin']/m:configuration/m:classifier" pom.xml > pom.mod.xml
    mv pom.mod.xml pom.xml

    # only add classesDirectory configuration to single-module boosters
    if ! xq -e '.project.packaging' pom.xml > /dev/null; then
        # if there was no configuration for the failsafe plugin, add it
        if ! xml sel -N m=${mvnNS} -t -v "${failsafePluginXPath}/m:configuration" pom.xml; then
            xml ed -N m=${mvnNS} -s "${failsafePluginXPath}" -t elem -n 'configuration' -v '' pom.xml > pom.mod.xml
            mv pom.mod.xml pom.xml
        fi

        xml ed -N m=${mvnNS} -u "${failsafePluginXPath}/m:configuration/m:classesDirectory" -v '${project.build.directory}/${project.build.finalName}.${project.packaging}.original' pom.xml > pom.mod.xml
        mv pom.mod.xml pom.xml
    fi

    commit "Remove classifier in Spring Boot Maven plugin configuration and adapt failsafe configuration accordingly."
    local -r pr=$(hub pull-request -f -p -h snowdrop:"${branchName}" -m "Removal of classifier in SB maven plugin")
    simple_log "Created PR: ${YELLOW}${pr}"
}
