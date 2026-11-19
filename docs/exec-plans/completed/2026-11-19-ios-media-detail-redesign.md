# iOS Media Detail Redesign and Multi-Backdrop Support

**Status:** Completed
**Plan type:** iOS UI redesign, metadata enrichment, and Figma fidelity verification
**Related product specs:** [`../../product-specs/ios-subtitles-and-appearance.md`](../../product-specs/ios-subtitles-and-appearance.md), [`../../product-specs/media-detail-metadata.md`](../../product-specs/media-detail-metadata.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Redesign iOS `MediaDetailView` to replicate Figma frames `19 · Movie Detail — Above the Fold (393×852)` (`745:1621`) and `20 · Movie Detail — Full Parallax Scroll (393×1164)` (`745:1783`) under `miM6YTQAnerz6SgkkYZMjo` (`656:2`), prioritize server backdrop artwork with automatic multi-backdrop carousel playback (falling back to poster when absent), and enrich `VanmoCore` metadata parsing to drive episode progress/watched states, cast roles, and technical media specifications.

## Scope

- iOS `MediaDetailView` continuous parallax scroll layout, multi-stop obsidian/cream melt scrim, floating top Liquid Glass bar (`CatLGBack`, `CatLGMoreDots`), `Play Now` + `CatPerchingPlayTopRight` + circular favorite/download controls, synopsis card, episode watched/in-progress badges, cast & crew roles, preserved collections, and `MEDIA SPECIFICATIONS`.
- Shared `MediaTitleLogoView` optional `titleColor` support for Day/Night text parity without changing macOS defaults.
- `VanmoCore` extensions (`ServerMediaItem`, `EmbyService`, `PlexService`, `MetadataCacheRecord` schema v2, `MediaCapabilityTags`, `L10nTable`) and unit tests (`MediaCapabilityTagsTests`, `MediaDetailProgressiveLoaderTests`) without altering SwiftData `@Model` schemas.

## Out of Scope

- Changing macOS `MacMediaDetailView` layout.
- Adding Plex remote watched-state writeback (`/:/scrobble` or `/:/unscrobble`).
- Altering SwiftData `@Model` schemas (`VanmoSchemaV1`).

## Required Verification

- `./init.sh` (`VanmoCore` tests, CloudKit/multiplatform scope & architecture guards, Harness documentation checks)
- `./scripts/check-app-build.sh ios-simulator`
- `./scripts/check-app-build.sh macos`
- Agent-operated iOS Simulator walk (`./run_device.sh --simulator` + `simctl` screenshots) across Night and Day modes compared against Figma frames `19` and `20`

## Risks

- The test Emby server returned single-entry `BackdropImageTags` for walked items (`backdrops=1`), leaving multi-image server-sourced carousel switching backed by unit tests and timer-transition inspection rather than a live multi-tag server item.
- Plex watched-state toggling from the More menu remains local-only and can be overwritten on a later server metadata refresh.
- The no-scale image load relies on Kingfisher 8.14 `KFImage` internals (`.fade` animates the image out of a zero-size frame; `loadTransition` inserts it at final geometry). Recheck MediaDetail image loading after any Kingfisher upgrade.

## Decisions

- Resolved Figma-to-feature deltas with the user before coding: moved watched toggle, metadata refresh, and system Share into the top-right `...` More menu; kept Collections below Cast & Crew while removing the bottom director/genre detail card; kept `Play Now` centered with `继续播放` / `立即播放` and icon-only circular download progress/completion/retry states; prioritized backdrops with a 5-second indicator-free cross-fade carousel; and enriched `VanmoCore` metadata for episode progress, cast roles, and `MEDIA SPECIFICATIONS`.
- Upgraded `MetadataCacheIndex.currentSchemaVersion` to `2` with backward-compatible `Codable` decoding on `MetadataCacheRecord` and `CachedEpisodeInfo` so pre-existing v1 caches refresh multi-backdrop URLs, cast roles, and stream specs cleanly.

## Progress

- 2026-11-19: Audited Figma frames `745:1621` and `745:1783`, aligned feature deltas with the user, and added SVG assets `CatPerchingPlayTopRight` and `CatLGMoreDots`.
- 2026-11-19: Extended `VanmoCore` (`ServerMediaItem`, `EmbyService`, `PlexService`, `MetadataCacheRecord` schema v2, `MediaCapabilityTags`, `L10nTable`) and rewrote `MediaDetailView` for continuous parallax scrolling, multi-backdrop carousel, Day/Night adaptation, and local SwiftData episode progress merging.
- 2026-11-19: Walked live Emby series (`新乌托邦`, `洛基`) and movie (`玩具总动员3`) detail screens on the iPhone 17 Pro iOS Simulator (`./run_device.sh --simulator` + `simctl` screenshots) across Night and Day modes, fixed scroll top-bar scrim height/visibility and Day Mode download-icon contrast, and verified `HEVC` / `10-bit` / `Dolby TrueHD 7.1` / `24.2 Mbps` chips on movie detail.
- 2026-11-19: Post-task code review reported three blocking issues (tvShow download button disabled after partial episode completion, `mergeLocalProgress`/`mergeEpisodeBackdrops` dropping new `EpisodeInfo` technical fields, and tvShow `toggleWatched` not refreshing in-memory episode cards) plus minor issues (`.failed` task display, Plex URL helper, Plex episode dynamic-range alignment). All blocking and minor fixes were applied.
- 2026-11-19: Final verification passed: `./init.sh` (364 `VanmoCore` tests with 1 Keychain test skipped in the unsigned process and 0 failures, architecture guards, Harness docs check, Exit 0), `./scripts/check-app-build.sh ios-simulator` (Exit 0), `./scripts/check-app-build.sh macos` (Exit 0), and final `./run_device.sh --simulator` visual check (`新乌托邦`).
- 2026-11-19 follow-up: Removed the root `GeometryReader` (layout now fills the screen via per-layer `ignoresSafeArea`, `containerRelativeFrame` widths, and `onGeometryChange` for the top inset and scroll offset), replaced the 0.45 parallax offset with a pinned hero that stretches on pull-down and shrinks to a `260pt` floor (static `486pt` under Reduce Motion), and moved the hero, episode, cast, and collection `KFImage` loads from `.fade` + outer `.scaledToFill()` to `.loadTransition(.opacity)` + `contentConfigure { $0.scaledToFill() }` to remove load-time scale animations. Evidence: `./scripts/check-app-build.sh ios-simulator` (run `20261119-162606-67309`, pass), `check-harness-docs.sh` and `check-architecture-guards.sh` pass, simulator screenshot of full-screen fill, and operator physical-device acceptance of scroll feel, text legibility, no top-bar jump on entry, and scale-free first loads for the hero and all three thumbnail types.

## Next Step

None for this plan.
