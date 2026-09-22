# Playback Performance

**Status:** Active

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

## Measurement and Acceptance

Before-and-after runs use the same media, source, network, device, and build configuration.

- Run at least three cold starts per scenario.
- Run at least one 15-minute steady-state session per platform.
- Exercise two non-adjacent seeks, pause/resume, item switching, and close cleanup.
- iOS physical-device evidence uses local Console plus Energy Log, Time Profiler, Network, and Allocations. macOS uses the corresponding local Instruments templates.
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
