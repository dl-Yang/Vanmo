# iOS WebDAV Prefetch Depth A/B

**Status:** Completed

## Objective

Compare HTTP prefetch pipeline depths 4, 8, and 16 on one WebDAV file on iOS, as the HTTP prefetch depth debt asks, and decide whether the default of 16 should change.

## Scope

- Device and build: iPhone 17 Pro, iOS 27.0.1, Debug build at `2ccc166`.
- Source: a WebDAV connection to a LAN server over plain HTTP on Wi-Fi. Playback went through the localhost prefetch proxy (`source=http`).
- Media: one MP4, 360 s long, 60 fps, decoded by KSPlayer with hardware decoding. KSPlayer's `videoBitrate` samples had a median of 23.8 Mb/s (range up to 31.2 Mb/s).
- What the depth controls: `httpPipelineDepth` sets how many chunks the response body that serves KSPlayer keeps in flight. The background forward fill (`fillAhead`) is capped at 2 concurrent chunks at every depth, so this A/B did not vary forward-fill concurrency.
- Method: the app was relaunched for each round with `VANMO_PREFETCH_PIPELINE_DEPTH` and `-playback.resumePlayback '<false/>'`, so each round started from 0 with an empty session cache. Order: 16, 8, 4, then 16 again to detect drift. In each round the operator played from the start for 93–176 s, dragged to 63–65%, played on, and closed the player.
- Logs under `tem/log/` (not committed): `accept-20261021-step6-d16a.txt`, `-d8.txt`, `-d4.txt`, and `-d16b.txt`, captured with `devicectl ... --console`. An earlier depth-16 capture ended when the USB cable disconnected before any playback and is not used.

## Out of Scope

- macOS, Emby progressive streams, and other HTTP servers.
- Changing `PrefetchConfig`.

## Verification

Every round logged `depth=` matching its launch value in `prefetchResponseSummary`.

| Round | Depth | `ready` | `firstFrame` | `seekEnd` | Buffering | Buffering share of the open | KSPlayer read rate, median (range) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 16 | 5.5 s | 17.5 s | 386 ms | 2 ended (11.9 s, 12.2 s), a third started 5 s before close | 11% over 224 s | 21.4 Mb/s (0.0–24.7) |
| 2 | 8 | 2.0 s | 14.5 s | 479 ms | 2 (11.9 s, 20.3 s) | 18% over 182 s | 15.5 Mb/s (6.5–23.9) |
| 3 | 4 | 1.6 s | 24.1 s | 68 ms | 5 (23.3–38.4 s) | 50% over 302 s | 9.2 Mb/s (3.8–12.6) |
| 4 | 16 | 4.6 s | 22.1 s | 94 ms | 5 (18.7–22.8 s) | 40% over 258 s | 13.8 Mb/s (0.4–23.1) |

- The read rate is the median of KSPlayer's 5-second `bytesDelta` samples with `displayFPS >= 1`. While playback keeps up, reads follow consumption, so a value near the bitrate is a lower bound on what the source could supply.
- The buffering share is total ended buffering time divided by the time from `ready` to close.
- `firstFrame` is the first KSPlayer sample with `displayFPS >= 1`. The early samples in each round showed 0.1–0.6 fps, so the 14–24 s values reflect a slow start rather than that long a black screen. `seekEnd` is the time for KSPlayer's seek call to return.
- The forward-fill target is 180 s, capped at 256 MiB (about 90 s at this bitrate). In every round the cached span stayed about 0.020 of the file (about 7 s) ahead of the playhead (median of `aheadFill` `spanEnd - fraction`).
- The operator reported slight stutters at depth 16 and 8, and several stutters at depth 4 and in the second depth-16 round. Playback otherwise worked in every round.

## Decision

The HTTP prefetch depth stays 16. Depth 4 was worse in its single round: its read rate never exceeded 12.6 Mb/s over 54 samples, below the file's bitrate, while every depth-8 and depth-16 round peaked at 23.1–24.7 Mb/s. It also read slower than the later second depth-16 round, so a steady decline over the session would not explain it. Depths 8 and 16 cannot be separated here. At the same depth, the two depth-16 rounds 23 minutes apart read at 21.4 and 13.8 Mb/s, which brackets depth 8's 15.5 Mb/s. Conditions changed during the session, whether in the link, the server, or the device.

## Risks

- This is one LAN WebDAV server, one file, and one round per depth. The first three rounds ran in depth order 16, 8, 4, so depth and time are confounded. The depth-8 result is not evidence for or against lowering the default.
- At every depth the file rebuffered, and the cached span stayed about 7 s ahead of the playhead. Whether the server, Wi-Fi, the 256 KiB per-chunk request pattern, or the forward fill's 2-chunk concurrency cap limits throughput was not measured.
- `ready` and `firstFrame` are single samples per depth.

## Progress Log

- 2026-10-21: On iPhone 17 Pro, a 360 s MP4 at about 24 Mb/s on a LAN WebDAV server played at depths 16, 8, 4, and 16. Depth 4 read at a median of 9.2 Mb/s and never above 12.6 Mb/s, and it buffered for 50% of the open. The two depth-16 rounds read at 21.4 and 13.8 Mb/s, and depth 8 at 15.5 Mb/s. HTTP depth stays 16.

## Open Decisions

- None. A repeat with interleaved rounds on a stable link would be needed before considering depth 8.
