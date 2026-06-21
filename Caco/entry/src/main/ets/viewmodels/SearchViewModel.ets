import { appContainer } from '../data/AppContainer';
import type { MediaItem } from '../domain/MediaItem';

export class SearchViewModel {
  query: string = '';
  results: MediaItem[] = [];

  async updateQuery(query: string): Promise<void> {
    this.query = query;
    this.results = await appContainer.mediaRepository.search(query);
  }
}
