# iOS HLS Scrub Preview

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Restore the scrub preview after switching an Emby title to a transcoded quality. Found during the Tier 2.4 device walk: Original showed previews, but 720p showed none.

## Root Cause

- Lower Emby/Jellyfin qualities play `master.m3u8` on `AVPlayerEngine`. `usesScrubPreviewLane` only allowed `KSPlayerEngine`, so scrubbing fell back to `AVAssetImageGenerator`, which returns no frames for HLS. The device log showed no `previewLane` event during 720p drags.
- On Original, the preview lane opens playback's shared prefetch token. The switch to HLS unregisters that token, but the lane kept its open player on the dead localhost URL.

## Scope

- `usesScrubPreviewLane` also accepts AVPlayer when the active URL is a transcode playlist (Emby, Jellyfin, or Plex) and the original source is not itself a playlist. The lane reads the original file, not the HLS rendition.
- `ScrubPreviewLane` remembers the shared proxy URL it opened. When a later request carries a different shared proxy URL (none, or a new token), it drops that player so the next capture resolves the source again. A lane on its own prefetch session drops it, and unregisters its token, once playback has a shared proxy again, such as after switching back to Original. A player reset during its ready wait cannot mark itself ready.

## Out of Scope

- Playing HLS transcode on KSPlayer. See the tech-debt row.

## Verification

- Serial `./scripts/check-app-build.sh ios-simulator`, then `macos`
- iPhone device walks on Emby item 253013 (Debug, USB `idevicesyslog`):
  - The shared-proxy reset alone: dragging on 720p still showed no preview and logged no `previewLane` event. After switching back to Original, the log showed `previewLaneReset reason=sharedProxyChanged`, then `previewLaneOpen mode=shared` on the new token, then `previewLaneShow` frames.
  - With both changes: drags on Original showed previews (`previewLaneOpen mode=shared`). After switching to 720p on AVPlayer (`videoQualityEngine engine=AVPlayer`), the log showed `previewLaneReset reason=sharedProxyChanged`, then `previewLaneOpen mode=proxy`; 20 `previewLaneShow` events in total. The operator confirmed previews on Original, 720p, and back on Original.
  - After the review fixes, the operator repeated Original, 720p, then Original drags plus rapid switches and confirmed previews and resumed playback. No log was captured for this walk.

## Risks

- While AVPlayer plays a transcode, the lane registers its own prefetch session for the original file. It is released when playback has a shared proxy again or the lane closes.
- The changes made after review (narrowed lane condition, own-session release) were walked on device with operator confirmation only: the USB log capture for that walk produced no file.

## Progress Log

- 2026-10-14: Diagnosed with device logs, fixed, and re-walked on device; recorded build ids `20261014-141225-20093` and `20261014-141240-20233`.

## Open Decisions

- None.
