export interface PlaybackRecord {
  id: string;
  mediaItemId: string;
  position: number;
  duration: number;
  playedAt: number;
  selectedAudioTrack?: number;
  selectedSubtitleTrack?: number;
}

export function createPlaybackRecord(mediaItemId: string, position: number, duration: number): PlaybackRecord {
  return {
    id: `${Date.now()}-${mediaItemId}`,
    mediaItemId,
    position,
    duration,
    playedAt: Date.now()
  };
}
