import { appContainer } from '../data/AppContainer';
import type { MediaItem } from '../domain/MediaItem';
import { createPlaybackRecord } from '../domain/PlaybackRecord';
import type { PlayerEngine, PlayerEngineObserver, SubtitleContent } from '../player/PlayerEngine';
import { PlayerEngineFactory } from '../player/PlayerEngineFactory';
import { PlaybackStateKind, type PlaybackState } from '../player/PlaybackState';

export class PlayerViewModel implements PlayerEngineObserver {
  item?: MediaItem;
  state: PlaybackState = { kind: PlaybackStateKind.Idle };
  currentTime: number = 0;
  duration: number = 0;
  bufferProgress: number = 0;
  subtitle?: SubtitleContent;
  private engine?: PlayerEngine;

  async load(item: MediaItem): Promise<void> {
    this.item = item;
    this.engine = PlayerEngineFactory.make(item.fileUri);
    this.engine.setObserver(this);
    await this.engine.load(item.fileUri, item.lastPlaybackPosition);
  }

  play(): void {
    this.engine?.play();
  }

  pause(): void {
    this.engine?.pause();
  }

  async seek(time: number): Promise<void> {
    await this.engine?.seek(time);
  }

  async stopAndPersist(): Promise<void> {
    this.engine?.stop();
    if (!this.item) {
      return;
    }

    const record = createPlaybackRecord(this.item.id, this.currentTime, this.duration);
    await appContainer.playbackRepository.add(record);
    await appContainer.mediaRepository.updatePlaybackProgress(this.item.id, this.currentTime, Date.now());
  }

  onStateChanged(state: PlaybackState): void {
    this.state = state;
  }

  onTimeChanged(currentTime: number, duration: number): void {
    this.currentTime = currentTime;
    this.duration = duration;
  }

  onBufferChanged(progress: number): void {
    this.bufferProgress = progress;
  }

  onSubtitleChanged(content?: SubtitleContent): void {
    this.subtitle = content;
  }
}
