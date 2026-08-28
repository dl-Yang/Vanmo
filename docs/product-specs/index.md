# Product Specifications Index

This folder contains current user-visible behavior and acceptance targets. It does not replace implementation sources, tests, or execution-plan status.

## Active Specifications

- [`downloads.md`](downloads.md): macOS download progress, pause controls, detail navigation, and HTTP-via-Emby real-source recovery acceptance; iOS Figma download-page behavior is specified; 2026-08-27 simulator HTTP-via-Emby runs recorded enqueue, progress, complete, play, and `.part` resume; one 2026-08-28 physical-device SMB enqueue, terminate-while-downloading `.part` restore, and completion run is recorded; one 2026-08-28 macOS SMB library-detail mixed run (one movie + three episodes) recorded the eleven-step matrix
- [`smb-connections.md`](smb-connections.md): SMB connect, browse, and KSPlayer playback for iOS and macOS, including unreadable-share hiding; 2026-08-27 File Sharing runs passed on iOS Simulator and VanmoMac
- [`smb-311-encryption.md`](smb-311-encryption.md): SMB 3.1.1 AES-GCM encryption-required connect, browse, and play; 2026-08-28 VanmoMac and iOS-device runs recorded `0x311` + `encrypt=true`, a `MacShare` listing, VanmoMac prefetch `source=smb`, and an iOS KSPlayer `smb://` load

## Rules

- Describe observable behavior and acceptance criteria, not implementation aspirations.
- Distinguish automated, build, visual, and manual real-environment evidence.
- Do not mark behavior verified because corresponding code exists.
- Update the specification and its execution plan together when acceptance changes.
- Keep credentials, complete authenticated URLs, and private media details out of evidence.
- Keep this index current so a new session can discover active product scope.
