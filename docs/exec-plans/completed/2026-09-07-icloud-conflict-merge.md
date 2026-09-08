# iCloud Conflict Merge Evidence

**Status:** Completed
**Plan type:** Architecture / sync
**Related product spec:** none
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Make CloudStore conflict rules explicit, tested, and walkable. After two signed devices edit the same cloud-synced progress, favorite, or folder bookmark while apart, launch/foreground merge keeps one winner and does not rewind the newer write.

## Scope

- Keep `CloudSyncConflictResolver` as the only app-level merge
- Progress: last-write by `lastPlayedAt`; writes within two seconds keep the farther position
- Favorite: last-write by `favoriteUpdatedAt` (stamped on `MediaItem` and `CloudMediaState`)
- Watched: sticky true
- Duplicate `CloudMediaState` rows with the same `mediaKey` collapse before apply
- Duplicate live `FolderBookmark` rows with the same `connectionId + path` keep the later `updatedAt`
- Duplicate host-based `SavedConnection` rows with the same identity collapse to one CloudStore row (delete the extra CloudKit record; do not only tombstone it)
- Record a signed two-device walk on a **file-based** connection (not Emby/Jellyfin/Plex; those items set `isProgressCloudSynced = false`)

## Out of Scope

- `VersionedSchema` / `SchemaMigrationPlan`
- iCloud Keychain or passwords in CloudKit
- Merging media-server progress (server remains authoritative)
- Per-device user-delete tombstones (a real delete still hides only on that device)
- Bumping CloudStore generation

## Verification

1. `swift test --package-path Packages/VanmoCore` including new conflict-resolver cases — passed (158 tests, 0 failures)
2. `./scripts/check-harness-docs.sh` — passed with 0 failures
3. Manual signed-device walk (same Apple ID, iCloud on, file-based scanned item):
   - Progress: Device A and Device B sync the same position — **passed** (operator, 2026-09-08)
   - Favorite: after a favorite change, both devices match — **passed** (operator, 2026-09-08)
   - Bookmark: folder bookmarks sync across devices — **passed** (operator, 2026-09-08)
   - CloudKit Dashboard one `CD_SavedConnection` id per SMB host + user — **passed** (operator, 2026-09-08)
4. Simulator Debug is not CloudKit evidence

## Risks

- Existing CloudKit rows that still store a live `smb://` URL (possibly with a password) remain until both devices run the new merge and CloudKit deletes the loser
- `NSPersistentCloudKitContainer` may already last-write the CloudKit record before our resolver runs; the walk proves the local apply does not rewind
- Two `CloudMediaState` rows for one `mediaKey` are possible if devices inserted independently before this collapse
- In-flight playback on the losing device can write progress again after merge
- A later second save of the same SMB identity on a device that has not yet run collapse can briefly re-export a duplicate until both sides merge again

## Progress

- **2026-09-07:** Plan opened. Resolver already ran on launch/foreground/`performSync`, but favorite ignored timestamps, duplicate cloud-media rows were applied in fetch order, and there were no tests.
- **2026-09-07:** Favorite last-write now uses `MediaItem.favoriteUpdatedAt`. `mergePendingConflicts` collapses duplicate `CloudMediaState` rows before apply. VanmoCore tests cover progress, favorite, watched, connection LWW, bookmark dedupe, and cloud-state collapse.
- **2026-09-07:** `swift test --package-path Packages/VanmoCore` passed 148 tests, 0 failures.
- **2026-09-07:** `./scripts/check-harness-docs.sh` passed with 0 failures. Signed two-device file-based walk is still required before this plan can move to completed.
- **2026-09-07:** Operator walk found two `CD_CloudMediaState` rows for one SMB movie: `vanmo://playback/smb/MacShare/...` vs a live `smb://` URL. Cause: `mediaKey` was `fileURL.absoluteString`. Key is now `conn:<connectionId>|<normalized path>`; launch merge rewrites and collapses the legacy pair.
- **2026-09-07:** Dashboard showed two `CD_SavedConnection` rows for one SMB host. Cause: iOS and Mac each inserted a UUID, then `hideDuplicates` only wrote a local tombstone. Collapse now remaps LocalStore media, bookmarks, and `CloudMediaState` keys onto the earlier `addedAt` (then UUID) winner and deletes the extra CloudStore row. Port `0` matches the type default; SMB `guest` matches an empty username.
- **2026-09-07:** `swift test --package-path Packages/VanmoCore` passed 158 tests, 0 failures. `./scripts/check-harness-docs.sh` passed with 0 failures. Winner user-delete tombstones stay on this device; collapse does not lift them.
- **2026-09-07:** iOS Home → detail favorite on a `vanmo://` file item failed with `未连接到服务器` because `EmbyFavoriteUpdater` ran without a media-server snapshot. File-based items now skip Emby and write SwiftData plus CloudKit. Device logs: before `fallback store missing` / after `skippedEmby=true wroteCloud=true`.
- **2026-09-08:** Operator signed two-device walk (same Apple ID, iCloud on, file-based item): progress syncs between A and B; favorite changes sync both ways; bookmarks sync. Operator conclusion: pass. Plan archived.
- **2026-09-08:** Operator queried CloudKit Dashboard: one SMB connection shows one `CD_SavedConnection` record. Identity collapse is recorded as passed.

## Open Decisions

- None. Media-server items stay server-authoritative. File-based items use the rules above. Same SMB identity keeps one CloudStore / Dashboard `CD_SavedConnection` row.
