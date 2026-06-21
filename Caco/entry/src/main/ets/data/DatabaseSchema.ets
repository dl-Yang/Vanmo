export interface ColumnSchema {
  name: string;
  type: 'TEXT' | 'INTEGER' | 'REAL' | 'BLOB';
  primaryKey?: boolean;
  notNull?: boolean;
  defaultValue?: string | number;
}

export interface TableSchema {
  name: string;
  columns: ColumnSchema[];
  indexes: string[];
}

export const DatabaseVersion = 1;

export const MediaItemTable: TableSchema = {
  name: 'media_items',
  columns: [
    { name: 'id', type: 'TEXT', primaryKey: true, notNull: true },
    { name: 'title', type: 'TEXT', notNull: true },
    { name: 'media_type', type: 'TEXT', notNull: true },
    { name: 'file_uri', type: 'TEXT', notNull: true },
    { name: 'file_size', type: 'INTEGER', defaultValue: 0 },
    { name: 'duration', type: 'REAL', defaultValue: 0 },
    { name: 'last_played_at', type: 'INTEGER' },
    { name: 'last_playback_position', type: 'REAL', defaultValue: 0 },
    { name: 'is_watched', type: 'INTEGER', defaultValue: 0 },
    { name: 'is_favorite', type: 'INTEGER', defaultValue: 0 },
    { name: 'added_at', type: 'INTEGER', notNull: true },
    { name: 'source_connection_id', type: 'TEXT' },
    { name: 'server_id', type: 'TEXT' },
    { name: 'payload_json', type: 'TEXT', notNull: true }
  ],
  indexes: [
    'CREATE INDEX IF NOT EXISTS idx_media_added_at ON media_items(added_at)',
    'CREATE INDEX IF NOT EXISTS idx_media_favorite ON media_items(is_favorite)',
    'CREATE INDEX IF NOT EXISTS idx_media_source_connection ON media_items(source_connection_id)',
    'CREATE INDEX IF NOT EXISTS idx_media_server ON media_items(server_id)'
  ]
};

export const SavedConnectionTable: TableSchema = {
  name: 'saved_connections',
  columns: [
    { name: 'id', type: 'TEXT', primaryKey: true, notNull: true },
    { name: 'name', type: 'TEXT', notNull: true },
    { name: 'type', type: 'TEXT', notNull: true },
    { name: 'host', type: 'TEXT', notNull: true },
    { name: 'port', type: 'INTEGER', notNull: true },
    { name: 'username', type: 'TEXT' },
    { name: 'path', type: 'TEXT' },
    { name: 'local_uri', type: 'TEXT' },
    { name: 'is_favorite', type: 'INTEGER', defaultValue: 0 },
    { name: 'last_connected_at', type: 'INTEGER' },
    { name: 'last_synced_at', type: 'INTEGER' },
    { name: 'added_at', type: 'INTEGER', notNull: true }
  ],
  indexes: [
    'CREATE INDEX IF NOT EXISTS idx_connections_type ON saved_connections(type)',
    'CREATE INDEX IF NOT EXISTS idx_connections_favorite ON saved_connections(is_favorite)'
  ]
};

export const PlaybackRecordTable: TableSchema = {
  name: 'playback_records',
  columns: [
    { name: 'id', type: 'TEXT', primaryKey: true, notNull: true },
    { name: 'media_item_id', type: 'TEXT', notNull: true },
    { name: 'position', type: 'REAL', defaultValue: 0 },
    { name: 'duration', type: 'REAL', defaultValue: 0 },
    { name: 'played_at', type: 'INTEGER', notNull: true },
    { name: 'selected_audio_track', type: 'INTEGER' },
    { name: 'selected_subtitle_track', type: 'INTEGER' }
  ],
  indexes: [
    'CREATE INDEX IF NOT EXISTS idx_playback_media ON playback_records(media_item_id)',
    'CREATE INDEX IF NOT EXISTS idx_playback_played_at ON playback_records(played_at)'
  ]
};

export const MetadataCacheTable: TableSchema = {
  name: 'metadata_cache_records',
  columns: [
    { name: 'id', type: 'TEXT', primaryKey: true, notNull: true },
    { name: 'media_item_id', type: 'TEXT', notNull: true },
    { name: 'source_connection_id', type: 'TEXT' },
    { name: 'server_id', type: 'TEXT' },
    { name: 'kind', type: 'TEXT', notNull: true },
    { name: 'remote_uri', type: 'TEXT', notNull: true },
    { name: 'local_uri', type: 'TEXT', notNull: true },
    { name: 'updated_at', type: 'INTEGER', notNull: true },
    { name: 'byte_size', type: 'INTEGER', defaultValue: 0 }
  ],
  indexes: [
    'CREATE INDEX IF NOT EXISTS idx_metadata_media ON metadata_cache_records(media_item_id)',
    'CREATE INDEX IF NOT EXISTS idx_metadata_server ON metadata_cache_records(server_id)'
  ]
};

export const AllTables: TableSchema[] = [
  MediaItemTable,
  SavedConnectionTable,
  PlaybackRecordTable,
  MetadataCacheTable
];
