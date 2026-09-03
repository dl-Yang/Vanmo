# Reliability

This document defines how Vanmo proves that the repository and user journeys are healthy, diagnosable, and restartable.

## Standard Paths

### Environment Requirements

- Swift and `xcodebuild` from the selected Xcode toolchain
- Python 3 for `scripts/check-harness-docs.sh`

### Bootstrap

```bash
./init.sh
```

This resolves shared-package dependencies and then runs four baseline stages:

1. the 36-test `VanmoCore` suite
2. the CloudKit/multiplatform static scope check, including XcodeGen drift, target source whitelist, and VanmoCore UI-import guards
3. the Advanced Harness document, repository-local Markdown-link, and live narrative-consistency check
4. the iOS UI interaction CLI static check

The third stage checks required files, repository-local Markdown links, the fast-baseline stage count, active/completed plan-index Status, product-spec/plan Status, and QUALITY current-baseline command paths. It does not build or launch either app. The fourth stage validates target declarations, generated-project presence, Bash syntax/usage, and Swift type-checking; it does not run XCUITest.

After the four stages succeed, `./init.sh --full` adds Debug compile evidence for the iOS Simulator and macOS applications:

```bash
./init.sh --full
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
```

These commands compile only. They do not install, launch, test, or archive. Evidence is retained under `build/app-build-evidence/`.

#### Debug compile caches

`scripts/check-app-build.sh` uses isolated caches on purpose:

- DerivedData: `build/app-build-evidence/DerivedData/ios-simulator` or `.../macos`
- Swift package checkout: `build/app-build-evidence/SourcePackages`

Xcode's Incremental Build uses `~/Library/Developer/Xcode/DerivedData` and the IDE package cache. That path is usually already warm. The script path often starts with Resolve Package Graph and remote package updates, so a first script run can sit on `Updating from …` for a long time before it compiles Vanmo sources.

An Xcode Incremental Build does not replace this script. The isolated caches exist so the recorded `.app` path, command line, and package checkout stay independent of the operator's IDE DerivedData.

Follow these two rules:

1. **Run script platforms one at a time.** `./scripts/check-app-build.sh all` already builds iOS Simulator then macOS in one process. Do not start `ios-simulator` and `macos` as two concurrent processes. The script refuses a second instance that would share `SourcePackages`. After the shared package cache has resolved once, a later serial script run can increment.
2. **Do not share the evidence package cache.** Keep Xcode on its default DerivedData. Do not point Xcode at `build/app-build-evidence/SourcePackages`. Do not start the script while another `check-app-build.sh` or an `xcodebuild` using that same `clonedSourcePackagesDirPath` is still running.

A second serial script run is faster than the first because the isolated package checkout already exists. It is still not the same cache as Xcode.

### Focused Verification

```bash
swift test --package-path Packages/VanmoCore
./scripts/check-cloud-sync-multiplatform-scope.sh
./scripts/check-architecture-guards.sh
./scripts/check-harness-docs.sh
./scripts/check-ios-ui-cli.sh
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
./scripts/ios-ui.sh simulator journey --name tab-navigation
swift test --package-path Packages/VanmoCore --filter DownloadTests
```

Use the smallest relevant check during iteration, then run the required broader check before claiming completion.

### Start or Build

```bash
./run_device.sh
./run_device.sh --simulator
./run_device.sh --macos
```

The default path targets an iOS device. Use `--simulator` for iOS Simulator and `--macos` for the native macOS app. Record the platform, configuration, and whether the command built, installed, launched, or only compiled.

### iOS UI Interaction CLI

Use `scripts/ios-ui.sh` for one bounded iOS action at a time:

```bash
# Simulator: XCUITest backend
./scripts/ios-ui.sh simulator screenshot --output /tmp/vanmo-simulator.png
./scripts/ios-ui.sh simulator tree --output /tmp/vanmo-tree.json
./scripts/ios-ui.sh simulator tap --identifier tab.settings --timeout 5
./scripts/ios-ui.sh simulator assert --identifier screen.library --state exists
./scripts/ios-ui.sh simulator journey --name tab-navigation

# Physical device: the same XCUITest backend
./scripts/ios-ui.sh device screenshot --output /tmp/vanmo.png
./scripts/ios-ui.sh device tree --output /tmp/vanmo-tree.json
./scripts/ios-ui.sh device tap --identifier tab.settings --timeout 5
./scripts/ios-ui.sh device type --label "exact-label-from-tree" --text "example"
./scripts/ios-ui.sh device swipe --direction up
./scripts/ios-ui.sh device assert --identifier screen.library --state exists

# Simulator management only
./scripts/ios-ui.sh simulator launch --device "iPhone 17 Pro"
./scripts/ios-ui.sh simulator terminate --device "iPhone 17 Pro"
```

Device and Simulator screenshot, tree, tap, type, swipe, wait, assert, and journey commands run `VanmoDeviceInteractionTests/testExecuteCommand` through the `Vanmo` scheme. Each command except `journey` launches the app once, so tap and assert cannot preserve navigation across processes. `journey --name tab-navigation` asserts `screen.library`, taps Settings, and asserts `screen.settings` in one process. Replace remaining selector placeholders with identifiers or exact labels from the current tree output. The script sets `TEST_RUNNER_VANMO_UI_*`; Xcode's test runner is expected to expose those values to the test process as `VANMO_UI_*`. Each XCUITest run retains `result.xcresult`, the `xcodebuild` log, attachment-export diagnostics, and exported attachments under `build/ui-cli/runs/`. Simulator XCUITest uses `build/DerivedData-UITests-sim` and does not require a development team.

Physical-device prerequisites are a connected and trusted iOS device, a usable Xcode destination, and valid signing. Select a device with `--device`; provide the development team with `VANMO_DEVELOPMENT_TEAM` or `--team TEAM`. Keep typed values and exported trees/screenshots free of secrets before sharing them.

`simulator launch|terminate` still use `simctl` only to manage the Simulator. They do not capture screenshots or validate UI.

Current evidence as of August 26, 2026:

- XcodeGen generation, target discovery, Bash validation, Swift type-checking, and the full `./scripts/check-ios-ui-cli.sh` static check passed.
- Focused `./scripts/check-app-build.sh ios-simulator` passed after the Settings `.paused` label was added. Evidence: `build/app-build-evidence/runs/20260826-145050-52563/ios-simulator`.
- Simulator XCUITest on iPhone 17 Pro recorded `tree` (`screen.library`, `tab.library`, `tab.settings` present), `assert --identifier screen.library --state exists`, and `journey --name tab-navigation` (`tab.settings` tap, `screen.settings` assert). Journey artifacts: `build/ui-cli/runs/20260826-145830-63647`.
- `TEST_RUNNER_VANMO_UI_*` delivery succeeded on the Simulator. No physical-device XCUITest has run, so device signing remains unverified.

### Debug

- Reproduce on the relevant device or Mac and inspect Xcode Console or Console.app.
- Prefer the project's existing logs. Add narrowly scoped `#if DEBUG` local console logs only at critical entry points, state transitions, asynchronous boundaries, error branches, and return values.
- Use a stable searchable prefix such as `[Debug][Downloads]`.
- Never add remote instrumentation, telemetry, log upload, or an external observation service for device debugging unless explicitly authorized.
- Redact credentials, tokens, cookies, complete authenticated URLs, private file contents, and sensitive path components before sharing logs.

## Debug and Release CloudKit Boundary

`CLOUDKIT_SYNC_ENABLED` and cloud entitlements are enabled for iOS and macOS Debug and Release. Personal-team fallback entitlement files still omit iCloud. Debug can verify local fallback when ModelContainer creation throws, and a signed Debug device or Mac can exercise real CloudKit.

A real CloudKit claim requires a signed physical iOS device or Mac, the Cloud entitlements, an iCloud account, the bound `iCloud.com.vanmo.app` container, a recorded user flow, and non-sensitive evidence. Do not infer it from `./init.sh`, a Simulator Debug launch, or the presence of synchronization code. A signed-device export that ends as `CKErrorDomain` code 2 with empty userInfo is not a schema failure by itself: `NSPersistentCloudKitContainer` strips nested partial errors, and a 2026-09-02 probe recorded `Quota exceeded` (`CKError` 25) for `iCloud.com.vanmo.app`.

## Golden Journeys

1. **Connect, scan, and find media**
   - Connect to a supported readable source, choose the intended scope, complete a scan or server synchronization, and find imported media in the library or search.
2. **Resolve, play, and persist progress**
   - Start a supported item, verify the appropriate player path, stop or close cleanly, and confirm progress restoration without exposing a credential-bearing URL.
3. **Download and recover**
   - Queue media from a real SMB or HTTP source, verify no duplicate tasks, pause and resume individual and global work, restart, continue from existing partial files, and navigate back to the correct detail.
4. **Platform navigation and lifecycle**
   - On iOS, verify tab navigation and full-screen player presentation. On macOS, verify sidebar routing, the independent player window, downloads window, and cleanup on close.
5. **Optional cloud synchronization**
   - On a signed device or Mac with an iCloud account and the bound container, verify only the intended connection, bookmark, favorite, and minimal playback state across devices; confirm credentials and the full media catalog are excluded.

Each journey must record the source type, platform, configuration, steps performed, outcome, and sanitized failure evidence.

## Evidence Boundaries

| Evidence | What it proves | What it does not prove |
| --- | --- | --- |
| `VanmoCore` tests | Shared model and infrastructure behavior covered by those tests | App UI, player rendering, platform lifecycle, or real remote services |
| Static scope check | Declared CloudKit and cross-platform boundaries satisfy the check | Runtime CloudKit synchronization or successful app compilation |
| Architecture structure guards | `project.yml` target sources and dependency direction stay inside the whitelist, committed `pbxproj`/schemes match a non-mutating XcodeGen generate after format normalization, and `VanmoCore` has no unconditional UIKit/AppKit/SwiftUI imports | App compilation, launch, or that a local Xcode `DEVELOPMENT_TEAM` rewrite is absent |
| iOS UI CLI static check | The declared UI-test target, generated-project reference, Bash interface, and test source satisfy the checker | App compilation, signing, test-runner argument delivery, device interaction, or attachment export |
| Simulator `simctl` launch/terminate | The exact recorded simulator management command completed | Screenshots, selectors, XCUITest interaction, or a golden journey |
| Simulator XCUITest command | The exact recorded action or in-process journey completed on that simulator, with retained `xcresult` artifacts | Physical-device signing, Figma fidelity, real-source flows, or product journeys 1–3 |
| Physical-device XCUITest command | The exact recorded action and its retained artifacts completed on that signed device | Other commands, complete UI coverage, Figma fidelity, accessibility quality, or an end-to-end product journey |
| Debug app compile check | The selected application target compiled for the recorded Debug configuration and destination | Installation, launch, XCUITest, physical-device signing, UI behavior, real-source flows, or real CloudKit transport |
| `check-app-build.sh` Debug compile | The selected target compiled in the isolated evidence DerivedData and SourcePackages | An Xcode Incremental Build, launch, or that iOS and macOS can share one DerivedData or run as two parallel processes |
| App build | A target compiled for the recorded configuration and environment | Launch quality or completion of a user journey |
| App launch | Startup reached the recorded state | End-to-end playback, downloads, synchronization, or recovery |
| Manual golden journey | The exact recorded flow worked in that environment | Other source types, platforms, accounts, or configurations |

## Reliability Rules

- A long-running operation must expose visible state, cancellation or pause semantics where supported, and a diagnosable failure path.
- Restart behavior is part of acceptance for persisted queues, security-scoped folders, playback progress, and caches.
- Cleanup must converge on one safe path for player windows, prefetch sessions, temporary files, and media-server reporting.
- Do not mark an unrun platform or environment as passing.
- Convert repeated failures into focused tests, static checks, or documented manual acceptance steps.
