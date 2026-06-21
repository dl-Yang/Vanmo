export enum MetadataAssetKind {
  Poster = 'poster',
  Backdrop = 'backdrop',
  Logo = 'logo',
  CastProfile = 'castProfile',
  EpisodeStill = 'episodeStill'
}

export interface MetadataCacheRecord {
  id: string;
  mediaItemId: string;
  sourceConnectionId?: string;
  serverId?: string;
  kind: MetadataAssetKind;
  remoteUri: string;
  localUri: string;
  updatedAt: number;
  byteSize: number;
}
