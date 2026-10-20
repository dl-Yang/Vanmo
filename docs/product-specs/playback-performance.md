# Playback Performance

**Status:** Completed

**Current acceptance status:** Completed. Some gaps are recorded below. The 2026-10-12 matrix in [`../exec-plans/completed/2026-09-21-playback-performance.md`](../exec-plans/completed/2026-09-21-playback-performance.md) covers, on iPhone 17 Pro and an M2 Mac, local H.264 and HEVC 10-bit, iOS direct SMB, macOS SMB prefetch, and iOS Emby HLS: cold starts, 15-minute runs, scripted seeks, pause/resume, close cleanup, iOS PiP, and macOS window close. KSPlayer's 15-minute local and SMB runs averaged 29.4–30.0 fps on 30 fps sources with no rebuffer, and their thermal state stayed at 1 or below. The HLS 15-minute run rebuffered because the external server's transcode throughput was too low; it is not a standard-network baseline. Emby progressive streams played through HTTP prefetch (`source=http`, depth 16) on both platforms, and Emby item switches on both platforms unregistered the old prefetch session, registered the next one, and cleaned up on close. The iOS walk used the long-press menu; a visible episode button was added afterward (see `ios-player-controls.md`). Not measured: WebDAV, HTTP depth A/B, multichannel audio, Instruments energy, CPU, network, and allocations, and macOS HLS, which is not applicable. These gaps are listed in the tech-debt tracker.

## Objective

Vanmo should play supported local and remote video on iOS and macOS without avoidable decoder fallback, sustained resource contention, or repeated buffering. Performance decisions must be based on comparable local measurements rather than format-name assumptions.

## Supported Performance Matrix

The acceptance matrix covers the same representative media on both platforms where the source is available:

- local H.264 MP4
- local or remote HEVC 10-bit video with multichannel audio
- HTTP or WebDAV playback through the localhost prefetch proxy
- SMB playback
- HLS playback through AVFoundation

Each record identifies only the source category, codec, resolution, nominal frame rate, device, operating-system version, and build configuration. It must not include credentials, complete authenticated URLs, or private media titles.

## Observable Requirements

1. Playback starts with the expected engine and does not silently switch to full software decoding because of a network, authentication, cancellation, or container-open error.
2. Steady playback does not create avoidable thumbnail, probe, prefetch, or stale subtitle work after the active media changes.
3. A new seek request is not blocked behind an abandoned prefetch response, and a seek cannot leak its async continuation.
4. Remote subtitle discovery does not block the first playable frame. Results from an old media generation cannot overwrite the current item.
5. Closing or switching playback releases the active engine, prefetch session, temporary session cache, subtitle work, and media-server reporting path.
6. iOS Picture in Picture and macOS independent-window playback preserve their existing lifecycle behavior.
7. Closing playback saves the current position once. Stopping the engine must not overwrite it with 0.

## Measurement and Acceptance

Before-and-after runs use the same media, source, network, device, and build configuration.

- Run at least three cold starts per scenario.
- Run at least one 15-minute steady-state session per platform.
- Exercise two non-adjacent seeks, pause/resume, item switching, and close cleanup.
- iOS physical-device evidence uses local Console plus Energy Log (Power Profiler on Xcode 26), Time Profiler, Network, and Allocations. macOS uses the corresponding local Instruments templates.
- KSPlayer steady display FPS should remain at least 95% of nominal FPS when the source throughput is sufficient.
- Steady A/V synchronization difference should remain below 50 milliseconds in absolute value.
- A standard-network run must not add rebuffer events relative to its baseline.
- Seek recovery, first-play latency, CPU, memory, and energy must not regress. A tuning change is retained only when it improves a measured bottleneck or removes a confirmed correctness defect.
- iOS must not enter `serious` or `critical` thermal state during the recorded standard acceptance run.

These thresholds apply only to the recorded environment. They are not guarantees for every server, network, codec, or device.

## Diagnostics Boundary

Performance diagnostics are local, Debug-only, and emitted through `VanmoLogger`. They may record engine kind, source category, hardware-decoding intent, timing, buffering counts, frame-rate and A/V-sync aggregates, dropped-frame deltas, byte deltas, cache behavior, and thermal-state changes.

Diagnostics must not upload data or record credentials, tokens, cookies, complete authenticated URLs, private paths, or media titles.

## Out of Scope

- Player UI redesign
- A general KSPlayer fork or replacement
- New disc-image support
- Download-system tuning
- Production telemetry, MetricKit upload, or third-party observability
