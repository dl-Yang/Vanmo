import { CacoError, CacoErrorCode } from '../../common/CacoError';
import { ConnectionType, RemoteFileType, type ConnectionConfig, type RemoteFile } from '../../domain/Connection';
import type { RemoteFileService } from './RemoteFileService';
import { httpClient } from './HttpClient';

export class WebDavService implements RemoteFileService {
  readonly type: ConnectionType = ConnectionType.WebDav;
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
    if (!this.config) {
      throw new CacoError(CacoErrorCode.Authentication, 'WebDAV is not connected');
    }

    const uri = this.resolveUri(path);
    const xml = await httpClient.requestText(uri, {
      method: 'PROPFIND',
      headers: {
        Depth: '1'
      }
    });

    return this.parsePropfind(xml);
  }

  async streamUriFor(file: RemoteFile): Promise<string> {
    return this.resolveUri(file.path);
  }

  async download(file: RemoteFile, localUri: string, progress: (value: number) => void): Promise<void> {
    progress(0);
    throw new CacoError(CacoErrorCode.Network, `WebDAV download is pending implementation for ${file.name}`);
  }

  private resolveUri(path: string): string {
    if (!this.config) {
      throw new CacoError(CacoErrorCode.Authentication, 'WebDAV is not connected');
    }

    const scheme = this.config.port === 443 ? 'https' : 'http';
    const root = this.config.path ?? '';
    return `${scheme}://${this.config.host}:${this.config.port}${root}${path}`;
  }

  private parsePropfind(xml: string): RemoteFile[] {
    // Replace this with xml.ConvertXML or fast-xml-parser once the HarmonyOS
    // SDK version is locked. Keeping parser output behind this method limits
    // future schema churn to this service.
    if (xml.length === 0) {
      return [];
    }

    return [];
  }
}
