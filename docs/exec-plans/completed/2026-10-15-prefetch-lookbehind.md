# Prefetch Lookbehind

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Shorten the wait between KSPlayer `ready` and the first picture on a proxied media-server file that resumes in the middle. On 2026-10-08, Emby item 253013 resumed near 1680 seconds. `ready` was 2.4–2.9 seconds and `firstFrame` was 8.1–8.9 seconds. After `play()`, KSPlayer's clock was already at the resume time while it decoded backward from the previous keyframe, and the prefetch window started at the playhead, so those earlier bytes were not local.

## Scope

- `PrefetchConfig.lookbehindByteBudget` is 15 seconds of the file's average bitrate, capped at 8 MiB, and at least one chunk.
- The ahead loop fills that range behind the playhead before the forward fill, including when the playhead is still inside the first half of the budget. It records the fill only when the range completes. Another fill runs when the playhead jumps backward by more than two chunks, or forward beyond the ahead budget. Steady playback inside that window does not download it again.

## Out of Scope

- Removing the remaining decode wait inside KSPlayer after the display clock jumps to the resume time.
- Changing KSPlayer's accurate seek or its display clock

## Verification

- `swift test --package-path Packages/VanmoCore`: 276 tests, 0 failures, including the lookbehind budget, the near-start fill, and steady playback not repeating the lookbehind
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261015-113914-65358`), then `macos` (`20261015-114701-66369`)
- iPhone, Emby item 253013, filtered `idevicesyslog`:
  - First build: two resumes, `ready` 2689 ms then `firstFrame` 4689 ms (gap 2.0 s at 2236 s), and `ready` 6808 ms then `firstFrame` 9309 ms (gap 2.5 s at 1198 s). The 2026-10-08 gaps were 5.5–6.0 s. Playback also logged a new 8 MiB lookbehind every few seconds.
  - Follow-up build, after lookbehind runs only on open and on a real jump: one resume at 2250 s was `ready` 2848 ms and `firstFrame` 4845 ms (gap 2.0 s), then one at 1203 s was `ready` 5705 ms and `firstFrame` 7706 ms (gap 2.0 s). Each open logged a single `lookbehindFill`. The operator said the picture appeared and playback stayed normal.

## Risks

- The first forward fill starts after the lookbehind download. A resume whose keyframe is farther than 15 seconds or 8 MiB still waits on the network.
- A resume still waits about 2 seconds after `ready`. That remainder is KSPlayer decoding up to a clock that has already jumped to the resume time.

## Progress Log

- 2026-10-15: Added the lookbehind fill from the 2026-10-08 resume logs. A review found the first fill was skipped near the start of the budget and that an interrupted fill was recorded as done. Both are fixed, with session tests.
- 2026-10-15: iPhone resumes of item 253013 cut the gap after `ready` from about 6 seconds to about 2–2.5 seconds, and also showed an 8 MiB lookbehind repeating during playback. Lookbehind now runs on open and on a real jump. A second walk kept a 2.0 second gap and logged one fill per open. The operator said playback stayed normal.

## Open Decisions

- None.
