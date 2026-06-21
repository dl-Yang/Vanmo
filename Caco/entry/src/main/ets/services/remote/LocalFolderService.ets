import { ConnectionType, RemoteFileType, type ConnectionConfig, type RemoteFile } from '../../domain/Connection';
import type { RemoteFileService } from './RemoteFileService';

export class LocalFolderService implements RemoteFileService {
  readonly type: ConnectionType = ConnectionType.LocalFolder;
  private config?: ConnectionConfig;

  get isConnected(): boolean {
    return this.config !== undefined;
  }

  async connect(config: ConnectionConfig): Promise<void> {
    this.config = config;
  }

  async disconnect(): Promise<void> {
    this.config = undefined;
  }

  async listDirectory(path: string): Promise<RemoteFile[]> {
    // HarmonyOS file picker URI access will be wired after device validation.
    return [];
  }

  async streamUriFor(file: RemoteFile): Promise<string> {
    return file.path;
  }

  async download(file: RemoteFile, localUri: string, progress: (value: number) => void): Promise<void> {
    progress(1);
  }
}
