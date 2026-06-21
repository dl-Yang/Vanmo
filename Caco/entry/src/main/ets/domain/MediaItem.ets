export enum MediaType {
  Movie = 'movie',
  TvShow = 'tvShow',
  TvEpisode = 'tvEpisode',
  Season = 'season',
  Folder = 'folder',
  CollectionFolder = 'collectionFolder',
  Audio = 'audio',
  MusicAlbum = 'musicAlbum',
  Photo = 'photo',
  Other = 'other'
}

export interface AudioTrackInfo {
  id: number;
  language?: string;
  title?: string;
  codec?: string;
  channels?: number;
}

export interface SubtitleTrackInfo {
  id: number;
  language?: string;
  title?: string;
  isEmbedded: boolean;
  fileUri?: string;
}

export interface CastMemberInfo {
  id: string;
  name: string;
  role?: string;
  profileUri?: string;
}

export interface MediaItem {
  id: string;
  title: string;
  originalTitle?: string;
  year?: number;
  overview?: string;
  posterUri?: string;
  backdropUri?: string;
  logoUri?: string;
  rating?: number;
  mediaType: MediaType;
  fileUri: string;
  fileSize: number;
  duration: number;
  originalFileName?: string;
  container?: string;
  lastPlayedAt?: number;
  lastPlaybackPosition: number;
  isWatched: boolean;
  isFavorite: boolean;
  addedAt: number;
  tmdbId?: number;
  genres: string[];
  director?: string;
  cast: string[];
  castMembers: CastMemberInfo[];
  originCountry: string[];
  seasonNumber?: number;
  episodeNumber?: number;
  showTitle?: string;
  episodeTitle?: string;
  serverId?: string;
  seriesId?: string;
  sourceConnectionId?: string;
  audioTracks: AudioTrackInfo[];
  subtitleTracks: SubtitleTrackInfo[];
}

export function createMediaItem(title: string, fileUri: string, mediaType: MediaType = MediaType.Movie): MediaItem {
  return {
    id: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
    title,
    mediaType,
    fileUri,
    fileSize: 0,
    duration: 0,
    lastPlaybackPosition: 0,
    isWatched: false,
    isFavorite: false,
    addedAt: Date.now(),
    genres: [],
    cast: [],
    castMembers: [],
    originCountry: [],
    audioTracks: [],
    subtitleTracks: []
  };
}

export function playbackProgress(item: MediaItem): number {
  if (item.duration <= 0) {
    return 0;
  }

  return item.lastPlaybackPosition / item.duration;
}
