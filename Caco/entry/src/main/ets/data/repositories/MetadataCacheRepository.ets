import type { MetadataCacheRecord } from '../../domain/Metadata';

export interface MetadataCacheRepository {
  upsert(record: MetadataCacheRecord): Promise<void>;
  listForMedia(mediaItemId: string): Promise<MetadataCacheRecord[]>;
  totalByteSize(): Promise<number>;
  clearAll(): Promise<void>;
}

export class InMemoryMetadataCacheRepository implements MetadataCacheRepository {
  private readonly records: Map<string, MetadataCacheRecord> = new Map();

  async upsert(record: MetadataCacheRecord): Promise<void> {
    this.records.set(record.id, record);
  }

  async listForMedia(mediaItemId: string): Promise<MetadataCacheRecord[]> {
    return Array.from(this.records.values()).filter((record) => record.mediaItemId === mediaItemId);
  }

  async totalByteSize(): Promise<number> {
    return Array.from(this.records.values()).reduce((total, record) => total + record.byteSize, 0);
  }

  async clearAll(): Promise<void> {
    this.records.clear();
  }
}
