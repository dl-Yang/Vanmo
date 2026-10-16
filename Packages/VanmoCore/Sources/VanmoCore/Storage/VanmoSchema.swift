import SwiftData

/// Current SwiftData models. The next non-additive change adds a later version
/// and one lightweight `MigrationStage`. Custom stages stay unused because
/// CloudStore can attach CloudKit.
public enum VanmoSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static let models: [any PersistentModel.Type] = [
        MediaItem.self,
        SavedConnection.self,
        PlaybackRecord.self,
        FolderBookmark.self,
        CloudMediaState.self,
        ConnectionTombstone.self,
        ScanJobRecord.self,
    ]
}

public enum VanmoSchemaMigrationPlan: SchemaMigrationPlan {
    public static let schemas: [any VersionedSchema.Type] = [
        VanmoSchemaV1.self,
    ]

    public static let stages: [MigrationStage] = []
}
