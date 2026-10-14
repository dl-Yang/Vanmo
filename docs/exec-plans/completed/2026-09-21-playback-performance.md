# Dual-Platform Playback Performance

**Status:** Completed
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

Record at least three cold starts and one 15-minute steady run for each available category. Results for every cell are in the Recorded Matrix below.

| Source | Representative format |
| --- | --- |
| Local | H.264 MP4 |
| Local or remote | HEVC 10-bit, multichannel audio |
| HTTP/WebDAV | Prefetch proxy |
| SMB | Direct KSPlayer on iOS; prefetch on macOS |
| HLS | AVFoundation |

Each run records the engine, hardware-decoding intent or fallback, first-play latency, buffering transitions, seek recovery, KS display FPS/A-V sync/dropped-frame deltas where available, prefetch activity, CPU/memory/energy observations, and cleanup outcome.

## Recorded Matrix (2026-10-12)

Environment: Debug builds; macOS 26.0 on a Mac14,2 (Apple M2); iPhone 17 Pro (`iPhone18,1`) on iOS 27.0.1. Media: the public Jellyfish 1920x1080 30 fps 3 Mbps clips (H.264 and HEVC 10-bit), remuxed with a silent stereo AAC track into MKV and MP4 (30-second cold-start clips; a 15-minute loop for steady runs). SMB is this Mac's File Sharing share over the same Wi-Fi network. Values are ranges over three cold starts per cell. Runs launched through the Debug hooks with resume disabled; local run labels are listed in the Progress Log.

`firstFrame` differs by engine: KSPlayer logs it at the first sample with `displayFPS >= 1` (1-second sample granularity), and AVFoundation logs it when the playhead first advances past 0.1 s (0.5-second granularity). The two are not directly comparable. Mac CPU and RSS come from `ps` sampling, not Instruments.

| Source | Format | iOS | macOS |
| --- | --- | --- | --- |
| Local | H.264 MKV/MP4 | KSPlayer: `ready` 57–265 ms, `firstFrame` 1058–1267 ms, 30.0–30.2 fps, 0 dropped, thermal 0–1. AVFoundation (MP4 A/B): `ready` 129–521 ms, `firstFrame` 1132–1518 ms | KSPlayer: `ready` 52–67 ms, `firstFrame` 1053–1068 ms, 29.6–30.2 fps, 0 dropped, CPU 8–14%, RSS 306–341 MB. AVFoundation (MP4 A/B): `ready` 144–158 ms, `firstFrame` 722–778 ms, CPU 5–6%, one startup buffering transition per run |
| Local | HEVC 10-bit MKV/MP4, stereo | KSPlayer: `ready` 54–167 ms, `firstFrame` 1055–1168 ms, 29.9–30.2 fps, at most 1 dropped. AVFoundation (MP4 A/B): `ready` 151–251 ms, `firstFrame` 1168–1256 ms. 15-minute run: `ready` 68 ms, `firstFrame` 1068 ms, 30.0 fps, 1 dropped, 0 buffering, thermal ≤ 1 | KSPlayer: `ready` 47–63 ms, `firstFrame` 1048–1066 ms, 29.9–30.2 fps, 0 dropped, CPU 9–14%. AVFoundation (MP4 A/B): `ready` 113–162 ms, `firstFrame` 727–738 ms, CPU 7–9%. 15-minute run: 30.0 fps, 0 dropped, 0 buffering, average CPU 11%, peak RSS 452 MB, A/V sync 3–34 ms, no thermal change |
| Local or remote | Multichannel audio | Not run: the sample set had no multichannel track | Not run: same reason |
| HTTP/WebDAV | Prefetch proxy | External public Emby server, Original quality, `/emby/Videos/<id>/stream` through `source=http` at depth 16 (item-switch walks): first walk `ready` 9558 ms, `firstFrame` 14059 ms on a 1420 s episode resumed at 1140.5 s; 2026-10-14 walk first episode `ready` 5685 ms, `firstFrame` 9186 ms, second episode `ready` 5426 ms, `firstFrame` 8927 ms. No cold-start series, depth A/B, or WebDAV run: the LAN AList host was unreachable | Same server through `source=http` at depth 16 (item-switch walk): first episode `ready` 8815 ms, `firstFrame` 11316 ms; second episode `ready` 7141 ms, `firstFrame` 9641 ms. No cold-start series, depth A/B, or WebDAV run |
| SMB | iOS direct KSPlayer `smb://` | H.264: `ready` 328–444 ms, `firstFrame` 1328–1444 ms, 25.6–30.0 fps (first 40 s), 0 dropped. HEVC: `ready` 304–640 ms, `firstFrame` 1050–4304 ms (the slow run had one buffering transition), 24.3–30.0 fps, up to 8 dropped. 15-minute H.264 run: closed by script at 899 s with cleanup and `stop()`; cumulative `bufferingCount` stayed 0 through close. The USB syslog relay dropped from minute 1.5 to minute 12.5, so the 47 captured samples (29.4 fps average, 9 dropped, A/V sync ≤ 32 ms) do not cover the middle of the run. Thermal 0 | — |
| SMB | macOS prefetch `source=smb` | — | H.264 and HEVC: `ready` 2217–2254 ms, `firstFrame` 3718–3754 ms, 0 dropped, CPU 9–14%, RSS 356–368 MB. 15-minute H.264 run: 29.8 fps, 0 dropped, 0 buffering, CPU 15%, RSS 379 MB, `[Prefetch] unregistered` after close |
| HLS | AVFoundation | External public Emby server, 720p transcode (`-playback.videoQuality p720`), operator-tapped from Files. Cold starts: `ready` 3777–4884 ms, `firstFrame` 4855–5986 ms, at most one 59 ms startup buffering transition. The first regression and 15-minute attempts, started right after the cold starts, stayed at `playerItem.status=0` after the media playlist loaded; a retry about 15 minutes later passed. 15-minute retry: `ready` 4902 ms, `firstFrame` 5951 ms, three rebuffers of 122 s, 49 s, and 103 s, so the playhead reached only 625 s by the scripted close. This server's transcode throughput did not sustain 720p, so the run is not a standard-network baseline. The AVFoundation path logs no thermal or FPS samples | Not applicable: VanmoMac exposes no quality cap or transcoded HLS path, so media-server titles play the direct stream |

Lifecycle and regression runs (scripted with `VANMO_DEBUG_PLAYER_SCRIPT=seek:0.6,seek:0.2,pause,resume,wait:3,close`):

- macOS local HEVC: seeks 121 ms and 68 ms, pause/resume, close through the player window's `performClose`, `event=cleanup prefetch=false`, empty stderr, no continuation misuse.
- macOS SMB H.264: seeks 79 ms and 75 ms, close, `event=cleanup prefetch=true`, then `[Prefetch] unregistered`; no continuation misuse in stderr.
- iOS local HEVC: seeks 60–103 ms, close, `event=cleanup prefetch=false`, `[KSEngine] stop()`, `playerDisappear closing=true keepPlayback=false`.
- iOS SMB H.264: seeks 135 ms and 60 ms, pause/resume, close, cleanup, and `stop()`.
- iOS HLS (retry run): both seeks landed (playhead 1518 s, then 506 s), pause/resume, close, `event=cleanup engine=av`, `[AVEngine] stop()`, and `closing=true`. The AVFoundation engine does not log seek duration.
- iOS close progress: every iOS close before this fix saved progress twice, and the second save, after the engine stopped, wrote 0 s over the real position. This held for local, SMB, PiP, and soak runs. After the fix, `ios-progressfix-local-hevc10-ks` logged one save at 194.46 s, and the later HLS closes each logged one save.
- iOS Picture in Picture (operator walk on local HEVC): Home started PiP (`willStart`/`didStart`), "return to app" restored the UI and stopped PiP, a second Home plus the PiP close button stopped PiP, and the in-player close button disabled automatic PiP and ran cleanup, `stop()`, and `closing=true`. The operator confirmed each step on screen.
- macOS item switch (operator walk on an Emby series, Original quality): the first episode registered a `source=http` prefetch session; switching episodes logged `[Prefetch] unregistered`, then a new registration for the second episode, which reached `ready` and `firstFrame`. Closing logged `event=cleanup prefetch=true` and `[Prefetch] unregistered`, and stderr had no continuation misuse.
- iOS item switch (operator walk on 2026-10-14, same Emby series opened from the library): `episodesLoaded count=2 seasons=1`, then「选集」from the long-press menu on the cast/quality button group logged `episodeSwitch`, `[Prefetch] unregistered`, and a new `source=http` registration; the second episode reached `ready` and `firstFrame`. Closing logged one progress save at 98.04 s, `event=cleanup prefetch=true`, `[KSEngine] stop()`, `[Prefetch] unregistered`, and `closing=true`, with no continuation misuse. An earlier iOS walk did not switch because the operator could not find the selector; it is reachable only from that long-press menu, and a visible entry is tracked as debt.
- No iOS Instruments (Energy Log, Time Profiler, Network, Allocations) or macOS Instruments session was recorded. Thermal state came from the Debug thermal log, and Mac CPU and RSS from `ps` sampling.

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

- 2026-10-12: Closed the three P2 residuals. KSPlayer seek gates on iOS and macOS now resume immediately on stop or a newer seek instead of waiting out the 3-second bound. A stop also cancels a pending ready wait through a ready epoch. `PrefetchSession.cleanup()` bounds the source close and in-flight reads by `PrefetchConfig.cleanupDrainTimeout` (3 s) and still rejects late cache writes (`testSessionCleanupStopsWaitingForAHungSourceClose`). iOS and macOS first-play paths check `mediaGeneration` before each engine, subtitle, and session step, so a superseded load no longer starts. `project.yml` now sets `DEVELOPMENT_TEAM` to `HYGMY7H2C5`, and `xcodegen generate` regenerated `project.pbxproj`, which also cleared the earlier XcodeGen drift.
- 2026-10-12: Added Debug-only measurement hooks. `VANMO_DEBUG_PLAYER_SCRIPT` (iOS and macOS) runs `seek:<fraction>`, `pause`, `resume`, `wait:<s>`, and `close` steps 4 s apart after the first `playing` state; on macOS, `close` calls the player window's `performClose`. iOS `VANMO_DEBUG_PLAY_FILE` accepts a Documents-relative path, and the iOS Files and macOS acceptance hooks accept `VANMO_DEBUG_OPEN_PATH` and `VANMO_DEBUG_PLAY_NAME`. Both iOS hooks run once per process. iOS and macOS cleanup log `event=cleanup`, and AVFoundation logs `firstFrame`. The iOS `VANMO_NATIVE_VIDEO_ENGINE=av` A/B no longer falls back to KSPlayer. Remaining `print` calls in the touched browser file now use `VanmoLogger`.
- 2026-10-12: Recorded the dual-platform matrix above. Local run labels: macOS `cold-local-*`, `cold-ab-*`, `soak-hevc10-15min-ks`, `reg-local-hevc10-ks`, `smb-cold-*`, `smb-reg-h264-ks`, and `smb-soak-h264-15min-ks`; iOS `ios-cold-*`, `ios-ab-*`, `ios-soak-hevc10-15min-ks`, `ios-reg-local-hevc10-ks`, `ios-pip-local-hevc10-ks`, `ios-smb-cold-*`, `ios-smb-reg-h264-ks`, `ios-smb-soak-h264-15min-ks`, `ios-progressfix-local-hevc10-ks`, `ios-hls-cold-1..3`, `ios-hls-reg`, and `ios-hls-soak-15min`. Runs that were not kept as evidence include the first Mac cold batch (resume was not disabled), runs on video-only sources (they exposed the KSPlayer no-audio busy-wait), iOS SMB runs on degraded Wi-Fi, and iOS AV A/B runs that still routed to KSPlayer. No macOS run logged continuation misuse, which closes the 2026-08-28 macOS seek-misuse debt.
- 2026-10-12: Runtime defects found and fixed during the matrix. iOS close no longer overwrites saved progress with 0 s: `onDisappear` returns once `closePlayback()` has stopped resources. Emby and Jellyfin Files listings now classify Movie, Episode, Video, MusicVideo, and Trailer items as playable video; before this, titles without a file extension in `Name` could not be tapped (`EmbyListingTests`). Two iOS crashes inside libsmbclient under KSPlayer `MEPlayerItem.prepareToPlay` on degraded Wi-Fi were recorded as debt: SIGSEGV in `tevent_trace_point_callback` during `smbc_open`, and SIGABRT `talloc_abort_type_mismatch` in `smbc_read` while Files thumbnails were extracting.
- 2026-10-12: Final verification: `swift test --package-path Packages/VanmoCore` passed 262 tests, including `EmbyListingTests`. Serial `./scripts/check-app-build.sh ios-simulator` passed (`20261012-172614-23409`), then `macos` (`20261012-172921-29890`). `./scripts/check-architecture-guards.sh` first failed on `PrivacyInfo.xcprivacy` `lastKnownFileType` drift in the committed project, which the open Xcode IDE had rewritten. After `xcodegen generate`, it reported 0 failures. The two builds ran before that regeneration; the difference is that one file-type attribute. `./run_device.sh` installed the final iOS Debug build on the iPhone used for the progress-fix and HLS runs.
- 2026-10-13: Post-task review changes. Emby and Jellyfin Files rows no longer extract local thumbnails from the server's original stream on iOS or macOS. The Emby listing log now omits the query string, which carried `api_key`. Debug CloudKit `print` calls in the two browser view models now use `VanmoLogger.storage`. `ExportOptions.plist` now uses team `HYGMY7H2C5`, matching `project.yml`. iOS episode loading and switching now log Debug-only `episodesLoaded`, `episodesSkipped`, and `episodeSwitch` events. The item-switch walks are recorded in the matrix: macOS passed; iOS did not switch because the selector is only in a long-press menu. Verification on the final code (2026-10-14): `swift test --package-path Packages/VanmoCore` passed 262 tests; serial `./scripts/check-app-build.sh ios-simulator` (`20261014-085829-94394`) then `macos` (`20261014-085903-94724`) passed; `./scripts/check-architecture-guards.sh` and `./scripts/check-harness-docs.sh` reported 0 failures.
- 2026-10-14: Second review pass. The iOS KSPlayer `load()` now reads the ready epoch in the same main-actor step as its initial stop. `loadPlayer` skips creating a player when a newer load or stop has advanced the epoch, releases the libavformat gate it acquired, and throws `CancellationError`. Before this, a load suspended at the gate could overwrite a newer player and leave its ready wait hanging. `waitForReady` also cancels any continuation it replaces. The iOS live-stream retry ignores `CancellationError` as the other load call sites do. `ARCHITECTURE.md` now states the 3-second bound on prefetch unregister. Verification: `./scripts/check-app-build.sh ios-simulator` (`20261014-090612-95881`), architecture guards and Harness docs 0 failures. macOS code did not change after `20261014-085903-94724`.
- 2026-10-14: `./run_device.sh --install-only` installed this build on the iPhone 17 Pro, and the operator completed the iOS item-switch walk recorded in the matrix.

## Decisions

- HTTP prefetch pipeline depth stays 16. Emby progressive streams play through `source=http` at depth 16 on both platforms (only media-server HLS playlists bypass prefetch), and the item-switch walks reached the first frame without stalls. No depth 4/8 A/B or WebDAV source was run (the LAN AList host was unreachable), so there is no evidence for a lower depth; `PrefetchConfig` is unchanged, and the A/B is tracked as debt.
- Native-container routing stays KSPlayer-first. On the two synthetic MP4 remuxes, AVFoundation used less Mac CPU (5–9% vs 8–14%) and reached the first frame sooner, but its `firstFrame` signal is not comparable with KSPlayer's, it always logged a startup buffering transition on macOS, and compatibility evidence covers only those two remuxes against the earlier record of AVPlayer remux failures. The comparison is tracked as debt for a broader real-source sample.
- The physical-device and macOS matrix is recorded above. Cells that could not be measured (WebDAV, HTTP depth A/B, multichannel audio, Instruments energy/CPU/allocations, macOS HLS) have their reason in the matrix and are tracked as debt where the gap is actionable.
