# Direct Link Streaming and Download

**Status:** Completed
**Created:** 2026-11-03
**Completed:** 2026-11-04
**Plan type:** Implementation with dual-platform acceptance
**Product spec:** [`../../product-specs/direct-links.md`](../../product-specs/direct-links.md)
**Related architecture authority:** [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md)

## Objective

Let a user paste a direct `http(s)` video link to stream it or download it without a saved connection, on iOS and macOS, with a Vanmo-styled page rather than a copy of Infuse's numbered-steps screen.

## Decisions (operator, 2026-11-03)

- Both platforms; core logic shared in `VanmoCore`.
- Entry: the iOS Files `+` becomes a menu (Add Connection / Open URL); the macOS sidebar `连接` `+` becomes the same menu.
- The recent list and resume progress persist locally only, outside the media library grouping and iCloud.
- Figma first. Approved frames: iOS `DirectLink-Light` `640:2`, `DirectLink-Dark` `641:61`, `DirectLink-States` `642:2` (file `miM6YTQAnerz6SgkkYZMjo`, page `File`); macOS `DirectLink-Light` `118:406`, `DirectLink-Dark` `118:503`, `DirectLink-States` `119:406` (file `O75W1XT1Q0btSrepDwEx39`, page `Files`).
- macOS sidebar `URL 链接` row appears only while the page is open or a direct link exists.

## Scope

- `DirectLinkLibrary` (parse, upsert, list, remove, download-task lookup) and `DirectLinkListModel` in `VanmoCore/Storage`.
- `DownloadManager` downloads a connection-less `http(s)` `sourceFileURL` through the existing Range / `.part` path; `DownloadRequest.sourceKey` uses `absoluteString` for non-file URLs.
- iOS `DirectLinkView`, macOS `MacDirectLinkView`, `.directLinks` route, both `+` menus, localized strings.

Out of scope: a `vanmo://` deep link or share-extension intake, custom request headers or cookies, and re-signing expired links.

## Found Defects and Fixes

- **Prefetch crash after close.** With a broken link routed through the localhost prefetch proxy, `RemoteFetcher.close()` invalidated the range session while `probeTotalSize()` swallowed the cancelled HEAD and created the next task on the invalidated session, raising an Objective-C exception (`-[__NSURLSessionLocal taskForClassInfo:]`, SIGABRT). The range delegate now refuses new tasks after `close()` or `didBecomeInvalidWithError` and throws `CancellationError`.
- **Generic HLS entered file prefetch.** Both players bypassed prefetch only for media-server playlists. `PrefetchConfig.isPlaylist(_:)` now bypasses any `.m3u8` / `.m3u`.
- **HLS resume waited for the whole file.** The iOS `HlsTranscodePrimer` downloaded the target "segment" before a resume; for a byte-range fMP4 playlist that is the entire 150 MB file (54 s before `engine.load`). The primer now skips playlists with `#EXT-X-BYTERANGE`; resume reached `ready` in 1050 ms.
- **Clipboard highlight.** `hasURLs` is false for a copied URL string, so the Paste chip also uses `detectedPatterns(for: [\.probableWebURL])`.
- **Post-task review (2026-11-04).**
  - Public `http://` links: ATS allows only local cleartext, and a simulator download of a public `http://` link failed. Per the operator's decision ATS is unchanged; `parse` now rejects a public `http://` host with `公网链接请使用 https://`.
  - Uppercase schemes: an uppercase scheme passed `parse` but missed the case-sensitive download branch. `parse` now lowercases the scheme and host, and the branch compares case-insensitively.
  - macOS Return key: the Play button's `.keyboardShortcut(.defaultAction)` duplicated the field's `onSubmit`, so it was removed.
  - macOS VoiceOver: the macOS row gained an accessibility Play action.

## Verification Evidence

- `swift test --package-path Packages/VanmoCore`: 358 tests, 0 failures, 1 skipped (2026-11-04, after the review fixes). New: 14 `DirectLinkTests`, 2 `PrefetchTests`, 1 `IntroSkipTests` primer case. `BoxOAuthTests.testConcurrentRefreshIsCoalescedIntoOneOperation` failed intermittently in 2 of 7 runs; it belongs to the uncommitted Box work and is unrelated.
- After the review fixes, the iOS Simulator rejected a public `http://` link inline (`dl-24-http-blocked.png`).
- 2026-11-11 operator manual check on VanmoMac: pressing Return in the URL field started playback exactly once, and closing the player left no `请输入视频链接` error.
- 2026-11-11 operator manual walk on a physical iPhone passed the Open URL feature.
- `./scripts/check-architecture-guards.sh`: 0 failures after `xcodegen generate`.
- `./scripts/check-app-build.sh ios-simulator` and `macos`, run serially after the last code change: both `BUILD SUCCEEDED`.
- iOS Simulator (iPhone 17 Pro, iOS 26.0, Debug, agent-operated with `idb`): `+` menu; empty state; `ftp://` inline error; a mistyped link failed with the red retry control; swipe removal; MP4 download with progress ring and the existing Dynamic Island capsule, then `已下载` and a 991,017-byte file in `Documents/Downloads`; MKV streamed through KSPlayer and saved progress (`9.63 / 10 s`, watched, `isProgressCloudSynced = 0`, `sourceConnectionId = nil`); the item appeared in the home history row; clipboard-detected Paste chip; HLS streamed through AVPlayer, showed `仅串流`, the resume bar and `剩余 9分钟`, and resumed at 25.0 s.
- VanmoMac (Debug, agent-operated with real CGEvent clicks; System Events clicks do not reach SwiftUI plain buttons and the active Pinyin input source swallowed `keystroke`): sidebar `+` menu; conditional `URL 链接` row selected; empty-field error; Paste → Download → `已下载` with Reveal in Finder and a 991,017-byte file in `~/Downloads/Vanmo`; MKV streamed in the player window; the list reordered after close.
- Screenshots: `build/direct-link-evidence/` (local, not committed).

## Risks

- Signed links that expire cannot be refreshed; the download fails and offers retry.
- `MediaScanner` and the Files browser adopt a connection-less item only when a scanned file's URL is identical; a direct link matching a scanned URL exactly is unlikely.
- The system Paste button label follows the device language, not the in-app language.
## Progress Log

- 2026-11-03: Decisions recorded; Figma frames designed and approved; VanmoCore, iOS, and macOS implemented; package tests, guards, and both app builds passed; iOS Simulator download, MKV stream, and failure / removal walk passed; HLS walk exposed the prefetch crash.
- 2026-11-04: Fixed the crash, generic HLS prefetch bypass, byte-range primer, and clipboard highlight; reran package tests; iOS HLS stream, resume, and macOS walk passed; serial app builds passed again. Post-task review findings fixed (public-http rejection, scheme case, macOS Return, VoiceOver action) and re-verified.
- 2026-11-11: Operator confirmed on VanmoMac that Return in the URL field plays once and leaves no empty-input error after the player closes, and manually verified the feature on a physical iPhone.

## Open Decisions

None.
