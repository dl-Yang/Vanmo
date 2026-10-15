# Prefetch Lookbehind

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Shorten the wait between KSPlayer `ready` and the first picture on a proxied media-server file that resumes in the middle. On 2026-10-08, Emby item 253013 resumed near 1680 seconds. `ready` was 2.4–2.9 seconds and `firstFrame` was 8.1–8.9 seconds. After `play()`, KSPlayer's clock was already at the resume time while it decoded backward from the previous keyframe, and the prefetch window started at the playhead, so those earlier bytes were not local.

## Scope

- `PrefetchConfig.lookbehindByteBudget` is 15 seconds of the file's average bitrate, capped at 8 MiB, and at least one chunk.
- The ahead loop fills that range behind the playhead before the forward fill, including when the playhead is still inside the first half of the budget. It records the fill only when the range completes. A playhead jump of more than two chunks leaves it unfinished so the next loop can retry. It fills again after the playhead moves by more than half of that budget.
- The fill still stops if the playhead jumps by more than two chunks.

## Out of Scope

- A new timing of item 253013. The 2026-10-08 logs are the baseline. The after measurement is still open.
- Changing KSPlayer's accurate seek or its display clock

## Verification

- `swift test --package-path Packages/VanmoCore`: 276 tests, 0 failures, including the lookbehind budget, the near-start fill, and the retry after the playhead leaves
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261015-112335-61594`), then `macos` (`20261015-112358-61718`)

## Risks

- The first forward fill starts after the lookbehind download. A resume whose keyframe is farther than 15 seconds or 8 MiB still waits on the network.
- Without a new play of the same Emby item, the 6-second gap is not shown to be smaller.

## Progress Log

- 2026-10-15: Added the lookbehind fill from the 2026-10-08 resume logs. A review found the first fill was skipped near the start of the budget and that an interrupted fill was recorded as done. Both are fixed, with session tests. The same Emby resume was not played again.

## Open Decisions

- None.
