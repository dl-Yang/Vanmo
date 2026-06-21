import type { AudioTrackInfo, SubtitleTrackInfo } from '../domain/MediaItem';
import type { PlaybackState } from './PlaybackState';

export interface SubtitleContent {
  text?: string;
  imageUri?: string;
}

export interface PlayerEngineObserver {
  onStateChanged(state: PlaybackState): void;
  onTimeChanged(currentTime: number, duration: number): void;
  onBufferChanged(progress: number): void;
  onSubtitleChanged(content?: SubtitleContent): void;
}

export interface PlayerEngine {
  readonly state: PlaybackState;
  readonly currentTime: number;
  readonly duration: number;
  playbackRate: number;

  setObserver(observer: PlayerEngineObserver): void;
  load(uri: string, startPosition?: number): Promise<void>;
  play(): void;
  pause(): void;
  seek(time: number): Promise<void>;
  stop(): void;
  selectAudioTrack(index: number): Promise<void>;
  selectSubtitleTrack(index?: number): Promise<void>;
  availableAudioTracks(): Promise<AudioTrackInfo[]>;
  availableSubtitleTracks(): Promise<SubtitleTrackInfo[]>;
}
