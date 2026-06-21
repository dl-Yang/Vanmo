import type { MediaItem } from '../../domain/MediaItem';

export interface MediaRepository {
  listAll(): Promise<MediaItem[]>;
  listFavorites(): Promise<MediaItem[]>;
  listRecentlyPlayed(limit: number): Promise<MediaItem[]>;
  search(query: string): Promise<MediaItem[]>;
  getById(id: string): Promise<MediaItem | undefined>;
  upsert(item: MediaItem): Promise<void>;
  updatePlaybackProgress(id: string, position: number, playedAt: number): Promise<void>;
  delete(id: string): Promise<void>;
}

export class InMemoryMediaRepository implements MediaRepository {
  private readonly items: Map<string, MediaItem> = new Map();

  async listAll(): Promise<MediaItem[]> {
    return Array.from(this.items.values()).sort((lhs, rhs) => rhs.addedAt - lhs.addedAt);
  }

  async listFavorites(): Promise<MediaItem[]> {
    return (await this.listAll()).filter((item) => item.isFavorite);
  }

  async listRecentlyPlayed(limit: number): Promise<MediaItem[]> {
    return Array.from(this.items.values())
      .filter((item) => item.lastPlayedAt !== undefined)
      .sort((lhs, rhs) => (rhs.lastPlayedAt ?? 0) - (lhs.lastPlayedAt ?? 0))
      .slice(0, limit);
  }

  async search(query: string): Promise<MediaItem[]> {
    const normalized = query.trim().toLowerCase();
    if (normalized.length === 0) {
      return [];
    }

    return Array.from(this.items.values()).filter((item) => {
      return item.title.toLowerCase().includes(normalized) ||
        (item.originalTitle?.toLowerCase().includes(normalized) ?? false) ||
        (item.director?.toLowerCase().includes(normalized) ?? false) ||
        item.cast.some((name) => name.toLowerCase().includes(normalized));
    });
  }

  async getById(id: string): Promise<MediaItem | undefined> {
    return this.items.get(id);
  }

  async upsert(item: MediaItem): Promise<void> {
    this.items.set(item.id, item);
  }

  async updatePlaybackProgress(id: string, position: number, playedAt: number): Promise<void> {
    const item = this.items.get(id);
    if (!item) {
      return;
    }

    item.lastPlaybackPosition = position;
    item.lastPlayedAt = playedAt;
    item.isWatched = item.duration > 0 && position / item.duration >= 0.9;
  }

  async delete(id: string): Promise<void> {
    this.items.delete(id);
  }
}
