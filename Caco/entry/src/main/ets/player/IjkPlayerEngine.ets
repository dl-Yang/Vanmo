import { CacoError, CacoErrorCode } from '../common/CacoError';
import type { AudioTrackInfo, SubtitleTrackInfo } from '../domain/MediaItem';
import type { PlayerEngine, PlayerEngineObserver } from './PlayerEngine';
import { PlaybackStateKind, type PlaybackState } from './PlaybackState';

export class IjkPlayerEngine implements PlayerEngine {
  private observer?: PlayerEngineObserver;
  private _state: PlaybackState = { kind: PlaybackStateKind.Idle };
  playbackRate: number = 1;

  get state(): PlaybackState {
    return this._state;
  }

  get currentTime(): number {
    return 0;
  }

  get duration(): number {
    return 0;
  }

  setObserver(observer: PlayerEngineObserver): void {
    this.observer = observer;
  }

  async load(uri: string, startPosition?: number): Promise<void> {
    this._state = { kind: PlaybackStateKind.Error, message: 'ijkplayer PoC is not wired yet' };
    this.observer?.onStateChanged(this._state);
    throw new CacoError(CacoErrorCode.UnsupportedFormat, `ijkplayer integration pending for ${uri}`);
  }

  play(): void {}

  pause(): void {}

  async seek(time: number): Promise<void> {}

  stop(): void {
    this._state = { kind: PlaybackStateKind.Idle };
    this.observer?.onStateChanged(this._state);
  }

  async selectAudioTrack(index: number): Promise<void> {}

  async selectSubtitleTrack(index?: number): Promise<void> {}

  async availableAudioTracks(): Promise<AudioTrackInfo[]> {
    return [];
  }

  async availableSubtitleTracks(): Promise<SubtitleTrackInfo[]> {
    return [];
  }
}
