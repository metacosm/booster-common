package pomutils

import org.eclipse.aether.RepositorySystem
import org.eclipse.aether.RepositorySystemSession
import org.eclipse.aether.repository.RemoteRepository

class MavenContext {

    final RepositorySystem system
    final RepositorySystemSession session
    final List<RemoteRepository> remoteRepositories

    MavenContext(RepositorySystem system,
                 RepositorySystemSession session,
                 List<RemoteRepository> remoteRepositories) {
        this.system = system
        this.session = session
        this.remoteRepositories = remoteRepositories
    }
}
