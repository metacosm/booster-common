@Grapes([
        @Grab(group = 'org.apache.maven', module = 'maven-resolver-provider', version = '3.5.3'),
        @Grab(group='org.apache.maven.resolver', module='maven-resolver-connector-basic', version= '1.1.1'),
        @Grab(group='org.apache.maven.resolver', module='maven-resolver-transport-http', version= '1.1.1'),
        @Grab(group='ch.qos.logback', module='logback-classic', version='1.2.3'),
])

import ch.qos.logback.classic.Level
import groovy.transform.EqualsAndHashCode
import org.slf4j.Logger
import org.slf4j.LoggerFactory
import pomutils.MavenGaHighestVersionSearcher
import pomutils.SetupUtil

setupLogging()

final searcher = new MavenGaHighestVersionSearcher(SetupUtil.setup())

final pomFile = new File(args[0])
final pomXml = new XmlSlurper().parse(pomFile)

final List<PropertyNameAndGA> gaWithPropertyList =
        pomXml.dependencyManagement.dependencies.childNodes().collect {
            final versionNode = it.children.find {it .name == 'version'}
            final groupIdNode = it.children.find {it .name == 'groupId'}
            final artifactIdNode = it.children.find {it .name == 'artifactId'}
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

final propertyNameToHighestVersionMap =
        propertyNameToFirstGAMap.collectEntries { property, ga ->
            final highestVersion = searcher.getHighestVersion(ga.groupId, ga.artifactId)
            [(property): highestVersion.toString()]
        }


updatePomWithLatestVersions(pomFile, propertyNameToHighestVersionMap)

private Logger setupLogging() {
    LoggerFactory.getLogger("org.apache.http").level = Level.WARN
    LoggerFactory.getLogger("org.eclipse.aether").level = Level.WARN
    final logger = LoggerFactory.getLogger(this.class.getName())
    logger.level = Level.INFO
    return logger
}

private void updatePomWithLatestVersions(File pomFile, Map<?, ?> propertyNameToHighestVersionMap) {
    final pomText = pomFile.text
    propertyNameToHighestVersionMap.each { propertyName, highestVersion ->
        pomText = pomText.replaceFirst(
                String.format("<%s>.*</%s>", propertyName, propertyName),
                String.format("<%s>%s</%s>", propertyName, highestVersion, propertyName)
        )
    }

    pomFile.write(pomText)
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