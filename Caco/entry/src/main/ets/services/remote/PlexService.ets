import { ConnectionType } from '../../domain/Connection';
import type { ServerMediaItem } from './RemoteFileService';
import { MediaServerBaseService } from './MediaServerBaseService';

export class PlexService extends MediaServerBaseService {
  constructor() {
    super(ConnectionType.Plex);
  }

  async *streamMediaItems(since: number | undefined, pageSize: number): AsyncIterable<ServerMediaItem[]> {
    // Plex XML mapping is intentionally isolated from Emby/Jellyfin because the
    // response model and token semantics differ. The HTTP surface is ready for
    // the follow-up parser implementation.
    yield [];
  }
}
