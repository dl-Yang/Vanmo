# Dual-Platform Playback Performance

**Status:** In progress
**Related product spec:** [`../../product-specs/playback-performance.md`](../../product-specs/playback-performance.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Reduce avoidable heat, CPU/network work, startup delay, seek latency, and playback stalls on iOS and macOS while preserving source compatibility, subtitles, progress reporting, iOS Picture in Picture, and macOS player-window cleanup.

## Scope

- Local, HLS, HTTP/WebDAV-prefetched, and SMB playback on both platforms
- AVFoundation and KSPlayer engine diagnostics and lifecycle
- Shared prefetch concurrency, cache, Range handling, and cleanup
- Remote-subtitle discovery on the startup critical path
- Evidence-based evaluation of native AVFoundation routing for MP4/MOV/M4V

## Out of Scope

- Player UI redesign
- A KSPlayer fork or dependency replacement
- Disc-image feature expansion
- Download tuning
- Remote logging or production telemetry

## Baseline Matrix

Record at least three cold starts and one 15-minute steady run for each available category:

| Source | Representative format | iOS | macOS |
| --- | --- | --- | --- |
| Local | H.264 MP4 | Pending | Pending |
| Local or remote | HEVC 10-bit, multichannel audio | Pending | Pending |
| HTTP/WebDAV | Prefetch proxy | Pending | Pending |
| SMB | Direct KSPlayer on iOS; prefetch on macOS | Pending | Pending |
| HLS | AVFoundation | Pending | Pending |

Each run records the engine, hardware-decoding intent or fallback, first-play latency, buffering transitions, seek recovery, KS display FPS/A-V sync/dropped-frame deltas where available, prefetch activity, CPU/memory/energy observations, and cleanup outcome.

## Implementation Steps

1. Add low-frequency, sanitized, Debug-only local diagnostics and capture the initial baseline.
2. Fix seek continuation completion, broad software-decoding retry, stale subtitle work, and remote-subtitle startup blocking.
3. Add shared prefetch tests, move response-body sending outside proxy actor isolation, make pipeline depth source-aware, defend ignored Range responses, and await cleanup.
4. Compare AVFoundation and KSPlayer for native containers. Change routing only if real-source evidence supports it.
5. Run package, repository, serial app-build, and dual-platform runtime verification; record before-and-after evidence.

## Verification

Automated:

```bash
swift test --package-path Packages/VanmoCore
./init.sh
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
```

Runtime:

- iOS physical-device playback with local Console and Instruments evidence
- macOS playback with local Console and Instruments evidence
- two non-adjacent seeks, pause/resume, item switch, close cleanup, iOS PiP, and macOS window close
- no continuation misuse, stale prefetch session, stale subtitle result, or unintended software-decoding fallback

## Risks and Blockers

- A simulator build cannot prove device heat, hardware decoding, or thermal behavior.
- Network throughput and server Range behavior can dominate remote playback, so before-and-after runs must use the same environment.
- Existing native-container routing intentionally prefers KSPlayer because AVPlayer previously failed for some remuxes. It must not change without real-source evidence.
- The working tree contains unrelated untracked files. They must remain untouched unless a file is explicitly part of this plan and its current contents are preserved.

## Progress Log

- 2026-09-21: Plan opened after static review identified broad software-decoding retry, startup subtitle work, prefetch actor serialization, source-insensitive pipeline depth, and seek continuation completion as measurement targets.
- 2026-09-21: The pre-change `./init.sh` run passed the VanmoCore suite, then stopped in the existing architecture guard because the committed `project.pbxproj` differs from non-mutating XcodeGen output in privacy-manifest file typing and widget runpath formatting. This task did not regenerate or edit the project file.
- 2026-09-21: Added sanitized Debug-only AVFoundation, KSPlayer, thermal, and prefetch measurements. Physical-device and real-source before/after evidence remains pending.
- 2026-09-21: Removed broad source-error-to-software-decoding reopen, bounded KS seek completion, moved remote subtitle discovery after play with generation cancellation, and retained the persistent macOS AVPlayer observer across item loads.
- 2026-09-21: Added shared prefetch tests and changed response serving, source-specific pipeline depth, header-first strict HTTP Range validation, bounded body buffering, probe deduplication, lifecycle generations, and awaited cleanup.
- 2026-09-21: Focused playback/prefetch coverage passed, and the final full VanmoCore suite passed 228 tests. Focused iOS Simulator and macOS Debug compiles passed. `./run_device.sh --simulator` and `./run_device.sh --macos` both built and launched the apps; these launch checks do not prove playback performance.
- 2026-09-21: Added Debug A/B controls for AVFoundation native-container routing and HTTP pipeline depths 4/8/16. No real-source device evidence supports changing production routing or the HTTP depth, so MP4/MOV/M4V remain KSPlayer-first and HTTP remains 16; serial SMB/FTP/SFTP byte sources use depth 1.
- 2026-09-21: Post-task review fixes now clean failed KS loads, make FetchLimiter and serial-source read waits cancellation-safe, prevent reconnect after source close, guard subtitle and seek work by media/request generation, and cancel successful seek timeout tasks. Both focused app compiles passed after these fixes.
- 2026-09-21: Failed iOS KS loads now shut the player down before releasing `LibavformatOpenGate`. A later verification pass recorded VanmoCore 228/228, `./scripts/check-harness-docs.sh` 0 failures, iOS Simulator Debug `20260921-190019-82269`, and macOS Debug `20260921-190101-82730`. `./scripts/check-architecture-guards.sh` still fails on the pre-existing committed `project.pbxproj` drift (privacy-manifest file typing and widget runpath formatting). Physical-device and real-source performance matrix evidence remains open.
- 2026-09-21: Post-task review P1: first-play iOS/macOS subtitle restore, play, and session start now honor `mediaGeneration`. Stale prefetch registrations unregister instead of overwriting the current token. External-subtitle load failures no longer mutate a newer item. Recheck found no new P0/P1. P2 residuals remain: seek stop still waits the 3s gate bound, serial-source `unregister` still awaits `close()` without a timeout, and a superseded load can still start before the generation guard. Recheck compiles: iOS Simulator `20260921-191319-84297`, macOS `20260921-191352-84715`.
- 2026-09-22: PlaybackPerf diagnostics now emit through `VanmoLogger.player` / `VanmoLogger.prefetch` instead of `print`. Repository rules require `VanmoLogger` for debug logs. Verification: VanmoCore 228/228, harness docs 0 failures, iOS Simulator `20260922-111004-35603`, macOS `20260922-111041-35854`. Review fixes added local binds plus `privacy: .public` so Console does not redact PlaybackPerf values.
- 2026-09-22: iPhone 13 mini Emby 4K before run (USB console, 14:47–15:11): KSPlayer + prefetch `source=http` depth 16, first response 8478 bytes / 1 fetch, `ready` 5207 ms, `firstFrame` 6270 ms, six buffering intervals of 175–256 s each, `thermal state=2` (serious), close at 242.9 s with `scenePhase=background keepPlayback=true` and no `stop()`. Close now forces teardown (`isClosingPlayer`, disable automatic PiP, `closePlayback()`). A stale `engine.load()` that finishes after close force-stops the rebuilt engine. Prefetch proxy URLs set KS `isSecondOpen=false` on iOS and macOS. Verification: VanmoCore 229/229 (added `testIsProxyURLMatchesLocalhostStreamPath`), iOS Simulator Debug `20260922-152413-53443` then `20260922-153249-55646` after the stale-load force-stop, macOS Debug `20260922-152520-54001`. After-fix Emby 4K device replay remains open.
- 2026-09-22: Same Emby 4K after `isSecondOpen=false` still failed to show a real first frame. USB log: prefetch HEAD size 6.18 GB, first completed response still 8478 bytes, `ready` 7653 ms, logged `firstFrame` at `displayFPS=0.13` (false positive), `bytesDelta=4.5MB`, no further completed proxy responses. Media-server `/Videos/.../stream` URLs now skip prefetch and load Emby/Jellyfin directly. `firstFrame` now requires `displayFPS >= 1`. PrefetchTests 17/17. iOS Simulator Debug `20260922-154443-57617`, macOS Debug `20260922-154533-58124`. Device replay of the same Emby 4K title remains open.
- 2026-09-22: Direct Emby 4K no longer froze, but first picture stayed slow. Log: `skip prefetch`, `isSecondOpen: true`, `ready` 8130 ms with center spinner, then `play()` only after selecting subtitle track 9 of 24; first sample `fps=0.12 avSyncMs=-476` and KS dropped frames. Media-server URLs now also disable `isSecondOpen`, and `play()` runs immediately after `ready` before subtitle/session work.
- 2026-09-22: Operator after-run on the same iPhone 13 mini Emby 4K episode (`3840x2160`, KSPlayer, `skip prefetch`, `isSecondOpen: false`): `ready` 6301 ms, `play()` before subtitle select, `bufferingCount=0` on the opening samples, and the operator reported the first frame no longer hard-stalls and later playback no longer frequently rebuffers. Residual center loading, opening `fps=0.16–0.18`, KS video-clock frame drops, a `memoryWarning`, and heat remain expected on this device/codec. This run did not re-exercise tap-close or Home PiP. It does not close the rest of the dual-platform matrix.

## Open Decisions

- Select the lowest HTTP prefetch pipeline depth that sustains at least 1.2 times the representative media bitrate without adding rebuffer events. Default remains 16 pending runtime evidence.
- Retain KSPlayer-first native-container routing unless AVFoundation demonstrates lower resource use with equivalent real-source compatibility. Debug A/B is available; real-source evidence is pending.
- Capture the physical-device and macOS playback matrix. Compile and launch evidence cannot close thermal, steady-state, seek, or engine-comparison acceptance.
