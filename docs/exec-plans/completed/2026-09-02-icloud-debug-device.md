# iOS / macOS Real iCloud, Debug Device Testable

**Status:** Completed
**Plan type:** Architecture / sync
**Related product spec:** none
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)
**Supersedes:** [`2026-09-01-ios-testflight-launch-crash.md`](2026-09-01-ios-testflight-launch-crash.md) local-only launch path

## Objective

Attach real CloudKit (`iCloud.com.vanmo.app`) on iOS and macOS Debug and Release so a signed Debug device or Mac can test sync. Keep throw fallback to local CloudStore so a recoverable create failure does not crash launch.

## Scope

- iOS/macOS Debug Cloud entitlements and `CLOUDKIT_SYNC_ENABLED` in `project.yml`; VanmoCore `Package.swift` defines the flag for all configurations
- `makeSharedContainer()` uses `.private` when the user toggle is on; thrown create retries `.none`; unreadable stores are deleted once
- Default `CloudSyncPreferences.isEnabled` to true; Settings reset and coordinator copy match restart-required attach
- Update architecture, reliability, and agent CloudKit evidence boundaries

## Out of Scope

- Changing the container ID
- Hand-editing `project.pbxproj`
- `VersionedSchema` / `SchemaMigrationPlan`
- Writing passwords or OAuth tokens into CloudKit
- Hot-swapping `ModelContainer` when the toggle changes

## Verification

1. `swift test --package-path Packages/VanmoCore`
2. `xcodegen generate` then `./scripts/check-architecture-guards.sh`
3. iOS device Debug: `./run_device.sh` with a paid Team; Settings iCloud on; cold start does not crash; Console has no `CKContainer` assert
4. Save a connection or change a favorite; CloudKit Dashboard (Development) or a second device shows the CloudStore record (no password)
5. macOS Debug: `./run_device.sh --macos` on the same Apple ID sees the iOS-synced connection configuration
6. Simulator Debug is not iCloud evidence

## Risks

- Unbound-container `CKContainer` init still asserts and is not catchable.
- Testers who turned the toggle off keep that UserDefaults value until they turn it back on and restart.
- Debug Cloud entitlements require a paid Team; personal-team fallback files remain without iCloud.
- A second local-store open failure can still `fatalError`.
- The first launch after this build treats every local CloudStore connection not yet in `cloudSync.processedConnectionIDs` as new and runs connect/scan once. That includes connections created on this device before the processed set existed. It does not loop.

## Progress

- **2026-09-02:** Operator confirmed `iCloud.com.vanmo.app` is created and bound. Implementation started from the local-only crash mitigation.
- **2026-09-02:** iOS and macOS Debug/Release use Cloud entitlements and `CLOUDKIT_SYNC_ENABLED`. VanmoCore defines the flag unconditionally. `makeSharedContainer()` attaches `.private` when the toggle is on, retries `.none` if create throws, then deletes unreadable stores once. Sync default is on; Settings toggle is enabled in Debug.
- **2026-09-02:** `swift test --package-path Packages/VanmoCore` passed 109 tests, 0 failures.
- **2026-09-02:** `xcodegen generate` then `./scripts/check-architecture-guards.sh` and `./scripts/check-cloud-sync-multiplatform-scope.sh` passed. `./scripts/check-harness-docs.sh` passed.
- **2026-09-02:** `./run_device.sh --team L775YJ7YS4` on `TARS的iPhone` failed at signing: no Account for Team `L775YJ7YS4` and no iOS development profile for `com.vanmo.app`. This is not launch or CloudKit evidence.
- **2026-09-02:** `./run_device.sh --macos` failed at signing: no Mac App Development profile for `com.vanmo.app.mac`. This is not launch or CloudKit evidence.
- **2026-09-02:** Post-task review found leftover Release-only wording in the architecture diagram, apple-ui SOP, and XcodeGen reference. Those now match §3.3. The CloudKit static check now requires two iOS and two macOS Cloud `CODE_SIGN_ENTITLEMENTS` values and rejects non-cloud config paths.
- **2026-09-02:** Operator queried Development Private Database `CD_SavedConnection` after adding a `recordName` Queryable index: no records. `CD_FolderBookmark` and `CD_CloudMediaState` types are absent. Added `[Debug][CloudKit]` launch/save Console logs to distinguish `.private` attach from local-only save.
- **2026-09-02:** Device Console showed `requestPrivate=true`, `attachedPrivate=true`, and `local save reason=connection-created attachedPrivate=true`. Launch did not fall back to `.none`. Dashboard zone exists, same Apple ID, query still 0 records. CloudStore was first created with `.none` during the crash mitigation; opening that file with `.private` does not make mirroring export.
- **2026-09-02:** Adoption now snapshots the legacy `CloudStore` file and writes a new `CloudStore-ck1` under `.private`. The legacy file is deleted only after restore succeeds and generation `1` is marked. `LocalStore` is untouched. Same Apple ID on the phone and Dashboard is required but not sufficient; an empty `CD_SavedConnection` query still means export never ran.
- **2026-09-02:** Device Console after the adoption build showed `requestPrivate=true`, no reset log, `attachedPrivate=false`, then mirroring setup/import/export. The last export ended with `CKErrorDomain` code 2 (`partialFailure`). `describesNone` used `contains("none")` and treated `.private` as `.none`, so adoption was skipped while CloudKit still attached to the legacy store.
- **2026-09-02:** Later launch showed `needsAdoption=false generation=1 store=CloudStore-ck1`, `attachedPrivate=true`, setup and import `error=none`, then export `CKErrorDomain` code 2 with no nested partial errors. Adoption succeeded; export is the remaining failure.
- **2026-09-02:** Diagnostic build logged `accountStatus=1`, zones `_defaultZone,com.apple.coredata.cloudkit.zone`, `schemaInit failed NSCocoaErrorDomain 134060`, then re-adopted an empty snapshot (`connections=0`) to `CloudStore-ck1` with export `error=none`. Empty export is not proof. `SavedConnection.type` is a SwiftData composite attribute (`NSAttributeType` 2100); CloudKit rejects that type, which matches schema-init 134060 and the earlier one-record export `CKError` 2.
- **2026-09-02:** `SavedConnection.type` is now a `@Transient` wrapper over `typeRawValue` (`String`). Adoption generation is `2` and writes `CloudStore-ck2`, snapshotting `CloudStore-ck1` when generation is already `1`. Snapshot overlays legacy SQLite `ZTYPE` so an existing SMB/WebDAV connection keeps its type.
- **2026-09-02:** Generation-2 device launch showed `store=CloudStore-ck1` → `adopted CloudStore-ck2 generation=2`, `attachedPrivate=true`, `cloudCounts connections=0`, setup/import/export `error=none`. `schemaInit` still failed with `NSCocoaErrorDomain` 134060 and no extra userInfo. The ck1 snapshot was empty because the previous diagnostic launch had already adopted an empty `CloudStore`. Local model load succeeded (no `schemaInit load` line); 134060 is therefore the existing Development schema, not another local composite field.
- **2026-09-02:** After Reset Development Environment, launch showed `generation=2 store=CloudStore-ck2`, `zones=_defaultZone` only, `schemaInit` still 134060, empty export `error=none`, then import `CKErrorDomain` code 2. The Core Data zone was wiped, but `CloudStore-ck2` still holds pre-reset mirroring metadata. Adoption now goes to generation `3` / `CloudStore-ck3`, refuses to create an empty snapshot source, and schemaInit logs the model attribute types plus the full 134060 userInfo.
- **2026-09-02:** Generation-3 cold start logged a CloudKit-compatible `schemaModel` (`SavedConnection.typeRawValue:700`, no composite 2100). `schemaInit` 134060 nested reason is `Failed to initialize CloudKit schema because the requests timed out (a 30s wait failed)`. That call ran synchronously on launch and is not a model defect. Launch no longer calls `initializeCloudKitSchema`; SwiftData mirroring creates the Development schema.
- **2026-09-02:** Device verification on generation 3: `store=CloudStore-ck3`, `attachedPrivate=true`, zones include `com.apple.coredata.cloudkit.zone`, empty setup/import/export `error=none`. After `local save reason=connection-created`, export ended with `CKErrorDomain` code 2 and empty userInfo (`"(null)"`). NSPersistentCloudKitContainer strips nested partial errors; a DEBUG `VanmoCloudKitProbe` save now records the raw CloudKit result after that failure.
- **2026-09-02:** Follow-up cold start (no new connection; previous connection is Emby) showed `cloudCounts connections=1 types=emby`, setup/import `error=none`, then export `CKErrorDomain` code 2. `exportProbe` saved to `_defaultZone` and returned `CKErrorDomain` code 25 / `CKInternalErrorDomain` 2035, `ServerErrorDescription=Quota exceeded`, `ContainerID=iCloud.com.vanmo.app`, `CKRetryAfter=340`. Attach, zone, and local CloudStore are working; CloudKit write is rejected by the Apple ID iCloud quota.
- **2026-09-02:** Operator upgraded this Apple ID's iCloud storage and will re-run the signed-device export check. Do not reset Development. The local Emby `SavedConnection` is already in `CloudStore-ck3`.
- **2026-09-02:** After the iCloud upgrade, a cold start with no new connection showed `store=CloudStore-ck3`, `attachedPrivate=true`, `cloudCounts connections=1 types=emby`, setup/import `error=none`, and two exports `mirroring type=2 ended=true error=none`. No `exportProbe` ran, so there was no `CKError` 2. This is the first recorded successful CloudStore export on a signed device. Dashboard query is still required before verification step 4 can close.
- **2026-09-02:** Operator confirmed CloudKit Dashboard Development Private Database can query `CD_SavedConnection` (no password). Verification step 4 is recorded as passed. macOS Debug on the same Apple ID showed the iOS Emby connection in the sidebar. Verification step 5 is only partial: configuration appeared, browse/scan did not.
- **2026-09-03:** After a CloudKit import, iOS and macOS now diff new `SavedConnection` IDs and call the existing connect/scan path. The sidebar selection uses the `@Query` row when the ViewModel list is stale. If `conn_<id>` or the OAuth token is missing, the edit-connection sheet opens with copy that iCloud does not sync credentials. Saving that password on either platform now runs the same `connectAndScan` path. Passwords stay in the on-device Keychain (option A). Browse and scan still need a signed macOS Debug run.
- **2026-09-03:** Recorded the Keychain password-sync evaluation as a proposed design. Option A remains current. Option B (iCloud Keychain, shared access group) is feasible but not started. Option C (passwords in CloudKit) stays forbidden.
- **2026-09-03:** Operator chose option A: do not sync Keychain. A signed macOS Debug run attached `CloudStore-ck3` (`connections=49` including one `emby`, `bookmarks=1`, `mediaStates=77`), imported and exported with `error=none`, logged `activate type=emby missingCredential=true`, opened the edit sheet, then `local save reason=connection-updated` after the operator entered the password. Home refreshed. Verification step 5 is recorded as passed for configuration plus missing-password connect. No password appeared in Console.

## Remaining

- None for this plan. Conflict merge and a Mac-created connection imported on iOS are not claimed. iCloud Keychain password sync stays rejected under [`../../design-docs/icloud-keychain-password-sync.md`](../../design-docs/icloud-keychain-password-sync.md).

## Open Decisions

- None. Passwords stay on-device Keychain (option A). Option C stays forbidden.
