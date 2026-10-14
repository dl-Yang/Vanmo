# iOS Live Preview Cache

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Stop iOS KSPlayer from grabbing and rescaling a thumbnail on the main actor every two seconds. KSPlayer scrubbing uses the second preview player, which never reads that cache.

## Scope

- Removed `KSPlayerEngine.cacheLivePreviewIfNeeded`, its timer call, the last-bucket marker, and the downscale helper that only that path used.
- The on-demand preview cache used by `previewFrame(at:)` stays. AVPlayer still fills its own cache when it is not using the preview lane.

## Out of Scope

- A measured frame-rate or energy change. The existing evidence is that the captured frames were never displayed.
- macOS, which does not have this timer

## Verification

- Source check: `usesScrubPreviewLane` is true for every KSPlayer engine that has a preview URL, and `requestSeekPreview` returns before `cachedPreview(at:)`. `previewLaneURL` is set for every load. No remaining references to `cacheLivePreviewIfNeeded`.
- `./scripts/check-app-build.sh ios-simulator` (`20261014-173123-46544`). macOS does not compile `KSPlayerEngine`.

## Risks

- None recorded. A KSPlayer source that later scrubs without the preview lane would no longer have frames pre-captured during playback. It can still generate a frame on demand.

## Progress Log

- 2026-10-14: Removed the unused timer capture and recorded the iOS build.

## Open Decisions

- None.
