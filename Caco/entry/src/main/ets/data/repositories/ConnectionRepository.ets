import type { SavedConnection } from '../../domain/Connection';

export interface ConnectionRepository {
  listAll(): Promise<SavedConnection[]>;
  getById(id: string): Promise<SavedConnection | undefined>;
  upsert(connection: SavedConnection): Promise<void>;
  markConnected(id: string, connectedAt: number): Promise<void>;
  markSynced(id: string, syncedAt: number): Promise<void>;
  delete(id: string): Promise<void>;
}

export class InMemoryConnectionRepository implements ConnectionRepository {
  private readonly connections: Map<string, SavedConnection> = new Map();

  async listAll(): Promise<SavedConnection[]> {
    return Array.from(this.connections.values()).sort((lhs, rhs) => rhs.addedAt - lhs.addedAt);
  }

  async getById(id: string): Promise<SavedConnection | undefined> {
    return this.connections.get(id);
  }

  async upsert(connection: SavedConnection): Promise<void> {
    this.connections.set(connection.id, connection);
  }

  async markConnected(id: string, connectedAt: number): Promise<void> {
    const connection = this.connections.get(id);
    if (connection) {
      connection.lastConnectedAt = connectedAt;
    }
  }

  async markSynced(id: string, syncedAt: number): Promise<void> {
    const connection = this.connections.get(id);
    if (connection) {
      connection.lastSyncedAt = syncedAt;
    }
  }

  async delete(id: string): Promise<void> {
    this.connections.delete(id);
  }
}
