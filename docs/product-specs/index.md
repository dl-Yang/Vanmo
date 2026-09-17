# Product Specifications Index

This folder contains current user-visible behavior and acceptance targets. It does not replace implementation sources, tests, or execution-plan status.

## Active Specifications

- [`downloads.md`](downloads.md): macOS download progress, pause controls, detail navigation, and HTTP-via-Emby real-source recovery acceptance; iOS Figma download-page behavior is specified; detail enqueue flies a poster capsule to the Dynamic Island, then hands off once to Compact `569:38` (tap expands to `570:259`; Compact ring vs pause-icon; Expanded pause pill; complete/delete collapse; ActivityKit is requested in the foreground and updated on resign-active so the scene can absorb into the hardware island); a notch iPhone without an island hides the system status bar, shrinks the capsule to the leading slot, and shows a solid-blue capsule with a white progress border (no video info, no Expanded; system privacy pills cannot host downloads; lock-screen Live Activity is requested on island and notch; 2026-09-17 13 mini recording `tem/cmp.mp4` passed flight, landed capsule, lock-screen Live Activity, and pause sync); or on SE / iPad lands then fades in the status-bar bar; island phones hide the system status bar; lock-screen cards open Downloads; 2026-09-13 / 2026-09-14 fixture walks recorded the iPhone 17 Pro island, iPhone SE fallback swallow, and signed Vanmo-macOS icon flight; 2026-08-27 simulator HTTP-via-Emby runs recorded enqueue, progress, complete, play, and `.part` resume; one 2026-08-28 physical-device SMB enqueue, terminate-while-downloading `.part` restore, and completion run is recorded; one 2026-08-28 macOS SMB library-detail mixed run (one movie + three episodes) recorded the eleven-step matrix
- [`smb-connections.md`](smb-connections.md): SMB connect, browse, and KSPlayer playback for iOS and macOS, including unreadable-share hiding; 2026-08-27 File Sharing runs passed on iOS Simulator and VanmoMac
- [`smb-311-encryption.md`](smb-311-encryption.md): SMB 3.1.1 AES-GCM encryption-required connect, browse, and play; 2026-08-28 VanmoMac and iOS-device runs recorded `0x311` + `encrypt=true`, a `MacShare` listing, VanmoMac prefetch `source=smb`, and an iOS KSPlayer `smb://` load
- [`ftp-connections.md`](ftp-connections.md): FTP connect, browse, KSPlayer prefetch play, and Files-browser download; 2026-08-31 iOS Simulator and VanmoMac runs recorded login, listing, play, download, and local play
- [`sftp-connections.md`](sftp-connections.md): SFTP connect, browse, KSPlayer prefetch play, and Files-browser download; 2026-08-31 iOS Simulator and VanmoMac runs recorded login, listing, play, download, and local play
- [`app-language.md`](app-language.md): Chinese / English / Follow System interface language on Appearance settings; default Chinese; applies after restart; 2026-09-01 iOS Simulator and macOS operator walks plus isolated `check-app-build.sh all` are recorded
- [`library-scan.md`](library-scan.md): first-connect shallow scan of the outermost path, filename identification, same-folder episode clustering, and serial KSPlayer keyframe covers for scanned items and Files icons; Baidu Netdisk covers use official `filemetas` thumbs instead of opening the download `dlink`; Google Drive covers use Bearer prefetch keyframes; later connects resume missing covers only and do not rescan; a 2026-09-09 iOS SMB walk recorded scan, covers, Files play, reconnect, and matching poster navigation; a 2026-09-11 iOS Simulator Baidu walk recorded official thumbs, `dlink` play, cancelable directory sync, and local catalog cleanup; the same day Vanmo-macOS re-authenticated, listed, scanned four local rows, and played with `skip prefetch`; a 2026-09-13 iOS Simulator and 2026-09-14 Vanmo-macOS Google Drive walk recorded prefetch `extractOK` plus reconnect `connectOnly` / `resumeCovers`; CloudKit still syncs the connection only

## Rules

- Describe observable behavior and acceptance criteria, not implementation aspirations.
- Distinguish automated, build, visual, and manual real-environment evidence.
- Do not mark behavior verified because corresponding code exists.
- Update the specification and its execution plan together when acceptance changes.
- Keep credentials, complete authenticated URLs, and private media details out of evidence.
- Keep this index current so a new session can discover active product scope.
