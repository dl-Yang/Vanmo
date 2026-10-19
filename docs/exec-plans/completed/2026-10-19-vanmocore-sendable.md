# VanmoCore Sendable Warnings

**Status:** Completed

## Objective

Clear the Swift 6 `Sendable` warnings emitted by `VanmoCore`, so a later language-mode upgrade does not fail on those types.

## Scope

- `DynamicRange`, `AudioTrackInfo`, and `SubtitleTrackInfo` now conform to `Sendable`.
- Detail loading captures its loader functions with an explicit `self.` assignment.
- Probe, thumbnail, and remote-scan writes go through `@MainActor` methods instead of `MainActor.run` closures that captured `MediaItem` or `ModelContext`.
- Local directory enumeration runs in a synchronous function, outside the async scan method.
- Scan progress updates the coordinator's `activeJob` on the main actor only when its id matches the job that produced the callback.

## Out of Scope

- iOS `BrowserViewModel`, `HlsSegmentFixServer`, `PlayerEngine`, and `SettingsViewModel`
- macOS `MacConnectionsViewModel`
- The existing access-control warnings on private `JSONDecoder` helpers and `requiresLazyPlaybackURL`
- Enabling Swift 6 language mode

## Verification

- `swift test --package-path Packages/VanmoCore`: 279 tests, 0 failures
- iOS Simulator Debug `20261019-123010-29345` and macOS Debug `20261019-123019-29422` recompiled `ProbeTypes.swift`: pass, no `VanmoCore` Swift 6 warning
- iOS Simulator Debug `20261019-123521-30759` and macOS Debug `20261019-123532-30854` recompiled `ScanCoordinator.swift` after the progress callback was limited to the matching job id: pass, no `VanmoCore` Swift 6 warning

## Risks

- The app-target warnings listed above remain and will still fail a Swift 6 language-mode build.
- Model objects are still passed into `@MainActor` methods from the scanner actor. The compiler accepts that hop; this change does not move scanning onto a `ModelActor`.

## Progress Log

- 2026-10-19: Cleared the `VanmoCore` Swift 6 `Sendable` warnings and rebuilt both apps.

## Open Decisions

- None.
