import type { AudioTrackInfo, SubtitleTrackInfo } from '../domain/MediaItem';
import type { PlayerEngine, PlayerEngineObserver } from './PlayerEngine';
import { PlaybackStateKind, type PlaybackState } from './PlaybackState';

export class SystemPlayerEngine implements PlayerEngine {
  private observer?: PlayerEngineObserver;
  private _state: PlaybackState = { kind: PlaybackStateKind.Idle };
  private _currentTime: number = 0;
  private _duration: number = 0;
  playbackRate: number = 1;

  get state(): PlaybackState {
    return this._state;
  }

  get currentTime(): number {
    return this._currentTime;
  }

  get duration(): number {
    return this._duration;
  }

  setObserver(observer: PlayerEngineObserver): void {
    this.observer = observer;
  }

  async load(uri: string, startPosition?: number): Promise<void> {
    this.updateState({ kind: PlaybackStateKind.Loading });
    this._currentTime = startPosition ?? 0;
    this._duration = 0;
    this.observer?.onTimeChanged(this._currentTime, this._duration);
    // Wire HarmonyOS media AVPlayer here after device PoC.
    this.updateState({ kind: PlaybackStateKind.Paused });
  }

  play(): void {
    this.updateState({ kind: PlaybackStateKind.Playing });
  }

  pause(): void {
    this.updateState({ kind: PlaybackStateKind.Paused });
  }

  async seek(time: number): Promise<void> {
    this._currentTime = time;
    this.observer?.onTimeChanged(this._currentTime, this._duration);
  }

  stop(): void {
    this._currentTime = 0;
    this._duration = 0;
    this.updateState({ kind: PlaybackStateKind.Idle });
  }

  async selectAudioTrack(index: number): Promise<void> {}

  async selectSubtitleTrack(index?: number): Promise<void> {}

  async availableAudioTracks(): Promise<AudioTrackInfo[]> {
    return [];
  }

  async availableSubtitleTracks(): Promise<SubtitleTrackInfo[]> {
    return [];
  }

  private updateState(state: PlaybackState): void {
    this._state = state;
    this.observer?.onStateChanged(state);
  }
}
