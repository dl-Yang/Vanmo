import { appContainer } from '../data/AppContainer';
import type { MediaItem } from '../domain/MediaItem';

export class LibraryViewModel {
  items: MediaItem[] = [];
  favorites: MediaItem[] = [];
  recentlyPlayed: MediaItem[] = [];
  isLoading: boolean = false;

  async load(): Promise<void> {
    this.isLoading = true;
    this.items = await appContainer.mediaRepository.listAll();
    this.favorites = await appContainer.mediaRepository.listFavorites();
    this.recentlyPlayed = await appContainer.mediaRepository.listRecentlyPlayed(10);
    this.isLoading = false;
  }
}
