# Completed Execution Plans

Completed plans remain as durable evidence of what was attempted, decided, and verified.

## Completed Plans

- [`2026-08-25-mac-download-real-source-validation.md`](2026-08-25-mac-download-real-source-validation.md) — **Completed.** One HTTP-via-Emby macOS download run passed queue, pause, restart-from-part, and main-window detail navigation; SMB was not exercised.
- [`2026-08-26-ios-download-parity.md`](2026-08-26-ios-download-parity.md) — **Completed.** iOS downloads page implemented from Figma Download; one HTTP-via-Emby simulator run passed enqueue, live progress, completion, and local play.
- [`2026-08-27-ios-download-part-resume.md`](2026-08-27-ios-download-part-resume.md) — **Completed.** One iOS simulator HTTP-via-Emby run passed pause, terminate, restore from `.part`, and resume at the restored offset.
- [`2026-08-28-ios-device-smb-download.md`](2026-08-28-ios-device-smb-download.md) — **Completed.** One physical-device SMB run passed Files-browser enqueue, same-session resume, terminate while downloading, cold-launch `.part` restore, and completion.
- [`2026-08-28-macos-smb-download-matrix.md`](2026-08-28-macos-smb-download-matrix.md) — **Completed.** Run 3 passed the eleven-step macOS SMB matrix (one movie + three episodes, inferred single-task pause/resume, `.part` continue, movie and episode `open detail`). The earlier Files-browser `failed` restore was local disk exhaustion, not engine debt.
- [`2026-08-27-smb-connection-fix.md`](2026-08-27-smb-connection-fix.md) — **Completed.** iOS Simulator and VanmoMac connected to this Mac's File Sharing share `yinguSMB`, listed files, and played a video; macOS playback used the SMB-backed prefetch proxy.
- [`2026-08-28-alist-connection-validation.md`](2026-08-28-alist-connection-validation.md) — **Completed.** iOS Simulator and VanmoMac connected to LAN AList WebDAV `/dav`, listed files, played through KSPlayer plus prefetch `source=http`, and completed a Files-browser download with local play.
- [`2026-08-28-ftp-connection-validation.md`](2026-08-28-ftp-connection-validation.md) — **Completed.** iOS Simulator and VanmoMac saved a Windows FTP host/account connection, logged a logical connect, and showed an empty listing; this is the documented placeholder gap, not a working FTP client.
- [`2026-08-30-ftp-real-source.md`](2026-08-30-ftp-real-source.md) — **Completed.** iOS Simulator and VanmoMac connected to LAN FTP at `192.168.1.77:21`, listed a non-empty directory, played through KSPlayer plus prefetch, and completed a Files-browser download with local play.
- [`2026-08-28-sftp-connection-validation.md`](2026-08-28-sftp-connection-validation.md) — **Completed.** iOS Simulator and VanmoMac connected to LAN SFTP at `192.168.1.77:22`, listed a non-empty directory, played through KSPlayer plus prefetch `source=sftp`, and completed a Files-browser download with local play.
- [`2026-08-28-smb-311-encryption.md`](2026-08-28-smb-311-encryption.md) — **Completed.** VanmoMac and an iOS device connected to encryption-required `MacShare` at `192.168.1.77` with SMB 3.1.1 AES-128-GCM (`dialect=0x311`, `encrypt=true`); later pastes recorded VanmoMac prefetch `source=smb` and an iOS KSPlayer `smb://` load.
- [`2026-08-26-debug-build-evidence-layer.md`](2026-08-26-debug-build-evidence-layer.md) — **Completed.** Layered Debug compile evidence exists; later full matrix on `34bf345` passed iOS Simulator and macOS.
- [`2026-08-26-ios-ui-golden-journey.md`](2026-08-26-ios-ui-golden-journey.md) — **Completed.** Simulator XCUITest tab-navigation journey recorded; iOS Debug compile unblocked; physical-device XCUITest remains optional follow-up.
- [`2026-08-26-harness-narrative-consistency.md`](2026-08-26-harness-narrative-consistency.md) — **Completed.** Documentation check now fails on init stage-count and plan-index Status conflicts.
- [`2026-08-28-architecture-structure-guards.md`](2026-08-28-architecture-structure-guards.md) — **Completed.** Stage 2 now rejects XcodeGen drift, illegal target sources, and unconditional VanmoCore UI imports; fast baseline stays at four stages.
- [`2026-08-31-app-language-switching.md`](2026-08-31-app-language-switching.md) — **Completed.** Chinese / English / Follow System on Appearance; 2026-09-01 iOS Simulator and macOS operator walks plus isolated `check-app-build.sh all` passed.
- [`2026-09-01-ios-home-detail-files-ui.md`](2026-09-01-ios-home-detail-files-ui.md) — **Completed.** iOS Simulator walk passed home loading under the title, favorites 1/2/3+, default hero, TV/movie resolution tags, Files root without status, and the Figma Add Connection dialogs.
- [`2026-09-01-ios-testflight-launch-crash.md`](2026-09-01-ios-testflight-launch-crash.md) — **Completed.** TestFlight launch crash mitigated with CloudStore defaults, no `mediaKey` unique, local-only launch, and one-time store reset. CloudKit re-attach is recorded in the 2026-09-02 iCloud plan.
- [`2026-09-02-icloud-debug-device.md`](2026-09-02-icloud-debug-device.md) — **Completed.** Signed iOS and macOS Debug attach `iCloud.com.vanmo.app`; Dashboard and macOS missing-password connect of an iOS-synced Emby row are recorded. Passwords stay on-device Keychain.

## Archival Rules

- Move a plan here rather than deleting it.
- Preserve its objective, final scope, dated progress, decisions, verification commands, manual evidence, and unresolved follow-ups.
- A plan is not completed merely because code exists; its required verification must have passed or a superseding decision must be recorded.
- Link any remaining confirmed debt from `../tech-debt-tracker.md`.
