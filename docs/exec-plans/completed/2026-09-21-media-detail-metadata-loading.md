# Media Detail Metadata Progressive Loading

**Status:** Completed
**Plan type:** Cross-platform performance and state-boundary change
**Related product spec:** [`../../product-specs/media-detail-metadata.md`](../../product-specs/media-detail-metadata.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Reduce uncached iOS and macOS detail latency by publishing cached and network metadata as each
component becomes ready, keeping artwork outside the critical path, and preventing metadata updates
from invalidating the root SwiftUI detail view.

## Scope

- Emby, Jellyfin, and Plex detail metadata.
- Shared metadata cache and refresh coordination.
- iOS and macOS detail state ownership and observation boundaries.
- Focused concurrency, cache-ordering, cancellation, and app-build evidence.

## Out of Scope

- A new metadata provider for local or file-based media.
- Visual restyling of either platform's MediaDetail design.
- Changes to playback, download semantics, or media-server APIs.
- A fixed latency promise independent of server and network conditions.

## Required Verification

- `swift test --package-path Packages/VanmoCore`
- `./scripts/check-cloud-sync-multiplatform-scope.sh`
- `./scripts/check-harness-docs.sh`
- `./scripts/check-app-build.sh ios-simulator`
- `./scripts/check-app-build.sh macos`
- Cold-cache iOS and macOS detail walks with sanitized local phase timing and component-refresh
  evidence. The closure decision below supersedes this final requirement.

## Risks

- The two platform stores currently duplicate aggregation and can drift during conversion.
- Existing uncommitted iOS detail artwork and gesture work shares `MediaDetailView.swift`.
- The generated Xcode project had pre-existing normalization drift at task start.
- Real-source acceptance requires an available Emby/Jellyfin or Plex server and credentials.

## Decisions

- Existing platform-specific layouts remain authoritative; only loading state ownership changes.
- Base `MediaItem` content renders immediately.
- Text/index persistence completes before background artwork caching starts.
- Metadata updates use component-scoped observable state; the root detail view does not subscribe
  to aggregate metadata.
- Closure decision: the operator's explicit dual-platform speed approval and real-source phase
  timings were accepted instead of a separately labelled cold-cache walk and an Instruments
  component-redraw recording. The logs prove only the recorded runs. Request overlap and
  component-scoped publication remain supported by delayed-dependency tests and the reviewed state
  ownership structure, not by the timing logs themselves.

## Progress

- 2026-09-21: Task-start `./init.sh` ran 209 passing VanmoCore tests. The baseline stopped in the
  architecture guard because the already-modified committed `project.pbxproj` differed from
  XcodeGen output in PrivacyInfo file typing and Widget runpath formatting. No implementation
  changes existed when this baseline was recorded.
- 2026-09-21: Added a shared progressive loader that emits cache, detail, season, and collection
  events in completion order. Detail records persist before bounded, deduplicated background image
  caching. Episode pages extend the cache without blocking their UI update.
- 2026-09-21: iOS and macOS now seed detail content from `MediaItem` and route summary, cast,
  collection, episode, technical, and metadata-action updates through component-owned observable
  state. The root detail stores do not relay metadata changes.
- 2026-09-21: The final VanmoCore suite passed 212 tests, including three delayed-dependency
  progressive-loader tests. The CloudKit/multiplatform and Harness documentation checks passed.
  Focused Debug compiles passed for iOS Simulator
  (`build/app-build-evidence/runs/20260921-143949-46615/ios-simulator`) and macOS
  (`build/app-build-evidence/runs/20260921-144029-46959/macos`).
- 2026-09-21: Post-task review found cache-refresh episode loss and cancellation/re-entry races.
  The cache now merges existing and pending episode pages, image completion only merges artwork,
  both platform stores cancel stale initial-page work, and cancelled same-item loads can retry.
  Review follow-up reported no blocking findings; 212 tests and both focused app compiles passed
  again after the fixes.
- 2026-09-21: Operator acceptance passed on iOS and macOS: detail loading was reported as fast and
  the change was approved. Two iOS real-source TV detail runs completed collections, seasons, and
  metadata at `2827/2829/2869 ms` and `1725/1726/1745 ms`. Three macOS runs completed those phases
  at `722/703/737 ms`, `966/1244/1268 ms`, and `1097/1089/1111 ms` respectively. Every run logged
  one shared `phase=start type=tvShow metadata=true seasons=true` before the component phases. These
  logs record real-source completion timing only; the automated delayed-dependency tests provide
  the concurrency and publication-order evidence.

## Next Step

None for this plan.
