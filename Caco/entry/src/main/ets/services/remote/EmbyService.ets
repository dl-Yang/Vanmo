import { ConnectionType } from '../../domain/Connection';
import { MediaType } from '../../domain/MediaItem';
import type { ServerMediaItem } from './RemoteFileService';
import { MediaServerBaseService } from './MediaServerBaseService';

interface EmbyItemsResponse {
  Items?: EmbyItem[];
}

interface EmbyItem {
  Id: string;
  Name: string;
  OriginalTitle?: string;
  ProductionYear?: number;
  Overview?: string;
  CommunityRating?: number;
  Type: string;
  RunTimeTicks?: number;
  Container?: string;
  SeriesId?: string;
  SeriesName?: string;
  ParentIndexNumber?: number;
  IndexNumber?: number;
  DateCreated?: string;
}

export class EmbyService extends MediaServerBaseService {
  constructor(type: ConnectionType = ConnectionType.Emby) {
    super(type);
  }

  async *streamMediaItems(since: number | undefined, pageSize: number): AsyncIterable<ServerMediaItem[]> {
    const uri = `${this.baseUri()}/Items?Recursive=true&IncludeItemTypes=Movie,Episode,Series&Limit=${pageSize}`;
    const response = await this.client.requestJson<EmbyItemsResponse>(uri);
    const items = response.Items ?? [];
    yield items.map((item) => this.mapItem(item));
  }

  private mapItem(item: EmbyItem): ServerMediaItem {
    const base = this.baseUri();
    const mediaType = item.Type === 'Episode' ? MediaType.TvEpisode :
      item.Type === 'Series' ? MediaType.TvShow : MediaType.Movie;

    return {
      serverId: item.Id,
      title: item.Name,
      originalTitle: item.OriginalTitle,
      year: item.ProductionYear,
      overview: item.Overview,
      rating: item.CommunityRating,
      mediaType,
      posterUri: `${base}/Items/${item.Id}/Images/Primary`,
      backdropUri: `${base}/Items/${item.Id}/Images/Backdrop`,
      logoUri: `${base}/Items/${item.Id}/Images/Logo`,
      genres: [],
      cast: [],
      streamUri: `${base}/Videos/${item.Id}/stream`,
      fileSize: 0,
      duration: (item.RunTimeTicks ?? 0) / 10000000,
      container: item.Container,
      showTitle: item.SeriesName,
      seasonNumber: item.ParentIndexNumber,
      episodeNumber: item.IndexNumber,
      seriesId: item.SeriesId,
      dateCreated: item.DateCreated ? Date.parse(item.DateCreated) : undefined,
      lastPlaybackPosition: 0,
      isFavoriteOnServer: false
    };
  }
}
