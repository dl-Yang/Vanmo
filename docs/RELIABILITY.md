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
2. the CloudKit/multiplatform static scope check
3. the Advanced Harness document and repository-local Markdown-link check
4. the iOS UI interaction CLI static check

It does not build or launch either app. The fourth stage validates target declarations, generated-project presence, Bash syntax/usage, and Swift type-checking; it does not run XCUITest.

After the four stages succeed, `./init.sh --full` adds Debug compile evidence for the iOS Simulator and macOS applications:

```bash
./init.sh --full
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
```

These commands compile only. They do not install, launch, test, or archive. Evidence is retained under `build/app-build-evidence/`.

### Focused Verification

```bash
swift test --package-path Packages/VanmoCore
./scripts/check-cloud-sync-multiplatform-scope.sh
./scripts/check-harness-docs.sh
./scripts/check-ios-ui-cli.sh
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
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
# Physical device: XCUITest backend
./scripts/ios-ui.sh device screenshot --output /tmp/vanmo.png
./scripts/ios-ui.sh device tree --output /tmp/vanmo-tree.json
./scripts/ios-ui.sh device tap --identifier "identifier-from-tree" --timeout 5
./scripts/ios-ui.sh device type --label "exact-label-from-tree" --text "example"
./scripts/ios-ui.sh device swipe --direction up
./scripts/ios-ui.sh device assert --identifier "identifier-from-tree" --state exists

# Simulator: simctl backend
./scripts/ios-ui.sh simulator screenshot --device "iPhone 17 Pro" --output /tmp/vanmo-simulator.png
./scripts/ios-ui.sh simulator launch --device "iPhone 17 Pro"
./scripts/ios-ui.sh simulator terminate --device "iPhone 17 Pro"
```

The physical-device backend runs `VanmoDeviceInteractionTests/testExecuteCommand` through the `Vanmo` scheme. It supports screenshot, flat JSON accessibility-tree export, identifier or exact-label tap/type, directional swipe, and exists/absent wait/assert. Replace the selector placeholders above with values from the current tree output. The script sets `TEST_RUNNER_VANMO_UI_*`; Xcode's test runner is expected to expose those values to the test process as `VANMO_UI_*`, but that delivery path has not been verified on a physical device. Each run retains `result.xcresult`, the `xcodebuild` log, attachment-export diagnostics, and exported attachments under `build/ui-cli/runs/`.

Physical-device prerequisites are a connected and trusted iOS device, a usable Xcode destination, and valid signing. Select a device with `--device`; provide the development team with `VANMO_DEVELOPMENT_TEAM` or `--team TEAM`. Keep typed values and exported trees/screenshots free of secrets before sharing them.

The simulator backend intentionally uses only `simctl` screenshot, launch, and terminate. It rejects tree, tap, type, swipe, wait, and assert because `simctl` does not provide those interactions and this path does not run XCUITest.

Current evidence as of August 26, 2026:

- XcodeGen generation, target discovery, Bash validation, Swift type-checking, and the full `./scripts/check-ios-ui-cli.sh` static check passed.
- A simulator `simctl` screenshot completed successfully.
- `./init.sh --full` compiled both apps: macOS Debug passed, and iOS Simulator Debug failed at the pre-existing non-exhaustive `DownloadStatus` switch in `Vanmo/Features/Settings/Views/SettingsView.swift`, which lacks `.paused`.
- Full iOS `build-for-testing` remains blocked by the same source error. The failure is unrelated to the UI-test target.
- No physical-device XCUITest has run. Device signing, `TEST_RUNNER_VANMO_UI_*` argument delivery, command execution, and `xcresult` attachment export therefore remain unverified.

### Debug

- Reproduce on the relevant device or Mac and inspect Xcode Console or Console.app.
- Prefer the project's existing logs. Add narrowly scoped `#if DEBUG` local console logs only at critical entry points, state transitions, asynchronous boundaries, error branches, and return values.
- Use a stable searchable prefix such as `[Debug][Downloads]`.
- Never add remote instrumentation, telemetry, log upload, or an external observation service for device debugging unless explicitly authorized.
- Redact credentials, tokens, cookies, complete authenticated URLs, private file contents, and sensitive path components before sharing logs.

## Debug and Release CloudKit Boundary

`CLOUDKIT_SYNC_ENABLED` and cloud entitlements are Release-only for both applications. Debug builds use non-cloud entitlements and can verify local fallback behavior and static model boundaries, but they cannot prove real CloudKit transport, account, conflict, or multi-device behavior.

A real CloudKit claim requires a Release-capable environment, the intended entitlements and account, a recorded user flow, and non-sensitive evidence. Do not infer it from `./init.sh`, a Debug launch, or the presence of synchronization code.

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
   - In an authorized Release environment, verify only the intended connection, bookmark, favorite, and minimal playback state across devices; confirm credentials and the full media catalog are excluded.

Each journey must record the source type, platform, configuration, steps performed, outcome, and sanitized failure evidence.

## Evidence Boundaries

| Evidence | What it proves | What it does not prove |
| --- | --- | --- |
| `VanmoCore` tests | Shared model and infrastructure behavior covered by those tests | App UI, player rendering, platform lifecycle, or real remote services |
| Static scope check | Declared CloudKit and cross-platform boundaries satisfy the check | Runtime CloudKit synchronization or successful app compilation |
| iOS UI CLI static check | The declared UI-test target, generated-project reference, Bash interface, and test source satisfy the checker | App compilation, signing, test-runner argument delivery, device interaction, or attachment export |
| Simulator `simctl` screenshot/lifecycle | The exact recorded simulator command completed | XCUITest interaction, accessibility selectors, physical-device behavior, or a golden journey |
| Physical-device XCUITest command | The exact recorded action and its retained artifacts completed on that signed device | Other commands, complete UI coverage, Figma fidelity, accessibility quality, or an end-to-end journey |
| Debug app compile check | The selected application target compiled for the recorded Debug configuration and destination | Installation, launch, XCUITest, physical-device signing, UI behavior, real-source flows, or Release CloudKit |
| App build | A target compiled for the recorded configuration and environment | Launch quality or completion of a user journey |
| App launch | Startup reached the recorded state | End-to-end playback, downloads, synchronization, or recovery |
| Manual golden journey | The exact recorded flow worked in that environment | Other source types, platforms, accounts, or configurations |

## Reliability Rules

- A long-running operation must expose visible state, cancellation or pause semantics where supported, and a diagnosable failure path.
- Restart behavior is part of acceptance for persisted queues, security-scoped folders, playback progress, and caches.
- Cleanup must converge on one safe path for player windows, prefetch sessions, temporary files, and media-server reporting.
- Do not mark an unrun platform or environment as passing.
- Convert repeated failures into focused tests, static checks, or documented manual acceptance steps.
