import type { ConnectionConfig, ConnectionType, RemoteFile } from '../../domain/Connection';
import type { MediaType } from '../../domain/MediaItem';

export interface ServerMediaItem {
  serverId: string;
  title: string;
  originalTitle?: string;
  year?: number;
  overview?: string;
  rating?: number;
  mediaType: MediaType;
  posterUri?: string;
  backdropUri?: string;
  logoUri?: string;
  genres: string[];
  director?: string;
  cast: string[];
  streamUri: string;
  fileSize: number;
  duration: number;
  originalFileName?: string;
  container?: string;
  showTitle?: string;
  seasonNumber?: number;
  episodeNumber?: number;
  episodeTitle?: string;
  seriesId?: string;
  dateCreated?: number;
  lastPlayedAt?: number;
  lastPlaybackPosition: number;
  isFavoriteOnServer: boolean;
}

export interface RemoteFileService {
  readonly type: ConnectionType;
  readonly isConnected: boolean;

  connect(config: ConnectionConfig): Promise<void>;
  disconnect(): Promise<void>;
  listDirectory(path: string): Promise<RemoteFile[]>;
  streamUriFor(file: RemoteFile): Promise<string>;
  download(file: RemoteFile, localUri: string, progress: (value: number) => void): Promise<void>;
}

export interface MediaServerService extends RemoteFileService {
  streamMediaItems(since: number | undefined, pageSize: number): AsyncIterable<ServerMediaItem[]>;
}
