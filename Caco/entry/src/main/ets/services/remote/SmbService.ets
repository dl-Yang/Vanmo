import { CacoError, CacoErrorCode } from '../../common/CacoError';
import { ConnectionType, type ConnectionConfig, type RemoteFile } from '../../domain/Connection';
import type { RemoteFileService } from './RemoteFileService';

export class SmbService implements RemoteFileService {
  readonly type: ConnectionType = ConnectionType.Smb;
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
    throw new CacoError(
      CacoErrorCode.Network,
      `SMB directory listing needs the ArkTS smb2 or NDK libsmbclient PoC before enabling path ${path}`
    );
  }

  async streamUriFor(file: RemoteFile): Promise<string> {
    if (!this.config) {
      throw new CacoError(CacoErrorCode.Authentication, 'SMB is not connected');
    }

    // SMB playback must go through PrefetchProxy so credentials never appear
    // in a player-consumable URI.
    return `caco-prefetch://smb/${encodeURIComponent(file.path)}`;
  }

  async download(file: RemoteFile, localUri: string, progress: (value: number) => void): Promise<void> {
    progress(0);
    throw new CacoError(CacoErrorCode.Network, `SMB download is pending implementation for ${file.name}`);
  }
}
