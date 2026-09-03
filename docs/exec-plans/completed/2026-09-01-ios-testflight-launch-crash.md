# iOS TestFlight Launch Crash

**Status:** Completed
**Plan type:** Defect fix
**Related product spec:** none
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Stop TestFlight iOS launches from crashing in `ModelContainerFactory.makeSharedContainer()` so the app can open.

## Scope

- Make CloudStore models CloudKit-compatible (defaults; no unique constraints)
- Launch with `cloudKitDatabase: .none` so `CKContainer` is never initialized
- Delete an unreadable LocalStore or CloudStore once, then retry
- Default iCloud sync preference to off

## Out of Scope

- Versioned SwiftData schema or migration plan
- Real TestFlight CloudKit transport, account, or multi-device sync proof
- Changing entitlements or the `iCloud.com.vanmo.app` container ID
- Re-attaching `.private` at launch (superseded by [`2026-09-02-icloud-debug-device.md`](2026-09-02-icloud-debug-device.md))
- Unrelated working-tree UI or localization work

## Verification

1. `swift test --package-path Packages/VanmoCore` includes `ModelContainerFactoryTests`.
2. `swift test -c release --package-path Packages/VanmoCore --filter ModelContainerFactoryTests`.
3. `./run_device.sh --simulator` Debug build and launch succeeds.
4. Do not claim a new TestFlight build or real iCloud transport from these steps.
5. Do not claim iCloud sync works. Do not pass `.private` until `iCloud.com.vanmo.app` is bound and `CKContainer` init no longer asserts.

## Risks

- Removing `@Attribute(.unique)` from `CloudMediaState.mediaKey` allows duplicate keys; fetch still uses a predicate.
- A second local-store failure can still `fatalError`.
- Testers who already toggled iCloud sync on keep that UserDefaults value; the local-only launch path ignored it.
- Debug launch under this plan did not exercise Cloud entitlements.

## Progress

- **2026-09-01:** TestFlight `1.0.0 (1)` on iPhone 15,3 / iOS 18.6.2 crashed at launch in `ModelContainerFactory.swift:56` (`fatalError` after CloudKit container creation failed). Three reports matched.
- **2026-09-01:** CloudStore models gained CloudKit defaults. `CloudMediaState.mediaKey` unique constraint was removed after a Debug test logged `CloudKit integration does not support unique constraints`.
- **2026-09-01:** TestFlight `1.0.0 (3)` still crashed. Thread 2 asserted in `CKContainerImplementation initWithContainerID:`. Thread 0 was still in `makeContainerThrowing`. Swift `do/catch` never ran.
- **2026-09-01:** `makeSharedContainer()` now always uses `cloudKitDatabase: .none`. An unreadable LocalStore or CloudStore is deleted once and recreated. `CloudSyncPreferences` defaults to off.
- **2026-09-01:** `swift test --package-path Packages/VanmoCore` passed 107 tests, 0 failures, including on-disk launch-path and corrupt-store reset tests.
- **2026-09-01:** `swift test -c release --package-path Packages/VanmoCore --filter ModelContainerFactoryTests` passed 5 tests, 0 failures.
- **2026-09-01:** `./run_device.sh --simulator` Debug `BUILD SUCCEEDED` and launched `com.vanmo.app` PID 22665 on simulator `0811807F-3DD6-4DF5-B5B3-C734ABC76F1F`. This does not prove CloudKit.
- **2026-09-02:** Operator confirmed `iCloud.com.vanmo.app` is created and bound. Local-only launch remains the recorded crash mitigation. Re-attaching `.private` for Debug and Release is [`2026-09-02-icloud-debug-device.md`](2026-09-02-icloud-debug-device.md).

## Remaining

- None for this plan. TestFlight `1.0.0 (4)` confirmation and real iCloud attach live under the Debug-device iCloud plan.

## Open Decisions

- None. The bound-container decision is recorded; CloudKit re-attach is a separate plan.
