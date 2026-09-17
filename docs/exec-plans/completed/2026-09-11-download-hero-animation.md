# Download Hero Animation and Live Activity

**Status:** Completed
**Plan type:** Feature / downloads UI
**Related product spec:** [`../../product-specs/downloads.md`](../../product-specs/downloads.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

After a media-detail download enqueue, show a Dia-style capsule that flies to the iOS Dynamic Island (or a status-bar fallback bar) and to the VanmoMac sidebar download icon, then keep title plus progress visible with movie/single and multi-episode selection rules.

## Scope

- Detail-page enqueue on iOS and macOS
- Shared `DownloadActivityPresentation` selection
- iOS Live Activity widget for Dynamic Island devices
- iOS fallback progress bar when Live Activity or Dynamic Island is unavailable
- macOS fly-to-icon swallow
- Reduce Motion skips the flight

## Out of Scope

- Files-browser download hero
- Changing `DownloadManager` queue semantics
- Figma frames
- Expanding physical-device screenshot and recording coverage beyond the recorded walks
- Raising the entire QUALITY_SCORE snapshot to A

## Verification

1. `swift test --package-path Packages/VanmoCore` including `DownloadActivityPresentationTests`
2. `./scripts/check-architecture-guards.sh`
3. Serial `./scripts/check-app-build.sh ios-simulator` then `macos`
4. Manual: iPhone 17 Pro simulator island or fallback, iPhone SE fallback bar, `./run_device.sh --macos` icon swallow, no crash

Do not mark Downloads domain A until those commands and the recorded manual walks exist.

## Risks

- Simulator Live Activities can stay disabled even on Dynamic Island hardware; the fallback bar must still swallow the capsule
- Isolated app-build caches are large; disk pressure can fail a first `check-app-build.sh` run
- Broader download journeys still depend on screenshots, recordings, or agent-operated Simulator walks

## Progress

- 2026-09-11: Implemented selector, Live Activity widget, iOS/macOS hero overlays, and XcodeGen widget target.
- 2026-09-11: `DownloadActivityPresentationTests` passed 5/5. `./scripts/check-architecture-guards.sh` passed after adding `VanmoDownloadWidget` to the allowlist and temp mirror. `./scripts/check-harness-docs.sh` passed.
- 2026-09-11: Worktree `xcodebuild` Debug compile succeeded for `Vanmo` (iPhone 17 Pro simulator) and `Vanmo-macOS`. Isolated `./scripts/check-app-build.sh` was not run; the machine had only a few GB free and that script's SourcePackages cache would duplicate several GB.
- 2026-09-11: Signed iOS Simulator install on iPhone 17 Pro (`0811807F-3DD6-4DF5-B5B3-C734ABC76F1F`) launched `com.vanmo.app` and stayed on the empty Home screen with no crash. The library had no media, so the hero flight, island, and fallback bar were not exercised.
- 2026-09-13: An ad-hoc Vanmo-macOS launch crashed in `CKContainer.init` from `ModelContainerFactory.makeSharedContainer()` (`EXC_BREAKPOINT` / missing CloudKit entitlement on a `CODE_SIGNING_ALLOWED=NO` binary). That is not the hero overlay. A signed macOS Debug build failed with no profiles for `com.vanmo.app.mac`.
- 2026-09-13: Live Activity start failures are now remembered so progress ticks do not retry `Activity.request` on every `tasks` update.
- 2026-09-13: Review follow-up: fallback bar is a top overlay so it no longer swallows full-screen taps; Live Activity updates are keyed by title/percent; request failure falls back to the bar; existing activities are adopted on launch; flight waits briefly for a destination frame; series completion publishes a short completed state before the next episode.

- 2026-09-13: `swift test --package-path Packages/VanmoCore` passed 207 tests, including `DownloadActivityPresentationTests` 5/5. Serial `./scripts/check-app-build.sh` passed iOS Simulator (`20260913-004936-1528`, `aggregate=pass`) then macOS (`20260913-010035-12530`, `aggregate=pass`).
- 2026-09-13: LAN `192.168.1.77` was unreachable, so the walks used Debug-only `VANMO_DEBUG_HERO_WALK` / `VANMO_DEBUG_HERO_AUTO` local fixtures on the same media-detail `beginDownload` / `enqueueSelectedEpisodes` path. iPhone 17 Pro recorded the movie capsule in flight and a series Dynamic Island title. iPhone SE recorded the status-bar fallback swallow and a series episode title on the bar. No crash.
- 2026-09-14: A signed Vanmo-macOS launch (`Apple Development: Juyu Li`, team `HYGMY7H2C5`, existing Mac Team profile for `com.vanmo.app.mac`) recorded movie and series capsules flying from the detail download button toward the sidebar `arrow.down.circle`. Isolated `check-app-build.sh macos` remains compile-only (`CODE_SIGNING_ALLOWED=NO`). `./run_device.sh --macos` was not used because a cold `build/DerivedData` copy would have duplicated several GB.
- 2026-09-14: Downloads in `QUALITY_SCORE.md` moved to A.

## Next step

None. Later iOS UI follow-up uses screenshots, recordings, or agent-operated Simulator walks.
