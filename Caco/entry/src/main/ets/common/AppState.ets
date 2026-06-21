import { AppTab } from './AppRoute';
import type { MediaItem } from '../domain/MediaItem';

export class AppState {
  selectedTab: AppTab = AppTab.Library;
  currentPlayingItem?: MediaItem;
  isPlayerPresented: boolean = false;

  selectTab(tab: AppTab): void {
    this.selectedTab = tab;
  }

  play(item: MediaItem): void {
    this.currentPlayingItem = item;
    this.isPlayerPresented = true;
  }

  dismissPlayer(): void {
    this.isPlayerPresented = false;
  }
}

export const appState = new AppState();
