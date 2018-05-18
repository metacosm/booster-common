package pomutils


import org.eclipse.aether.artifact.DefaultArtifact
import org.eclipse.aether.resolution.VersionRangeRequest
import org.eclipse.aether.version.Version

class MavenGaHighestVersionSearcher {

    private final SetupResult setupResult

    MavenGaHighestVersionSearcher(SetupResult setupResult) {
        this.setupResult = setupResult
    }

    Version getHighestVersion(String groupId, String artifactId) {
        final artifact = new DefaultArtifact( "${groupId}:${artifactId}:[0,)" )

        final rangeResult = setupResult.system.resolveVersionRange(
                setupResult.session,
                new VersionRangeRequest().with {
                    setArtifact(artifact)
                    setRepositories(setupResult.remoteRepositories)
                }
        )

        return rangeResult.getHighestVersion()
    }


}


