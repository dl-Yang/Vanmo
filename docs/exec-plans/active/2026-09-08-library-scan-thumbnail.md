# Library Shallow Scan, Identification, and First-Frame Covers

**Status:** In progress
**Plan type:** Feature / library
**Related product spec:** [`../../product-specs/library-scan.md`](../../product-specs/library-scan.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

On a file-based connection, the first local connect scans the outermost path (root plus immediate subfolders), identifies movie and episode names from filenames, clusters same-folder series, and shows keyframe covers when the source has no poster. Files-browser video rows use the same thumbnail cache and fall back to the file icon.

## Scope

- Automatic shallow scan when this device has no `MediaItem` rows for the connection
- `maxDepth = 1` and no prune
- Filename identification plus same-folder episode clustering
- Local keyframe JPEG cache for scanned items and Files icons
- iOS and macOS Home / scanned-library grouping by folder

## Out of Scope

- Continue Watching, favorites, search, downloads, detail hero, history, and other cover surfaces (pending a later product decision)
- TMDb or `poster.jpg` sidecar scraping
- CloudKit sync of posters or `MediaItem` catalog rows
- Replacing Emby / Jellyfin / Plex artwork
- Recursive first-connect full-library scan

## Verification

1. `swift test --package-path Packages/VanmoCore` including shallow-scan, clustering, grouping, and thumbnail-cache cases
2. `./scripts/check-harness-docs.sh`
3. `./scripts/check-cloud-sync-multiplatform-scope.sh` if scan or store boundaries changed
4. Serial `./scripts/check-app-build.sh ios-simulator` then `macos`
5. Do not mark a real SMB/WebDAV first-connect journey passing unless an operator records it

## Risks

- Concurrent libsmbclient `smbc_new_context` / `lp_load` aborts in `talloc`. Cover extraction is serial (`maxConcurrent = 1`) and shares `LibavformatOpenGate` with probe and iOS SMB/FTP/SFTP playback through shutdown plus a 400ms close drain. Presenting the player pauses the cover queue.
- A shallow empty root hides the connection from Home until the user syncs a deeper directory
- Serial KSPlayer covers can stall Home posters on large libraries or while iOS is playing SMB
- Google Drive first-byte latency can exceed the 20s cover timeout; a `prefetchFail` skips the raw HTTPS open instead of reporting a misleading timeout
- Baidu open-platform `dlink` is a download URL (302, `User-Agent: pan.baidu.com`, optional Range for resume), not a seekable original stream. Prefetch size probes and KSPlayer keyframe opens time out at ~20s. Covers now use official `filemetas thumb=1`; play skips prefetch and opens `dlink` with the required User-Agent. There is no public own-file M3U8 API
- Baidu implicit-grant tokens have no refresh; an expired login fails listing, dlink exchange, official thumbs, and play until the user signs in again
- `MediaProbeQueue` still opens Google/Baidu URLs without streaming headers, so duration and codec fields can stay empty after a successful cover
- Some Baidu videos may have no `thumbs` payload; those items keep the file icon instead of a keyframe
- Official `thumbs` URLs can still fail JPEG download after `hasThumb=true`; the queue skips keyframe and keeps the file icon
- Root “同步当前目录” walks `maxDepth=8` at 1 rps; cancel works and Files stays interactive, but a large account can run for many minutes

## Progress

- **2026-09-08:** Shallow scan, filename identification, clustering, and the thumbnail queue landed. Package tests 174. Serial iOS (`20260908-172429-52438`) then macOS (`20260908-172552-53074`) Debug compiles passed. iOS SMB first-connect recorded `shallowRoot inserted=4`; AVFoundation could not open `smb://`.
- **2026-09-09:** Covers use serial KSPlayer keyframes (`engine=ksplayer-me`, `maxConcurrent = 1`) behind `LibavformatOpenGate` with a 400ms close drain. Reconnect skips the remote tree and resumes missing posters only. Path keys prevent a second insert; historical duplicates are not merged. JPEG is unscaled quality `1.0`. Package tests 185. Device connection `D7C3B015` recorded four `extractOK` covers, Files `smb://` play without abort, first-connect `shouldScan=true`, and reconnect `skipScan reason=connectOnly`.
- **2026-09-09:** Home/list poster mix-up was `scaledToFill` hit-testing overflow, not navigation identity. Cards use `contentShape` matching the visible rounded rect. ID-based `navigationDestination(item:)` stays to avoid Lazy `NavigationLink` destination capture. Operator confirmed four Home/scanned posters open the tapped file. Temporary `[Debug][LibraryNav]` logs and the extra Detail-id fields were removed. `./scripts/check-harness-docs.sh` and iOS Simulator compile `20260909-165742-98467` passed after that cleanup.
- **2026-09-10:** Google Drive and Baidu covers now register `PrefetchProxy` with the same `StreamingRequestHeaders` provider as play (Bearer / `User-Agent: pan.baidu.com`). A failed register skips the raw HTTPS open. iOS play uses `KSOptions.appendHeader` only when prefetch is unavailable; it no longer loads those sources without headers. Package tests 190, including header-provider declaration, queue prefetch routing, and empty-header skip cases. `./scripts/check-harness-docs.sh` passed. Serial iOS Simulator (`20260910-090058-14186`) then macOS (`20260910-090139-14486`) Debug compiles passed. No Baidu or Google Drive cover walk is recorded yet.
- **2026-09-10:** iOS Console on a Baidu library showed `extractStart via=prefetch` then `engine=ksplayer-me elapsedMs≈20000 error=timedOut` and `files result ok=false`. Official docs confirm `dlink` is a download URL (follow 302, keep `User-Agent: pan.baidu.com`; Range is for resume) and covers belong on `filemetas thumb=1`. The queue now prefers official thumbs and skips keyframe/prefetch for Baidu; play opens `dlink` with the User-Agent and does not Range-probe through PrefetchProxy. Package tests 198. `./scripts/check-harness-docs.sh` passed. Serial iOS Simulator (`20260910-094301-18681`) then macOS (`20260910-095724-21149`) Debug compiles passed. Device cover/play evidence is not recorded yet.
- **2026-09-10:** Device Baidu walk confirmed `categorylist+start` paging (no `repeatFirst` loop). A shallow pass finished `scanToast=同步完成，4 项待确认`. A following full tree walk then hit HTTP 400 `errno 31034 hit frequency limit` on later directories; those `listFail` rows were the “21 problems” toast, not probe failures. Listing now retries 31034 with backoff and Baidu scan rate is 1 worker / 1 rps. Operator confirmed the scan no longer sticks on frequency-limit failures. Temporary `[Debug][BaiduScan]` session probes were removed. Frequency-limit detection trusts JSON `errno` when present; a body that merely contains the digits `31034` is not treated as 31034.
- **2026-09-11:** iOS Simulator Baidu closeout on iPhone 17 Pro recorded reconnect `skipScan reason=resumeCovers`, official `baiduThumbs hasThumb=true` plus `skipKeyframe` (no prefetch/KSPlayer 20s cover path), Files `cacheHit` for an already-stored JPEG, and one `dlink` play (`official download link, skip prefetch`, KSPlayer `readyToPlay` duration 2002s, `state=playing`). A root “同步当前目录” walk used `scope=directory maxDepth=8` at ~1 dir/s with the Files list still interactive and a cancelable banner (220 directories / 4999 videos mid-walk); cancel produced `done status=cancelled`. Deleting while Home still held `MediaItem` rows first hit SwiftData `mediaType` fault; iOS now matches macOS (cancel scan, drop UI refs, then LocalStore cleanup). After delete, Files showed no sources and Home was empty. Package tests 202. Serial iOS Simulator (`20260911-101329-50240`) then macOS (`20260911-101434-50853`) Debug compiles passed before the walk. Signed VanmoMac CloudKit exported and imported; seven Baidu `SavedConnection` rows stayed `home hide reason=noItems` with no local catalog and no auto-scan. Google Drive is unchanged.
- **2026-09-11:** Vanmo-macOS Debug re-authenticated one imported Baidu connection (`accept reauth ok=true`), listed 19 Files entries, inserted 4 local catalog rows, and played through `MacKSPlayerEngine` with `KS official download link, skip prefetch` and `load complete`. The Baidu connection-validation plan moved to `docs/exec-plans/completed/`.

## Next step

Google Drive still expects prefetch keyframes.

## Open Decisions

- How other cover surfaces should use keyframe art after this library/Files path; tracked as deferred debt, not as remaining work on this plan
