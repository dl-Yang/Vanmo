import { InMemoryConnectionRepository } from './repositories/ConnectionRepository';
import { InMemoryMediaRepository } from './repositories/MediaRepository';
import { InMemoryMetadataCacheRepository } from './repositories/MetadataCacheRepository';
import { InMemoryPlaybackRepository } from './repositories/PlaybackRepository';

export class AppContainer {
  readonly mediaRepository = new InMemoryMediaRepository();
  readonly connectionRepository = new InMemoryConnectionRepository();
  readonly playbackRepository = new InMemoryPlaybackRepository();
  readonly metadataCacheRepository = new InMemoryMetadataCacheRepository();
}

export const appContainer = new AppContainer();
