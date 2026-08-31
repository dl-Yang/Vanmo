# SFTP Real-Source Connect, List, Play, and Download

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-08-31  
**Plan type:** Implementation plus real-source acceptance  
**Related spec:** [`../../product-specs/sftp-connections.md`](../../product-specs/sftp-connections.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Replace the placeholder SFTP entry with a real password-authenticated client so Files can connect to an operator-entered SFTP server, list a non-empty directory, play a listed video, and download that file on both Vanmo iOS and VanmoMac.

## Scope

- Shared `SFTPService` connect, directory listing, `sftp://` stream URL, offset reads, and resume download.
- Prefetch `source=sftp` on both platforms so KSPlayer loads the localhost proxy, not raw `sftp://`.
- Dual-platform evidence under the shared rules in [`../active/index.md`](../active/index.md).
- Credentials stay operator-entered in the host/account form and Keychain.

## Out of Scope

- SSH public-key or known-hosts / TOFU UI
- FTPS, NFS, DLNA, and other placeholder protocols
- Treating an empty listing as a successful media source
- Expanding `FTPService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac
- Reachable password-authenticated SFTP (the passing run used `192.168.1.77:22`)
- Operator-entered username and password
- At least one playable video in a listed directory

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add SFTP.
2. Confirm `[SFTP] login ok` and `[SFTP] connected to`.
3. Confirm the first listing is non-empty (`[SFTP] listed N entries`).
4. Play one listed video. Record KSPlayer plus prefetch `source=sftp`.
5. Download the same file from Files and play the completed local file.
6. Repeat add, connect, list, play, and download on VanmoMac with `./run_device.sh --macos`.
7. Paste sanitized `[SFTP]` and `[Prefetch]` lines. Do not record passwords.

The plan completes only when both platform runs pass.

## Log prefix

`[SFTP]`

## Risks

- Some OpenSSH hosts advertise only keyboard-interactive and reject `password`. Citadel 0.12.1 may then fail login.
- First-version host-key policy is Citadel `.acceptAnything()`. Suitable for a user-owned NAS; not for an untrusted public host.
- `sftp://user:pass@host/path` is persisted on `MediaItem.fileURL`, matching the known FTP/SMB credential-in-URL trade-off.
- macOS os.Logger may redact `[SFTP]` and prefetch `source=` as `<private>`.
- Citadel pulls SwiftNIO and pins `Wellz26/swift-nio-ssh`; compile time and Swift 6 `Sendable` warnings may increase.

## Progress

- **2026-08-28:** Validation-only placeholder plan created. No dual-platform placeholder confirmation was recorded.
- **2026-08-31:** Scope changed to implementation plus real-source acceptance. Placeholder expected-failure recording is no longer the pass condition.
- **2026-08-31:** Real `SFTPService` landed on Citadel 0.12.1. `swift test --package-path Packages/VanmoCore` passed 82 tests, including `sftp://` KSPlayer selection, path helpers, stream-URL encoding, and DownloadEligibility `.sftp` true.
- **2026-08-31:** Operator compiled and launched both apps from Xcode after Citadel was integrated. iOS Simulator and VanmoMac against `192.168.1.77:22` recorded login, a non-empty listing, KSPlayer plus prefetch play, Files-browser download, and local play of the completed file.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-31 |
| iOS | iPhone 17 Pro simulator, Vanmo Debug, launched from Xcode |
| macOS | Vanmo-macOS Debug, launched from Xcode |
| Source | Password SFTP at `192.168.1.77:22`. Login `login ok`, first listing 21 entries under `/`, later 4 entries under a media folder. |

Credentials, complete authenticated URLs, and private media titles are omitted.

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Add/open SFTP | Pass (operator-entered host/account; Xcode launch) | Pass (operator-entered host/account; Xcode launch) |
| 2. Connect / login | Pass (`login ok host=192.168.1.77 port=22`, `connected to 192.168.1.77:22`) | Pass (`login ok host=192.168.1.77 port=22`, `connected to 192.168.1.77:22`) |
| 3. First listing | Pass (`listed 21 entries under /`, later `listed 4 entries` under a folder) | Pass (`listed 21 entries under /`, later `listed 4 entries` under a folder) |
| 4. Play listed video | Pass (KSPlayer, prefetch `source=sftp`, `readyToPlay` 131s, `playing`) | Pass (`MacKSPlayerEngine`, `[MacPlayerVM] KS using prefetch proxy`, prefetch `source=sftp`, `load complete`) |
| 5. Download and local play | Pass (operator plus `file://` KSPlayer `readyToPlay` 131s, `playing`) | Pass (operator plus `file://` `MacKSPlayerEngine` `load complete`) |
| 6. Sanitized logs | Pass (`hasPassword=yes`; stream URL without userinfo) | Pass (`hasPassword=yes`; prefetch `source=sftp`) |

## Sanitized logs

iOS Simulator:

```
[SFTP] login ok host=192.168.1.77 port=22 user=yingu hasPassword=yes
[SFTP] connected to 192.168.1.77:22
[SFTP] listed 21 entries under /
[SFTP] listed 4 entries under /Users/yingu/Downloads/yinguSMB
[EngineFactory] 选择 KSPlayerEngine (KSPlayer/FFmpeg)
[Prefetch] registered session token=54410074… port=50152 source=sftp
[PlayerVM] using prefetch proxy for remote URL
[KSEngine] readyToPlay, duration: 131.000000s
[PlayerVM] state changed: playing
[KSEngine] load() called, url: file://…
[KSEngine] readyToPlay, duration: 131.000000s
[PlayerVM] state changed: playing
```

VanmoMac:

```
[SFTP] login ok host=192.168.1.77 port=22 user=yingu hasPassword=yes
[SFTP] connected to 192.168.1.77:22
[SFTP] listed 21 entries under /
[SFTP] listed 4 entries under /Users/yingu/Downloads/yinguSMB
[MacEngineFactory] 选择 MacKSPlayerEngine (KSPlayer/FFmpeg)
[Prefetch] registered session token=89448B77… port=54131 source=sftp
[MacPlayerVM] KS using prefetch proxy for remote URL
[MacKSEngine] load complete
[MacKSEngine] load() called, url: file://…
[MacKSEngine] load complete
```

## Open Decisions

None.

## Follow-ups

- SSH public-key and known-hosts / TOFU UI remain out of scope.
- First-version host-key policy is still Citadel `.acceptAnything()`.
- `sftp://user:pass@host/path` on `MediaItem.fileURL` remains the known credential-in-URL trade-off.
- One VanmoMac prefetch close logged `Network.NWError error 57` after a remote play; a later `source=sftp` play and a local `file://` play still completed.
