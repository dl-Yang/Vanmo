# iOS Quality Reload Recovery

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Make sure an iOS quality change or a transcode seek reopen never leaves a frozen picture and clock. A superseded reload in `PlayerViewModel.reloadPlaybackSource` returns without cleanup, because the newer request owns the state. If that newer request then ended before it reached its own reload, nothing cleared `qualityClockFrozenAt` or the hold frame, and nothing resumed the engine. Two examples: `noPlaylist` without a prefetch proxy, and a failed `reopenTranscodedPlayback` guard. A seek reopen also froze the clock before its guard, so a failed guard left the clock frozen even without supersession.

## Scope

- Every reload records what it has already done to the engine in `qualityReloadEngineEffect`: `paused`, or `replaced` once `openEngine` starts. The effect is cleared when the reload completes or rolls back.
- When the latest quality change or seek reopen ends without opening (`applyVideoQualitySelection` or `reopenTranscodedPlayback` returns `false`), `recoverAbandonedQualityReload` clears the hold frame and the frozen clock, then acts on the effect:
  - `paused`: resumes the engine.
  - `replaced`: reopens the current `activePlaybackURL` through the existing restore path, unless the engine already reports `playing`.
  - A hold frame from a successful reload that is still waiting for its first frame is left for the frame callback to clear.
- `resumeDetachedProxyIfNeeded`, the prefetch-session resume on `noPlaylist`, clears the effect once it has reloaded the proxy. It and the recovery check the synchronous `engine.state` instead of the main-queue `playbackState`, so the proxy is not opened twice.
- The restore code from the reload failure path moved into `restorePlayback` so both callers share it. The restore marks its own open as `replaced`, so a request that supersedes it mid-open can still recover. A restore that fails without being superseded clears the effect, so recovery does not retry the same source.

## Out of Scope

- The macOS quality path, which has no frozen-clock hold
- The existing case where a failed reload of the same URL has nothing to restore

## Verification

- Serial `./scripts/check-app-build.sh ios-simulator`, then `macos`
- iPhone device walk on Emby item 253013 (Debug, `./run_device.sh --install-only`, USB `idevicesyslog`):
  - The operator switched quality rapidly (720p → 360p → 720p → 360p → 480p → original → 360p) and repeatedly dragged the progress bar on a transcode.
  - Every chain ended with `videoQualityResult result=opened`, and playback resumed each time.
  - After the review fixes, the operator repeated rapid switches and confirmed playback resumed; no log was captured for that walk.
  - No `videoQualityRecover` event occurred. Every newest request opened, so the new recovery path itself was not exercised on device.
- The logic is iOS-only view-model state, not shared with VanmoCore, so no package test was added.

## Risks

- The recovery path is verified by source inspection and the build only. Exercising it needs a newer request that fails before it reloads, such as a PlaybackInfo failure during a rapid switch.
- Restoring a transcode URL reopens it at that transcode's start (existing `restorePlayback` behavior), not at the current position.

## Progress Log

- 2026-10-14: Implemented and walked on device; recorded build ids `20261014-141225-20093` and `20261014-141240-20233`.

## Open Decisions

- None.
