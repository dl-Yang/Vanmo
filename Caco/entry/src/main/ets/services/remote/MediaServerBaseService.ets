import { CacoError, CacoErrorCode } from '../../common/CacoError';
import type { ConnectionConfig, ConnectionType, RemoteFile } from '../../domain/Connection';
import type { MediaServerService, ServerMediaItem } from './RemoteFileService';
import { httpClient, HttpClient } from './HttpClient';

export abstract class MediaServerBaseService implements MediaServerService {
  readonly type: ConnectionType;
  protected config?: ConnectionConfig;
  protected client: HttpClient;

  constructor(type: ConnectionType, client: HttpClient = httpClient) {
    this.type = type;
    this.client = client;
  }

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
    throw new CacoError(CacoErrorCode.Network, `${this.type} folder browsing is not implemented yet for path ${path}`);
  }

  async streamUriFor(file: RemoteFile): Promise<string> {
    if (!this.config) {
      throw new CacoError(CacoErrorCode.Authentication, `${this.type} is not connected`);
    }

    return file.path;
  }

  async download(file: RemoteFile, localUri: string, progress: (value: number) => void): Promise<void> {
    progress(0);
    throw new CacoError(CacoErrorCode.Network, `${this.type} download is pending implementation for ${file.name}`);
  }

  abstract streamMediaItems(since: number | undefined, pageSize: number): AsyncIterable<ServerMediaItem[]>;

  protected baseUri(): string {
    if (!this.config) {
      throw new CacoError(CacoErrorCode.Authentication, `${this.type} is not connected`);
    }

    const scheme = this.config.port === 443 ? 'https' : 'http';
    const path = this.config.path ?? '';
    return `${scheme}://${this.config.host}:${this.config.port}${path}`;
  }
}
