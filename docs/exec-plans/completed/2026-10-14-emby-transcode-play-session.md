# Emby Transcode Play Session

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

End the Emby/Jellyfin HLS transcode that iOS opens for a lower quality when playback stops or switches quality. Before the change, the transcode playlist from `PlaybackInfo` carried the server's `PlaySessionId`, but `Sessions/Playing/Stopped` and the progress reports used the reporter's own UUID. The server could not tie the stop to the transcode job. On a public Emby server, the fourth and fifth back-to-back HLS starts loaded the playlist but never became ready.

## Scope

- VanmoCore `EmbyTranscodeClient.playSessionID(in:)` reads `PlaySessionId` from an `.m3u8` URL only.
- `EmbyPlaybackSession.playbackURLDidChange(_:)` switches the reporting `PlaySessionId` to the transcode's id, or back to the reporter's UUID for a direct URL. When it replaces a transcode id, it calls the new `EmbyService.stopActiveEncodings(playSessionId:)` (`DELETE Videos/ActiveEncodings` with `DeviceId` and `PlaySessionId`).
- `EmbyPlaybackSession.trackUnsettledTranscode(_:)` records a transcode that was requested but not adopted. A superseded, failed, or cancelled reload may still be on the engine, or may be resumed later. Unsettled ids are ended on the next `playbackURLDidChange`, excluding the id being adopted, and on `stopped`.
- If `Started` never succeeded, `stopped(position:)` ends the current and unsettled transcodes directly, because the server ignores a stop without a start.
- Start, progress, and stop reports send `PlayMethod=Transcode` while the session uses a transcode id.
- iOS `PlayerViewModel` hooks:
  - It reports the opened URL after the initial load, after a quality reload that is still current, and after a restore.
  - Any other reload that reached the open step marks its URL unsettled, before the restore when one follows.
  - An initial transcode open that falls back to the direct URL marks the transcode unsettled once the new item's session exists, so the first report ends it.

## Out of Scope

- macOS, which does not switch to transcoded qualities
- Plex transcode sessions

## Verification

- `swift test --package-path Packages/VanmoCore`: 273 tests, 0 failures. New `EmbyPlaybackReportingTests`:
  - The id is read from a playlist only.
  - The session switches ids across direct, 720p, 480p, and direct URLs.
  - Unsettled ids end when another URL is adopted, and survive when they are themselves adopted.
  - The `DELETE Videos/ActiveEncodings` request is checked with both the Emby (`emby/`) and Jellyfin (empty) prefixes: method, `DeviceId`, `PlaySessionId`, and `api_key`.
  - The check-in body sends `PlayMethod=Transcode` only for a transcode id.
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261014-154055-34167`), then `macos` (`20261014-154131-34614`)
- iPhone walks on Emby item 253013 (`emby.bangumi.ca`), filtered `idevicesyslog` captures:
  - Before the review fixes: five HLS transcode starts across a 720p switch, close and reopen at 720p, a 480p switch, and two more reopen cycles. Each logged `PlaybackInfo status=200 transcode=true` and `event=playSessionChange transcoding=true`. The 720p-to-480p switch logged `event=stopActiveEncodings result=ok`. The operator confirmed that every start played.
  - After the first review round, superseded reloads were ended immediately. The rapid-switching walk logged each superseded reload's `stopActiveEncodings result=ok`, and the operator confirmed playback continued. One walk in this round produced no log lines and is not counted.
  - Final code: three rapid reloads ended at 480p. Right after the 480p open adopted its id, three `stopActiveEncodings result=ok` lines ended the initial 720p transcode and the two superseded reloads. Closing and reopening started a new transcode that played. The operator confirmed all playback.
  - No capture logged `stopped failed` or `progress failed`.

## Risks

- The server's transcode list was not inspected. That the stop ends the job is inferred from the API contract and the successful requests.
- Jellyfin was not walked.
- Several paths leave a transcode for the server to reap, because the session is already stopped or not yet created:
  - The player closes or switches episodes while a quality reload or the initial load is opening.
  - The initial load's direct fallback also fails.
  - A quality change succeeds before the initial load creates its session.
- When a superseded reload's engine is resumed by `recoverAbandonedQualityReload` (`.paused`), reports keep the previous id until the next switch or stop. In the meantime, progress pings the previous transcode, which is no longer playing, and does not ping the one that is.
- `stopTranscode` and `started` can each create the session's `EmbyService` when neither has finished authenticating, which runs `AuthenticateByName` twice. The window is narrow. Re-authenticating for each playback is existing behavior.

## Progress Log

- 2026-10-14: Implemented in VanmoCore and the iOS view model, added tests, ran both builds, and walked back-to-back HLS starts on iPhone.
- 2026-10-14: After the first post-task review, ended never-played transcodes, stopped the transcode for a session that never started, and added request-level tests. Walked rapid switching on iPhone.
- 2026-10-14: The second review found that ending a superseded transcode right away could end the one later restored. Replaced that with unsettled tracking, then re-ran tests and builds and walked rapid switching on iPhone again.

## Open Decisions

- None.
