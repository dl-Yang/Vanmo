export enum PlaybackStateKind {
  Idle = 'idle',
  Loading = 'loading',
  Playing = 'playing',
  Paused = 'paused',
  Buffering = 'buffering',
  Error = 'error',
  Ended = 'ended'
}

export interface PlaybackState {
  kind: PlaybackStateKind;
  message?: string;
}

export enum VideoScaleMode {
  Fit = 'fit',
  Fill = 'fill',
  Stretch = 'stretch'
}

export interface PlayerConfig {
  playbackRate: number;
  scaleMode: VideoScaleMode;
  selectedAudioTrack: number;
  selectedSubtitleTrack?: number;
  subtitleDelay: number;
  brightness?: number;
  volume: number;
  isMuted: boolean;
}

export const DefaultPlayerConfig: PlayerConfig = {
  playbackRate: 1,
  scaleMode: VideoScaleMode.Fit,
  selectedAudioTrack: 0,
  subtitleDelay: 0,
  volume: 1,
  isMuted: false
};
