import type { PlaybackRecord } from '../../domain/PlaybackRecord';

export interface PlaybackRepository {
  add(record: PlaybackRecord): Promise<void>;
  latestForMedia(mediaItemId: string): Promise<PlaybackRecord | undefined>;
  listRecent(limit: number): Promise<PlaybackRecord[]>;
  deleteForMedia(mediaItemId: string): Promise<void>;
}

export class InMemoryPlaybackRepository implements PlaybackRepository {
  private readonly records: PlaybackRecord[] = [];

  async add(record: PlaybackRecord): Promise<void> {
    this.records.push(record);
  }

  async latestForMedia(mediaItemId: string): Promise<PlaybackRecord | undefined> {
    return this.records
      .filter((record) => record.mediaItemId === mediaItemId)
      .sort((lhs, rhs) => rhs.playedAt - lhs.playedAt)[0];
  }

  async listRecent(limit: number): Promise<PlaybackRecord[]> {
    return [...this.records].sort((lhs, rhs) => rhs.playedAt - lhs.playedAt).slice(0, limit);
  }

  async deleteForMedia(mediaItemId: string): Promise<void> {
    for (let index = this.records.length - 1; index >= 0; index--) {
      if (this.records[index].mediaItemId === mediaItemId) {
        this.records.splice(index, 1);
      }
    }
  }
}
