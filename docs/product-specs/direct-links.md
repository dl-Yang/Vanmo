# Direct Links (Open URL)

**Product area:** Vanmo and VanmoMac Files  
**Source scope:** Pasting a direct `http(s)` video link to stream it or download it without a saved connection, on iOS and macOS.

## User-Visible Behavior

- **Entry.** iOS: Files header `直链` pill opens the Open Direct Link sheet (`10 · Open Direct Link`). macOS: sidebar `连接` section `+` menu → `打开 URL 链接…` (or the `Direct URL` quick tile inside `MacAddConnectionView`) opens the page in the main content area. The macOS sidebar shows a `URL 链接` row only while the page is open or at least one direct link exists.
- **Link input card.** A single URL field with an inline system Paste button, a primary `播放` button, and a secondary `下载` button. Both buttons are disabled on iOS while the field is empty. On iOS the Paste chip turns accent blue when the clipboard holds a probable web URL; detection uses `hasURLs` / `detectedPatterns(for: [\.probableWebURL])` and never reads the clipboard until the user taps Paste.
- **Validation.** Only `http://` and `https://` links with a host are accepted; the scheme and host are lowercased before storage. App Transport Security stays at `NSAllowsLocalNetworking`, so cleartext `http://` is accepted only for an IP literal, an unqualified host name, or a `.local` host; any other `http://` link is rejected with `公网链接请使用 https://`. A link that embeds a username or password (`user:pass@host`) is rejected with a message that points to a WebDAV connection. Errors show inline under the field with a red field border, and editing the field clears them.
- **Recent links.** Every played or downloaded link is stored on this device and listed newest first (`lastPlayedAt`, otherwise `addedAt`). A row shows a format badge (extension, `HLS` for `.m3u8` / `.m3u`, `URL` when there is no extension), the decoded file name, the host, and a status: download progress, `已暂停`, `已下载`, `下载失败`, or the remaining time with a resume bar after partial playback. Tapping a row (iOS) or double-clicking / hover Play (macOS) streams it and resumes from the saved position.
- **Download control.** Per row: download → progress ring (tap pauses) → paused ring (tap resumes) → green check when completed; failure shows a red retry control. HLS playlists show `仅串流` and cannot be downloaded. Downloads use the shared download queue, so they appear in Downloads, drive the iOS Dynamic Island / Live Activity, resume from `.part`, and land in the normal download directory. macOS completed rows offer Reveal in Finder.
- **Removal.** iOS swipe or context menu, macOS hover trash or context menu. Removing a link deletes only the list entry and its progress; a queued or downloaded file stays in Downloads.
- **Continue watching.** A partially played direct link appears in the home history row like any connection-less item.

## Data and Privacy

- A direct link is a `MediaItem` in the local store with `sourceConnectionId == nil` and an `http(s)` `fileURL`. No new SwiftData model or schema version is involved.
- `isProgressCloudSynced` and `isFavoriteCloudSynced` are `false`, so direct links never enter `CloudMediaState` or iCloud.
- Links with embedded credentials are rejected before storage. A link may still carry a signed query token; Debug logs record only the host and extension, never the full URL.
- A download request uses `sourceFileURL` and the full `absoluteString` as its de-duplication key, so two hosts with the same path never collide.

## Acceptance Criteria

1. iOS and macOS `+` menus open the Open URL page; macOS shows the conditional sidebar row.
2. An `ftp://` link, a public `http://` link, and an empty field show the inline errors; a credential link is rejected.
3. A public MP4 link downloads through the shared queue, the row shows progress then `已下载`, and the file exists in the platform download directory with the source byte size.
4. A public MKV link streams through KSPlayer; a public HLS link streams through AVPlayer without the file prefetch proxy, shows `仅串流`, saves progress, shows the resume bar, and resumes from the saved position on the next tap.
5. Swipe / context removal returns the list to the empty state.

**Current acceptance status:** Completed. Agent-operated walks passed on the iOS Simulator (2026-11-03 / 2026-11-04) and on VanmoMac with real mouse events (2026-11-04); the operator manually verified VanmoMac Return-to-play and a physical iPhone on 2026-11-11.

## Evidence Rules

- `DirectLinkTests` prove parsing, storage, list ordering, removal, request keys, HLS eligibility, and the list model only.
- A compile or launch does not prove streaming or download. The acceptance walk is recorded in [`../exec-plans/completed/2026-11-03-direct-link-stream-download.md`](../exec-plans/completed/2026-11-03-direct-link-stream-download.md).
- Use public sample media for evidence; do not record private links or signed query tokens.
