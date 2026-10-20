# iOS Instruments Emby Playback Session

**Status:** Completed

## Objective

Record the first physical-device Instruments session for iOS playback: CPU, thermal state, power attribution, and network during Emby Original playback, with the `KSOptions.preferredFrame = false` setting in place, and attempt an allocations pass. Allocations during playback were not captured; see Risks.

## Scope

- Device and build: iPhone 17 Pro, iOS 27.0.1, Debug build at `2ccc166`, plugged in over USB for the whole session.
- Media: Emby item 232355, HEVC (decoded by `hevc_decode_frame`), started from 360p and played as Original. KSPlayer's `videoBitrate` averaged about 16.7–16.8 Mb/s over samples above 1 Mb/s.
- Traces under `tem/instruments/` (not committed):
  - `20261020-emby-10m.trace`: Power Profiler template plus Time Profiler and Network Connections, launched by `xctrace`, 601 s.
  - `20261020-emby-alloc-2m.trace`: Allocations, launched by `xctrace`, 121 s.
  - `20261020-proxy-cpu-2m.trace`: Time Profiler attached to the running app, 121 s.
- Logs under `tem/log/`: `accept-20261020-step3.txt` and `accept-20261020-step3b.txt` (`idevicesyslog` filtered to `[Debug]`).

## Out of Scope

- macOS Instruments.
- Battery drain and a `preferredFrame` on/off comparison. Both need an unplugged run.
- Code changes. Findings are recorded as debt.

## Verification

All playback figures below come from `[Debug][PlaybackPerf]` samples taken every 5 seconds. A steady window starts with the first sample after `firstFrame`, and its length runs from that sample's interval to the last sample. CPU figures are Time Profiler running-sample weight divided by wall time.

### Direct HTTPS path (10-minute trace)

- The first open requested 360p. The AVPlayer HLS open logged `videoQualityResult result=fallbackDirect` about 35 s later, and KSPlayer opened Original through the prefetch proxy (`ready` 4963 ms, `firstFrame` 18963 ms). Samples read 2.6–8.7 MB each before `bufferingStart` at 09:35:25 and 0.3–2.1 MB after it. Frame-rate samples stayed near 24 fps and no `bufferingEnd` was logged before the operator closed the player.
- The reopen logged `videoQualityPlaybackInfo status=transport` with `NSURLErrorDomain` -1004. The proxy open then failed with `KSPlayerErrorDomain` code 2, and KSPlayer fell back to the remote HTTPS URL without the proxy (`ready` 3107 ms, `firstFrame` 11608 ms).
- Steady window, samples 09:36:47–09:41:18 (52 samples, about 276 s): mean 24.0 fps (range 23.81–24.20), 4 dropped frames (all in the first sample), A/V sync 4–46 ms, no buffering. 655.9 MB was read, about 19.0 Mb/s.
- Thermal state was Fair for the whole trace. `ksCreate` logged `preferredFrame=false thermal=1 lowPower=false`.
- Over trace time 333–601 s (09:36:44 to the end of the trace), CPU averaged 0.197 cores. `KSPlayer_MEPlayerItem_read` used 139.6 ms/s. By leaf frame, 44.8% of samples were in `gcm_gf_mul` and 21.4% in `_nettle_aes_encrypt`: the software AES-GCM in FFmpeg's bundled TLS.
- Power Profiler: GPU impact 0, mean CPU impact 1.0 (p95 4), mean display impact 1.8. `SystemPowerLevel` read 0 %/hr throughout because the device was charging. In the steady window Network Connections attributed no connection to Vanmo, and `utun` interfaces were active. The throughput above comes from the app log.

### Prefetch proxy path (log run and attached Time Profiler)

- Log run, 09:49:03–10:00:15: 360p again fell back to Original after about 33 s. KSPlayer through the proxy reached `ready` in 2401 ms and `firstFrame` in 6901 ms. Steady window, samples 09:49:11–10:00:14 (126 samples, about 668 s): mean 24.01 fps, 0 dropped frames, A/V sync 19–36 ms, no buffering, 1484.8 MB read, about 17.8 Mb/s. No `event=thermal` change was logged, and the next `ksCreate` at 10:03:01 still logged `thermal=1`.
- Attached run, 10:02:43: 360p opened on AVPlayer this time (`firstFrame` 7564 ms). The operator switched to Original at 10:03:01, and the proxy KSPlayer open reached `ready` in 3006 ms and `firstFrame` in 8506 ms.
- The Time Profiler trace covered 10:03:04–10:05:05. Excluding the first 10 s, CPU averaged 0.244 cores. Unnamed Vanmo worker threads used 163.4 ms/s, the main thread 59.9 ms/s, and `KSPlayer_MEPlayerItem_read` 8.9 ms/s.
  - Worker threads: `RangeCache.installChunkLocked` accounted for 11.9% of worker samples, about 20 ms/s. Its inclusive time was in `getattrlist`, `rename`, `write`, `rmdir`, `mkdir`, `open`, and `fsync`, which is the per-chunk `Data.write(to:options: .atomic)`. `RemoteFetcher.RangeSessionDelegate.urlSession(_:dataTask:didReceive:)` was 8.2%.
  - Main thread: about 65% of samples were SwiftUI and AttributeGraph updates with no Vanmo frame below `VanmoApp.$main`, and 13.6% were `AVSampleBufferDisplayView.enqueue`. Nothing on screen was being touched. This run cannot tell whether that SwiftUI work is specific to the proxy path.
- These two attributed hotspots total about 60 ms/s of the 244 ms/s. Most worker-thread time is spread across smaller frames.

### Allocations

- The launched Allocations trace ended at 09:47:55, before playback started at 09:48:29, so it covers launch and browsing only. At the end: All Heap Allocations persistent 88.6 MB, heap plus anonymous VM persistent 177.0 MB (875.3 MB total allocated), IOSurface 72.4 MB, mapped files 380.7 MB.
- `xctrace record --template Allocations --attach 27133` failed with `Cannot find process for provided pid`. A Time Profiler attach to the same pid succeeded seconds later.

## Risks

- The direct and proxy CPU figures are not an A/B. They come from different minutes, and the Debug build compiles Vanmo's Swift code without optimization while FFmpeg and nettle ship prebuilt.
- Allocations during playback, battery drain, and the `preferredFrame` comparison are still unmeasured.
- The first session's `bufferingStart` and the -1004 reopen came close together. The log does not separate a network drop from a proxy fault.
- `loadChunkFromDiskNoLRULocked` calls `installChunkLocked(..., fullyWritten: true)`, so a chunk reloaded from disk is written back atomically again. This is from the source; how often it happens during playback was not measured.

## Progress Log

- 2026-10-20: Recorded the 10-minute Power Profiler session on iPhone 17 Pro, then the launched Allocations trace and an 11-minute proxy playback log. Recorded the attached proxy Time Profiler run after the attached Allocations run failed. The operator reported normal playback and no noticeable heat.

## Open Decisions

- None.
