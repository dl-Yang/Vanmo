# iOS Native-Container A/B on Real MP4/MOV Files

**Status:** Completed

## Objective

Collect the real-source MP4/MOV sample that the native-container routing debt asks for: play the same files on iOS through KSPlayer (the default) and through AVFoundation (`VANMO_NATIVE_VIDEO_ENGINE=av`), and record compatibility, open, and seek behavior.

## Scope

- Device and build: iPhone 17 Pro, iOS 27.0.1, Debug build at `2ccc166`.
- Media: eight files copied from a Mac File Sharing share, downloaded through Vanmo, and played locally. AVFoundation cannot open `smb://`, so both rounds used the same local files.

| Sample | Container | Video | Audio | Length |
| --- | --- | --- | --- | --- |
| A1 | MP4 | H.264 High 1080p29.97, 3 Mb/s | AAC | 131.8 s |
| A2 | MP4 | H.264 720p30, 7.7 Mb/s | AAC | 77.1 s |
| A3 | MP4 | iPhone HEVC Main10 4K60 HLG, 84 Mb/s | AAC | 4.2 s |
| A4 | MP4 | iPhone screen recording, HEVC, audio track first, average 48.7 fps | AAC | 17.1 s |
| A5 | MOV | iPhone screen recording, HEVC, variable frame rate, timescale 600, average 46.9 fps | AAC | 6.8 s |
| A6 | MOV | Screen recording, H.264 Main 1528x1310, 60 fps nominal, average 48.5 fps | none | 8.6 s |
| A7 | MP4 | H.264 4K portrait, 120 fps nominal, average 59.8 fps | none | 4.5 s |
| A8 | MP4 | H.264 540x960 29 fps | AAC | 25.7 s |

- A1 and A2 were muxed by FFmpeg (`Lavf`), and A8 by a third-party encoder (`bytevehwavc`). A3 also carries five timed-metadata data tracks.
- Round A: default routing (KSPlayer). Round B: the app was launched with `VANMO_NATIVE_VIDEO_ENGINE=av`. In each round the operator played all eight files in order. Round A logged seeks on A1 and A2 only, and round B on every file except A3.
- Logs under `tem/log/` (not committed): `accept-20261021-step5a.txt` (round A) and `accept-20261021-step5c-raw.txt` (round B).

## Out of Scope

- macOS, and remote HTTP or SMB sources.
- CPU, energy, and memory comparison.
- Changing production routing.

## Verification

### Engine selection

- Round A logged `engine=ks` for all nine opens (A4 was opened twice).
- Round B logged `[EngineFactory] Debug A/B override: AVPlayerEngine` and `engine=av` for all eight opens.

### Results

| Measure | Round A (KSPlayer) | Round B (AVFoundation) |
| --- | --- | --- |
| Opens that played | 9 of 9 | 8 of 8 |
| `ready` | 18–173 ms | 27–90 ms |
| `firstFrame` | 1.02–1.17 s | 0.60–1.24 s |
| Seek recovery (`seekEnd`) | 41–74 ms over 6 seeks on 2 files | 11–276 ms over 16 seeks on 7 files |
| Buffering events | 0 | 0 |
| Engine errors | 0 | 0; no `playerItem` reached `failed` |

- Per file, AVFoundation reached `ready` sooner on A1, A5, A6, and A7 and later on A2, A3, A4, and A8, so neither engine was consistently faster.
- The seek ranges cover different file sets and are not a direct comparison.
- Round A `displayFPS` samples: A2 and A8 at 28.5–30.0, A3 and A7 at 59.9–60.0, A4 and A6 at 35.8–51.1, and A5 at 60.0. A1 sampled 29.6–60.0, with 60 in the sample after its seeks. `displayFPS` is not the content frame rate: A1 is a 29.97 fps file and A5 averages 46.9 fps. A1 dropped 10 frames, no other file dropped any, and A/V sync stayed within 23 ms after each open's first sample.
- The AVFoundation `PlaybackPerf` sample carries no frame-rate, sync, or drop fields, so round B has no frame-level comparison.
- `firstFrame` is not a like-for-like measure. KSPlayer logs it at the first time-observer sample with `displayFPS >= 1`, so round A values sit about 1 s after `ready`. AVFoundation logs it once the playhead advances 0.1 s while playing.
- The operator reported that playback was normal for all eight files in both rounds, and that seeking was normal on the files where it was used.

### Progress on close

- Round B closes saved the playhead. A2 through A7 played to the end and saved the AVFoundation duration. For A6, AVFoundation reported 9.30 s against a container duration of 8.6 s.
- In round A, A1 logged `[KSEngine] finished playback` about 14 ms after a `seekEnd`. The last scrub-preview request before that seek was at 80.5 s of 131.8 s, and closing then saved progress 0 without marking the item watched. The seek target is not logged, so the log cannot tell whether KSPlayer ended early or the operator released the scrub near the end. The other five round A files that ended saved a position near their length.
- Reaching the end right after a seek also happened on AVFoundation: round B's A8 logged `ended` 0.19 s after a `seekEnd`, then kept its playhead through later seeks and saved 12.0 s. Saving 0 after the end was seen only on KSPlayer's A1.

## Decision

Native-container routing stays KSPlayer-first. AVFoundation opened and played all eight real files with no buffering, including two FFmpeg-muxed MP4s, which removes compatibility as the main blocker for these files. The comparison still has no iOS CPU or energy measurement, no frame-level AVFoundation metrics, and no retest of the files behind the earlier AVPlayer failures, which are described only as local and remote HTTP remuxes.

## Risks

- The files behind the earlier AVPlayer failures were not identified or retested. The sample has no remote HTTP files and no files with multiple audio or subtitle tracks.
- The first round B capture failed: `idevicesyslog` captured no Vanmo lines from an app launched by `devicectl`. Round B was replayed with `devicectl ... --console` and `OS_ACTIVITY_DT_MODE=1`.

## Progress Log

- 2026-10-21: On iPhone 17 Pro, eight real MP4/MOV files played locally through both KSPlayer and AVFoundation with no errors or buffering. `ready` took 18–173 ms on KSPlayer and 27–90 ms on AVFoundation, and neither engine was consistently faster per file. One KSPlayer open saved progress 0 after a `finished playback` that followed a seek. Routing stays KSPlayer-first.

## Open Decisions

- Whether to route some native containers to AVFoundation on iOS. This needs an iOS CPU or energy comparison on the same files and is a product decision.
