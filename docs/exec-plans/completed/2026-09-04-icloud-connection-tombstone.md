# iCloud Connection Tombstone and Sync Dedup

**Status:** Completed
**Plan type:** Architecture / sync
**Related product spec:** none
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Deleting a connection marks a per-device CloudKit tombstone and clears that device's watch history. Other devices keep the same connection. Saving a connection on this device must not immediately re-prompt for credentials, including a public Emby with an empty password. Overlapping iCloud sync calls must coalesce. A later save of the same `type + host + port + username` reuses the existing CloudStore row.

## Scope

- Add CloudStore `ConnectionTombstone` and filter connection lists with `ConnectionVisibility`
- iOS and macOS delete write a local tombstone; they do not hard-delete `SavedConnection` or set global `deletedAt`
- Local delete removes `MediaItem` and `PlaybackRecord` rows for that connection
- Home continue-watching hides rows whose `sourceConnectionId` is not visible on this device
- `CloudSyncCoordinator.performSync` coalesces in-flight calls
- Local save skips the missing-credential sheet; CloudKit activate no longer auto-presents it
- Password-auth saves always write `conn_<id>` (empty string when no password); `needsLocalCredential` is true only when the Keychain item is missing
- Host-based saves reuse a matching CloudStore `SavedConnection` and lift this device's tombstone; imported duplicates are hidden locally and not scanned

## Out of Scope

- iCloud Keychain or passwords in CloudKit
- Bumping CloudStore generation or adding `VersionedSchema`
- Merging duplicate `MediaItem` rows by server identity
- Merging OAuth drives or local folders

## Verification

1. `swift test --package-path Packages/VanmoCore`
2. `./scripts/check-cloud-sync-multiplatform-scope.sh`
3. `./scripts/check-architecture-guards.sh`
4. `./scripts/check-harness-docs.sh`
5. Serial `./scripts/check-app-build.sh ios-simulator` then `./scripts/check-app-build.sh macos`
6. Manual signed-device walk (same Apple ID, iCloud sync on):
   - Device A saves a public Emby with username only: no immediate credential sheet; macOS sidebar / iOS server list tap does not re-prompt
   - Device B shows the connection without an auto editor; opening it may still ask for a password until B also saves credentials (empty password is enough)
   - Device A deletes: A home history for that connection disappears; B keeps the connection and history
   - Device B adds the same `type + host + port + username`: no second CloudStore row; B reuses the existing id and can connect. Device A does not see a second connection or a second home-history set
   - Device B deletes locally: B home history disappears; A is unchanged

## Risks

- Existing globally `deletedAt` rows stay hidden on every device
- A connection deleted on every device still remains as a CloudStore configuration row plus tombstones
- Re-adding the same host-based server on the deleting device reuses the existing CloudStore row and lifts this device's tombstone; other devices keep that same id
- Local folders and OAuth drives are not identity-merged (bookmarks are device-bound; OAuth hosts often share `oauth`)
- Duplicate `MediaItem` rows already written before identity reuse are not merged
- Local delete does not cancel an in-flight `ScanJobRecord`; a still-running scan can write `MediaItem` rows back. Home continue-watching still hides them when the connection is tombstoned on this device

## Progress

- **2026-09-04:** Implementation started. Per-device tombstone, local media cleanup, sync coalescing, and home visibility filter landed in code.
- **2026-09-04:** `swift test --package-path Packages/VanmoCore` passed 128 tests, 0 failures.
- **2026-09-04:** CloudKit/multiplatform static checks passed until the nested architecture-guard stage. That guard failed on a pre-existing `project.pbxproj` drift (`PrivacyInfo.xcprivacy` `lastKnownFileType`); this task did not edit `project.yml` or the pbxproj.
- **2026-09-04:** `./scripts/check-harness-docs.sh` passed with 0 failures.
- **2026-09-04:** Serial Debug compile passed: `./scripts/check-app-build.sh ios-simulator` (`BUILD SUCCEEDED`; evidence `build/app-build-evidence/runs/20260904-164907-43156`) and `./scripts/check-app-build.sh macos` (`BUILD SUCCEEDED`; evidence `build/app-build-evidence/runs/20260904-165009-44066`).
- **2026-09-04:** Post-task review: no blocking defect.
- **2026-09-07:** Empty-password Keychain write, `needsLocalCredential` missing-item-only, and `ConnectionIdentity` reuse/hide landed in VanmoCore plus both connection VMs.
- **2026-09-07:** `swift test --package-path Packages/VanmoCore` passed 139 tests, 0 failures (identity match, empty-password decision, activate/hide duplicates). Package tests cannot write Data Protection Keychain (`errSecMissingEntitlement` -34018); empty-string vs missing-item is covered by `isMissingLocalPassword` / `resolvedPasswordToStore`.
- **2026-09-07:** `./scripts/check-harness-docs.sh` passed with 0 failures.
- **2026-09-07:** Serial Debug compile passed: `./scripts/check-app-build.sh ios-simulator` (`BUILD SUCCEEDED`; evidence `build/app-build-evidence/runs/20260907-103011-84963`) and `./scripts/check-app-build.sh macos` (`BUILD SUCCEEDED`; evidence `build/app-build-evidence/runs/20260907-103114-85662`).
- **2026-09-07:** Operator signed-device walk (same Apple ID, after a Development reset): Device B local delete cleared B home history and left A unchanged.
- **2026-09-07:** Operator signed-device walk passed the remaining acceptance: Device A saved a public Emby with username only and sidebar/list tap did not re-prompt; Device B added the same `type + host + port + username` without a second connection and could connect on the reused id; Devices A and B did not show a second home-history set. Operator conclusion: pass.

## Open Decisions

- None. Passwords stay on-device Keychain. Cross-device first open still prompts when the peer Keychain item is missing; saving an empty password on that device stops later prompts. Same `type + host + port + username` reuses one CloudStore row.
