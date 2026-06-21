# Data Migration

## Model Mapping

| iOS SwiftData model | HarmonyOS target | Notes |
| --- | --- | --- |
| `MediaItem` | `MediaItem` domain model + `media_items` table | Frequently queried fields are columns; rich metadata stays in `payload_json`. |
| `SavedConnection` | `SavedConnection` domain model + `saved_connections` table | Passwords and tokens are excluded from the table. |
| `PlaybackRecord` | `PlaybackRecord` domain model + `playback_records` table | Used for history and track selections. |
| Metadata cache records | `MetadataCacheRecord` + `metadata_cache_records` table | Tracks local cached poster, backdrop, logo, cast and episode assets. |

## Storage Policy

- RelationalStore owns user data that needs querying, sorting or joins.
- Preferences owns lightweight settings such as theme, subtitle size and metadata auto-download.
- HUKS-backed encrypted storage owns credentials. The current code exposes a `CredentialStore` interface and an in-memory placeholder until the HUKS implementation is wired.
- Stream URLs must not embed passwords or access tokens. Remote services pass credentials to request layers or PrefetchProxy in memory.

## Import Strategy

The first HarmonyOS release is treated as a new platform install. If iOS data migration becomes a product requirement, add an explicit JSON export from iOS and import into the repository layer instead of reading SwiftData files directly.
