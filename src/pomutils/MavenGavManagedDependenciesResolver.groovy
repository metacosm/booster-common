package pomutils

import org.eclipse.aether.artifact.Artifact
import org.eclipse.aether.artifact.DefaultArtifact
import org.eclipse.aether.graph.Dependency
import org.eclipse.aether.resolution.ArtifactDescriptorRequest
import org.eclipse.aether.resolution.ArtifactDescriptorResult

class MavenGavManagedDependenciesResolver {

    private final MavenContext setupResult

    MavenGavManagedDependenciesResolver(MavenContext setupResult) {
        this.setupResult = setupResult
    }

    List<Dependency> resolve(String groupId, String artifactId, String version) {
        final Artifact artifact = new DefaultArtifact( "${groupId}:${artifactId}:${version}")

        final ArtifactDescriptorRequest descriptorRequest = new ArtifactDescriptorRequest().with {
            setArtifact(artifact)
            setRepositories(setupResult.remoteRepositories)
        }

        ArtifactDescriptorResult descriptorResult =
                setupResult.system.readArtifactDescriptor(setupResult.session, descriptorRequest )

        return descriptorResult.managedDependencies
    }
}
