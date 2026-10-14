# KSPlayer Paused Seek Frame

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Show the new picture when a KSPlayer seek runs while paused, on iOS and macOS. Before the change, a paused seek (Skip Intro, a 10-second rewind, or a progress-bar drop) moved the clock, but the old frame stayed on screen until Play. KSPlayer stops its display link while paused, so nothing drew the frames decoded after the seek.

## Scope

- iOS `KSPlayerEngine` and macOS `MacKSPlayerEngine`: after a seek that does not resume playback, the engine starts `showFirstFrameAfterPausedSeek` in a main-actor task, so the seek returns without waiting for the frame. The task calls `videoOutput.readNextFrame()` every 40 ms. It stops when the displayed pixel buffer changes, or after 125 attempts (about 5 seconds). It keeps waiting through `.buffering` and stops early when a newer seek, a different player, or a state other than paused or buffering takes over.

## Out of Scope

- AVPlayer, which already redraws on a paused seek

## Verification

- Reproduced before the change with `VANMO_DEBUG_PLAYER_SCRIPT=pause,seek:0.8` on the local Jellyfish HEVC clip:
  - iOS Simulator: the screenshots before and after the paused seek were identical.
  - macOS: the window screenshots stayed identical through two paused seeks.
- After the change, with `VANMO_DEBUG_PLAYER_SCRIPT=pause,seek:0.8,seek:0.3,wait:20`:
  - iOS Simulator: both paused seeks logged `event=pausedSeekFrame attempts=4`. Screenshots show a different frame after each seek, and the play icon stays in the paused state.
  - macOS (`Vanmo-macOS.app` launched with the same environment): both seeks logged `attempts=3`. Window screenshots show a new frame after each seek that stays still while paused.
- After the review changes (main-actor task, 5-second budget, buffering tolerated), with `VANMO_DEBUG_PLAYER_SCRIPT=pause,seek:0.8,wait:4,seek:0.3,wait:20`:
  - iOS Simulator: the seeks logged `attempts=4` and `attempts=5`, with `seekEnd elapsedMs=7` and `6`. The final screenshot shows a new frame with the play icon in the paused state.
  - macOS: the seeks logged `attempts=2` and `attempts=3`, with `seekEnd elapsedMs=4` and `0`. This re-run is log evidence only.
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261014-142912-25312`), then `macos` (`20261014-142928-25474`)
- Evidence images are in `tem/paused-seek/` (not committed).

## Risks

- Only the local Jellyfish clip was checked. SMB, Emby original, and long-GOP sources were not walked. A decode slower than 5 seconds still leaves the old frame until Play.
- Not walked on an iPhone. The Simulator, the Mac, and the iPhone share the KSPlayer `MetalPlayView` path, but the iPhone was not checked.

## Progress Log

- 2026-10-14: Reproduced on the iOS Simulator and macOS, fixed both engines, and re-ran the same scripts.
- 2026-10-14: The post-task review found that a remote decode could pass the 1-second budget or briefly enter buffering. The helper now runs as a main-actor task, waits through buffering, and allows 5 seconds. Re-ran builds and both scripts.

## Open Decisions

- None.
