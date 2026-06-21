import { appContainer } from '../data/AppContainer';
import { credentialStore } from '../data/SecureCredentialStore';
import type { ConnectionConfig, SavedConnection } from '../domain/Connection';
import { RemoteServiceFactory } from '../services/remote/RemoteServiceFactory';
import type { RemoteFileService } from '../services/remote/RemoteFileService';

export class ConnectionsViewModel {
  connections: SavedConnection[] = [];
  activeService?: RemoteFileService;

  async load(): Promise<void> {
    this.connections = await appContainer.connectionRepository.listAll();
  }

  async connect(connection: SavedConnection): Promise<void> {
    const password = await credentialStore.readPassword(connection.id);
    const config: ConnectionConfig = {
      type: connection.type,
      host: connection.host,
      port: connection.port,
      username: connection.username,
      password,
      path: connection.path,
      localUri: connection.localUri
    };

    const service = RemoteServiceFactory.make(connection.type);
    await service.connect(config);
    await appContainer.connectionRepository.markConnected(connection.id, Date.now());
    this.activeService = service;
  }
}
