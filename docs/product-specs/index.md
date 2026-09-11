# Product Specifications Index

This folder contains current user-visible behavior and acceptance targets. It does not replace implementation sources, tests, or execution-plan status.

## Active Specifications

- [`downloads.md`](downloads.md): macOS download progress, pause controls, detail navigation, and HTTP-via-Emby real-source recovery acceptance; iOS Figma download-page behavior is specified; 2026-08-27 simulator HTTP-via-Emby runs recorded enqueue, progress, complete, play, and `.part` resume; one 2026-08-28 physical-device SMB enqueue, terminate-while-downloading `.part` restore, and completion run is recorded; one 2026-08-28 macOS SMB library-detail mixed run (one movie + three episodes) recorded the eleven-step matrix
- [`smb-connections.md`](smb-connections.md): SMB connect, browse, and KSPlayer playback for iOS and macOS, including unreadable-share hiding; 2026-08-27 File Sharing runs passed on iOS Simulator and VanmoMac
- [`smb-311-encryption.md`](smb-311-encryption.md): SMB 3.1.1 AES-GCM encryption-required connect, browse, and play; 2026-08-28 VanmoMac and iOS-device runs recorded `0x311` + `encrypt=true`, a `MacShare` listing, VanmoMac prefetch `source=smb`, and an iOS KSPlayer `smb://` load
- [`ftp-connections.md`](ftp-connections.md): FTP connect, browse, KSPlayer prefetch play, and Files-browser download; 2026-08-31 iOS Simulator and VanmoMac runs recorded login, listing, play, download, and local play
- [`sftp-connections.md`](sftp-connections.md): SFTP connect, browse, KSPlayer prefetch play, and Files-browser download; 2026-08-31 iOS Simulator and VanmoMac runs recorded login, listing, play, download, and local play
- [`app-language.md`](app-language.md): Chinese / English / Follow System interface language on Appearance settings; default Chinese; applies after restart; 2026-09-01 iOS Simulator and macOS operator walks plus isolated `check-app-build.sh all` are recorded
- [`library-scan.md`](library-scan.md): first-connect shallow scan of the outermost path, filename identification, same-folder episode clustering, and serial KSPlayer keyframe covers for scanned items and Files icons; Baidu Netdisk covers use official `filemetas` thumbs instead of opening the download `dlink`; later connects resume missing covers only and do not rescan; a 2026-09-09 iOS SMB walk recorded scan, covers, Files play, reconnect, and matching poster navigation; a 2026-09-11 iOS Simulator Baidu walk recorded official thumbs, `dlink` play, cancelable directory sync, and local catalog cleanup; the same day Vanmo-macOS re-authenticated, listed, scanned four local rows, and played with `skip prefetch`; CloudKit still syncs the connection only

## Rules

- Describe observable behavior and acceptance criteria, not implementation aspirations.
- Distinguish automated, build, visual, and manual real-environment evidence.
- Do not mark behavior verified because corresponding code exists.
- Update the specification and its execution plan together when acceptance changes.
- Keep credentials, complete authenticated URLs, and private media details out of evidence.
- Keep this index current so a new session can discover active product scope.
