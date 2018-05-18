package pomutils

import org.apache.maven.repository.internal.DefaultArtifactDescriptorReader
import org.apache.maven.repository.internal.DefaultVersionRangeResolver
import org.apache.maven.repository.internal.DefaultVersionResolver
import org.eclipse.aether.DefaultRepositorySystemSession
import org.eclipse.aether.RepositorySystem
import org.eclipse.aether.connector.basic.BasicRepositoryConnectorFactory
import org.eclipse.aether.impl.ArtifactDescriptorReader
import org.eclipse.aether.impl.DefaultServiceLocator
import org.eclipse.aether.impl.VersionRangeResolver
import org.eclipse.aether.impl.VersionResolver
import org.eclipse.aether.repository.LocalRepository
import org.eclipse.aether.repository.RemoteRepository
import org.eclipse.aether.spi.connector.RepositoryConnectorFactory
import org.eclipse.aether.spi.connector.transport.TransporterFactory
import org.eclipse.aether.transport.http.HttpTransporterFactory

import java.nio.file.Files

final class SetupUtil {

    private SetupUtil() {}

    static MavenContext setup() {
        final serviceLocator = new DefaultServiceLocator().with {
            addService(ArtifactDescriptorReader, DefaultArtifactDescriptorReader)
            addService(RepositoryConnectorFactory, BasicRepositoryConnectorFactory)
            addService(VersionResolver, DefaultVersionResolver)
            addService(VersionRangeResolver, DefaultVersionRangeResolver)
            addService(TransporterFactory, HttpTransporterFactory)
        }

        final system = serviceLocator.getService(RepositorySystem)

        final session = new DefaultRepositorySystemSession().with { it ->
            setLocalRepositoryManager(
                    system.newLocalRepositoryManager(
                            it,
                            new LocalRepository(Files.createTempDirectory("aether").toFile())
                    )
            )
        }

        final remoteRepos = [
                new RemoteRepository.Builder(
                        "central",
                        "default",
                        "http://central.maven.org/maven2/"
                ).build()
        ]

        return new MavenContext(system, session, remoteRepos)
    }
}
