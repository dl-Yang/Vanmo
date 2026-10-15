# HLS Prime Size Probe

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Stop the HLS quality primer from downloading a finished segment a second time. On 2026-10-08 the prime before AVPlayer opened took about 7.4–7.6 seconds. The first download waits for the server to finish the segment. The second download existed only to see that the byte count had stopped changing, and the logged pairs were identical.

## Scope

- After a segment download is not already aligned, the primer waits 400 ms and requests `Range: bytes=0-0`.
- A `206` `Content-Range` total, or a `200` `Content-Length`, that matches the downloaded size is treated as stable. The primer returns that body and does not download it again.
- If the probe does not report a matching size, the primer still downloads the segment again, up to three attempts.
- `HlsTranscodePrimer.contentRangeTotal` parses the total.

## Out of Scope

- Making the server finish the first segment faster. That remains most of the wait.

## Verification

- `swift test --package-path Packages/VanmoCore`: 277 tests, 0 failures, including `testContentRangeTotalReadsTheSizeAfterTheSlash`
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261015-153345-78596`), then `macos` (`20261015-154305-79764`)
- iPhone, Emby item 253013, filtered `idevicesyslog`:
  - The build that only accepted `206` still logged `attempt=0` and `attempt=1` (15:31:33.707 to 15:31:35.822) and no `sizeProbe`. The operator said audio and video stayed together.
  - The build that also reads `Content-Length` logged `attempt=0` then `stage=sizeProbe` with the same byte count, and no `attempt=1`. A 360p open went from the first body at 15:41:10.040 to `sizeProbe` at 15:41:10.993 and `result=opened` at 15:41:11.790. The operator said audio and video stayed together.

## Risks

- A server that reports a finished `Content-Length` while ffmpeg is still appending can skip the second download. This server's probe total matched the body, and the following segments were still shifted for lip sync.
- The first download is still the long part of the old 7-second prime.

## Progress Log

- 2026-10-15: Replaced the stability re-download with a size probe. The first device build ignored non-206 responses and still downloaded twice. Accepting `Content-Length` on 200 made the probe stick. Lip sync held on both walks. macOS Debug build `20261015-154305-79764` passed.

## Open Decisions

- None.
