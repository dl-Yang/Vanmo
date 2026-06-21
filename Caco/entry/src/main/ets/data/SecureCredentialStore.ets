export interface CredentialStore {
  savePassword(connectionId: string, password: string): Promise<void>;
  readPassword(connectionId: string): Promise<string | undefined>;
  deletePassword(connectionId: string): Promise<void>;
}

export class InMemoryCredentialStore implements CredentialStore {
  private readonly passwords: Map<string, string> = new Map();

  async savePassword(connectionId: string, password: string): Promise<void> {
    this.passwords.set(connectionId, password);
  }

  async readPassword(connectionId: string): Promise<string | undefined> {
    return this.passwords.get(connectionId);
  }

  async deletePassword(connectionId: string): Promise<void> {
    this.passwords.delete(connectionId);
  }
}

export const credentialStore: CredentialStore = new InMemoryCredentialStore();
