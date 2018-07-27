@Grapes([
        @Grab(group = 'org.apache.maven', module = 'maven-resolver-provider', version = '3.5.3'),
        @Grab(group = 'org.apache.maven.resolver', module = 'maven-resolver-connector-basic', version = '1.1.1'),
        @Grab(group = 'org.apache.maven.resolver', module = 'maven-resolver-transport-http', version = '1.1.1'),
        @Grab(group = 'ch.qos.logback', module = 'logback-classic', version = '1.2.3'),
        ])

import ch.qos.logback.classic.Level
import groovy.transform.EqualsAndHashCode
import org.slf4j.Logger
import org.slf4j.LoggerFactory
import pomutils.MavenGavManagedDependenciesResolver
import pomutils.SetupUtil

final log = setupLogging()

if (args.length < 2 || args.length > 3) {
    log.error(
            """
The script expects two arguments mandarory dependencies: 'pomFile', 'sbVersion' and one optional one: 'versionOverrideStr' 

'pomFile' is path to the pom.xml file that contains the Snowdrop Spring Boot Boom
'sbVersion' is the upstream Spring Boot version that we want to sync our dependencies to 
If the version also contains a qualifier (for example '1.5.13.RELEASE' or '2.0.0.M1'), then it's used as is
If no qualifier is present (for example '1.5.13'), then the 'RELEASE' qualifier is added
'versionOverrideStr' is a string that changes the default version-update behavior of the script.
This is best explained by some examples.

1) If the Hibernate version is not supposed to be changed by the script, than the following invocation would achieve such behavior:

groovy ${getScriptName()} /path/to/pom.xml 1.5.13 "hibernate.version="

2) Hibernate version is not suppose to change, and we want to use 8.5.20 for Tomcat

groovy ${getScriptName()} /path/to/pom.xml 1.5.13 "hibernate.version=,tomcat.version=8.5.20"   
""")
    System.exit(1)
}



final pomFile = new File(args[0])
final springBootVersion = args[1]
final effectiveSBVersion = effectiveSpringBootVersion(springBootVersion)
final simpleSBVersion = simpleSpringBootVersion(springBootVersion)
final parsedVersionOverride = parseVersionOverrideStr(args.length == 3 ? args[2] : null)
final pomXml = new XmlSlurper().parse(pomFile)

final List<PropertyNameAndGA> gaWithPropertyList =
        pomXml.dependencyManagement.dependencies.childNodes().collect {
            final versionNode = it.children.find { it.name == 'version' }
            final groupIdNode = it.children.find { it.name == 'groupId' }
            final artifactIdNode = it.children.find { it.name == 'artifactId' }
            new PropertyNameAndGA(
                    versionNode.text().replace('${', '').replace('}', ''),
                    new GA(groupIdNode.text(), artifactIdNode.text())
            )
        }

final Map<String, GA> propertyNameToFirstGAMap =
        gaWithPropertyList
                .groupBy { it.propertyName }
                .collectEntries { property, propertyNameAndGAList ->
            [(property): propertyNameAndGAList.first().ga]
        }

final springBootManagedDepsResolver = new MavenGavManagedDependenciesResolver(SetupUtil.setup())
final Map<GA, String> springBootManagedDependenciesGaToVersionMap =
        springBootManagedDepsResolver
                .resolve(
                "org.springframework.boot",
                "spring-boot-dependencies",
                effectiveSBVersion
        )
                .collect { it.artifact }
                .collectEntries {
            [(new GA(it.groupId, it.artifactId)): it.version]
        }

final Map<String, String> propertyNameToSpringBootVersionMap =
        propertyNameToFirstGAMap
                .findAll { propertyName, ga ->
            springBootManagedDependenciesGaToVersionMap.containsKey(ga)
        }
        .collectEntries { propertyName, ga ->
            [(propertyName): springBootManagedDependenciesGaToVersionMap.get(ga)]
        }
propertyNameToSpringBootVersionMap.put("spring-boot.version", effectiveSBVersion)
propertyNameToSpringBootVersionMap.put("version", simpleSpringBootVersion(springBootVersion) + "-SNAPSHOT")

updatePomWithLatestVersions(
        pomFile,
        propertyNameToSpringBootVersionMap
                .findAll {
            !parsedVersionOverride.first.contains(it.key)
        }  //remove the properties that are not supposed to change
                .plus(parsedVersionOverride.second) //add the hardcoded properties giving them precedence of what the maven resolution reported

)

private Logger setupLogging() {
    LoggerFactory.getLogger("org.apache.http").level = Level.WARN
    LoggerFactory.getLogger("org.eclipse.aether").level = Level.WARN
    final logger = LoggerFactory.getLogger(this.class.getName())
    logger.level = Level.INFO
    return logger
}

/**
 * @return A tuple that contains two entries:
 * A set of property names that should not change
 * A map that contains the specific overridden versions that should be used for specific properties
 */
private Tuple2<Set<String>, Map<String, String>> parseVersionOverrideStr(String input) {
    final pinnedPropertyNames = new HashSet()
    final propertyNameToHardCodedVersion = [:]
    if (!input) {
        return new Tuple2<Set<String>, Map<String, String>>(
                pinnedPropertyNames,
                propertyNameToHardCodedVersion
        )
    }

    final entries = input.split("\\s*,\\s*")
    if (!entries) {
        throw new IllegalArgumentException("The format of versionOverrideStr was incorrect")
    }

    entries.each {
        final entryParts = it.split("\\s*=\\s*")
        if (entryParts.length == 0 || entryParts.length > 2) {
            throw new IllegalArgumentException("versionOverrideStr part: '${it}' is malformed")
        }

        if (entryParts.length == 2) {
            propertyNameToHardCodedVersion[entryParts[0]] = entryParts[1]
        } else {
            pinnedPropertyNames.add(entryParts[0])
        }
    }

    return new Tuple2<Set<String>, Map<String, String>>(
            pinnedPropertyNames,
            propertyNameToHardCodedVersion
    )
}

private String effectiveSpringBootVersion(String springBootVersion) {
    if (springBootVersion ==~ /[0-9]+.[0-9]+.[0-9]+/) {
        return "${springBootVersion}.RELEASE"
    } else if (springBootVersion ==~ /[0-9]+.[0-9]+.[0-9]+.[A-Z0-9]+/) {
        return springBootVersion
    }

    throw new IllegalArgumentException("Version: '${springBootVersion}' is not a valid release version")
}

private String simpleSpringBootVersion(String springBootVersion) {
    def officialVersion = springBootVersion =~ /([0-9]+.[0-9]+.[0-9]+).[A-Z0-9]+/
    if (springBootVersion ==~ /[0-9]+.[0-9]+.[0-9]+/) {
        return springBootVersion
    } else if (officialVersion.matches()) {
        return officialVersion[0][1]
    }

    throw new IllegalArgumentException("Version: '${springBootVersion}' is not a valid release version")
}

private void updatePomWithLatestVersions(File pomFile, Map<?, ?> propertyNameToVersionMap) {
    def pomText = pomFile.text
    propertyNameToVersionMap.each { propertyName, highestVersion ->
        pomText = pomText.replaceFirst(
                String.format("<%s>[^<]*<\\/%s>", propertyName, propertyName),
                String.format("<%s>%s<\\/%s>", propertyName, highestVersion, propertyName)
        )
    }

    pomFile.write(pomText)
}

private String getScriptName() {
    final scriptName = new File(getClass().protectionDomain.codeSource.location.path).getName()
    return scriptName.take(scriptName.lastIndexOf('.')) + ".groovy"
}

@EqualsAndHashCode
class GA {
    final String groupId
    final String artifactId

    GA(String groupId, String artifactId) {
        this.groupId = groupId
        this.artifactId = artifactId
    }
}

@EqualsAndHashCode
class PropertyNameAndGA {
    final String propertyName
    final GA ga

    PropertyNameAndGA(String propertyName, GA ga) {
        this.propertyName = propertyName
        this.ga = ga
    }
}
