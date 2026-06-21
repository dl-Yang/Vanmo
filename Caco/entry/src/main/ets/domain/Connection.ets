export enum ConnectionType {
  LocalFolder = 'localFolder',
  Smb = 'smb',
  Ftp = 'ftp',
  Sftp = 'sftp',
  WebDav = 'webdav',
  Nfs = 'nfs',
  Dlna = 'dlna',
  Plex = 'plex',
  Emby = 'emby',
  Jellyfin = 'jellyfin'
}

export interface SavedConnection {
  id: string;
  name: string;
  type: ConnectionType;
  host: string;
  port: number;
  username?: string;
  path?: string;
  localUri?: string;
  isFavorite: boolean;
  lastConnectedAt?: number;
  lastSyncedAt?: number;
  addedAt: number;
}

export interface ConnectionConfig {
  type: ConnectionType;
  host: string;
  port: number;
  username?: string;
  password?: string;
  path?: string;
  localUri?: string;
}

export enum RemoteFileType {
  Video = 'video',
  Subtitle = 'subtitle',
  Audio = 'audio',
  Image = 'image',
  Directory = 'directory',
  Other = 'other'
}

export interface RemoteFile {
  id: string;
  name: string;
  path: string;
  size: number;
  isDirectory: boolean;
  modifiedAt?: number;
  type: RemoteFileType;
}

export function defaultPort(type: ConnectionType): number {
  switch (type) {
    case ConnectionType.Smb:
      return 445;
    case ConnectionType.Ftp:
      return 21;
    case ConnectionType.Sftp:
      return 22;
    case ConnectionType.WebDav:
      return 80;
    case ConnectionType.Nfs:
      return 2049;
    case ConnectionType.Plex:
      return 32400;
    case ConnectionType.Emby:
    case ConnectionType.Jellyfin:
      return 8096;
    default:
      return 0;
  }
}

export function isMediaServer(type: ConnectionType): boolean {
  return type === ConnectionType.Emby || type === ConnectionType.Jellyfin || type === ConnectionType.Plex;
}
