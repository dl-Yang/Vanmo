# FTP Real-Source Connect, List, Play, and Download

**Status:** Completed  
**Created:** 2026-08-30  
**Completed:** 2026-08-31  
**Plan type:** Implementation plus real-source acceptance  
**Related spec:** [`../../product-specs/ftp-connections.md`](../../product-specs/ftp-connections.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Replace the placeholder FTP entry with a real RFC 959 client so Files can connect to a Windows FTP server, list a non-empty directory, play a listed video, and download that file on both Vanmo iOS and VanmoMac.

## Scope

- Shared `FTPService` connect, `MLSD`/`LIST`, `ftp://` stream URL, REST/RETR range reads, and resume download.
- Prefetch `source=ftp` on both platforms so KSPlayer loads the localhost proxy, not raw `ftp://`.
- Dual-platform evidence under the shared rules in [`../active/index.md`](../active/index.md).
- Credentials stay operator-entered in the host/account form and Keychain.

## Out of Scope

- SFTP, FTPS/TLS, and active-mode PORT
- Treating the earlier placeholder plan as real-source evidence
- Expanding other placeholder protocols

## Prerequisites

- Reachable Windows FTP (the passing run used `192.168.1.77:21`; an earlier attempt used `192.168.31.59:21`)
- Operator-entered username and password
- At least one playable video in a listed directory

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add FTP.
2. Confirm `[FTP] login ok` and `[FTP] connected to`.
3. Confirm the first listing is non-empty (`[FTP] listed N entries`).
4. Play one listed video. Record KSPlayer plus prefetch `source=ftp`.
5. Download the same file from Files and play the completed local file.
6. Repeat add, connect, list, play, and download on VanmoMac with `./run_device.sh --macos`.
7. Paste sanitized `[FTP]` and `[Prefetch]` lines. Do not record passwords.

The plan completes only when both platform runs pass.

## Log prefix

`[FTP]`

## Risks

- Windows PASV may advertise `127.0.0.1`; the client rewrites loopback to the control host.
- Some servers reject `MLSD` and require `LIST`.
- macOS Local Network TCC can block LAN FTP even when `NSLocalNetworkUsageDescription` is present.
- `ftp://user:pass@host/path` is persisted on `MediaItem.fileURL`, matching the known SMB credential-in-URL trade-off.
- Microsoft IIS can return `530 User cannot log in` after `PASS` when the account is denied, the FTP home directory is missing, or the saved password is wrong. That is no longer treated as a successful empty listing.
- os.Logger on macOS redacts `[FTP]` command text and prefetch `source=` as `<private>`.

## Progress

- **2026-08-30:** Real `FTPService` and `FTPClient` landed in VanmoCore. SFTP remains `SFTPPlaceholderService`.
- **2026-08-30:** `swift test --package-path Packages/VanmoCore` passed 74 tests, including LIST/MLSD/PASV/EPSV parse, `ftp://` KSPlayer selection, and DownloadEligibility `.ftp` true / `.sftp` false. `./scripts/check-harness-docs.sh` passed.
- **2026-08-30:** iOS Simulator and VanmoMac against `192.168.31.59:21` reached a real RFC 959 login and recorded `530` after `PASS <redacted>`. Listing, play, and download were not reached.
- **2026-08-31:** Client treats failed `CWD /` as IIS user-isolation home, retries `RETR` with the filename after `CWD` to the parent, and reconnects a dropped control channel. `swift test --package-path Packages/VanmoCore` passed 75 tests.
- **2026-08-31:** Operator-entered login against `192.168.1.77:21` passed on iOS Simulator and VanmoMac: `[FTP] ← 230`, first listing 468 entries, a subdirectory listing of 4, KSPlayer plus prefetch play, Files-browser download, and local play of the completed file.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-31 |
| iOS | iPhone 17 Pro simulator, Vanmo Debug |
| macOS | Vanmo-macOS Debug |
| Source | FileZilla / Windows FTP at `192.168.1.77:21`. Login `230`, `MLSD` + `EPSV`, `SIZE` `213`, `REST` `350`. |

Credentials, complete authenticated URLs, and private media titles are omitted.

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Add/open FTP | Pass (operator-entered host/account `MacFtp`) | Pass (operator-entered host/account) |
| 2. Connect / login | Pass (`230 Login successful.`, `login ok host=192.168.1.77 port=21`) | Pass (`[FTP] ← 230`, `login ok` port=21) |
| 3. First listing | Pass (`listed 468 entries under /`, then `listed 4 entries` under a folder) | Pass (`listed 468 entries`, then `listed 4 entries`) |
| 4. Play listed video | Pass (KSPlayer, prefetch `source=ftp`, `readyToPlay` 131s, `playing`) | Pass (`MacKSPlayerEngine`, `[MacPlayerVM] KS using prefetch proxy`, FTP `SIZE`/`RETR` after register) |
| 5. Download and local play | Pass (operator) | Pass (operator) |
| 6. Sanitized logs | Pass (`PASS <redacted>`) | Pass (os.Logger `<private>`) |

## Sanitized logs

iOS Simulator:

```
[FTP] → USER test
[FTP] ← 331 Please, specify the password.
[FTP] → PASS <redacted>
[FTP] ← 230 Login successful.
[FTP] login ok host=192.168.1.77 port=21 user=test hasPassword=yes
[FTP] connected to 192.168.1.77:21
[FTP] listed 468 entries under /
[FTP] listed 4 entries under /yinguSMB
[EngineFactory] 选择 KSPlayerEngine (KSPlayer/FFmpeg)
[Prefetch] registered session token=E1F7F8DD… port=55961 source=ftp
[KSEngine] readyToPlay, duration: 131.000000s
[PlayerVM] state changed: playing
```

VanmoMac:

```
[FTP] ← 230 <private>
[FTP] login ok host=<private> port=21 user=<private> hasPassword=<private>
[FTP] connected to <private>:21
[FTP] listed 468 entries under <private>
[FTP] listed 4 entries under <private>
[MacEngineFactory] 选择 MacKSPlayerEngine (KSPlayer/FFmpeg)
[Prefetch] listener ready on port 54130
[Prefetch] registered session token=<private>… port=54130 source=<private>
[MacPlayerVM] KS using prefetch proxy for remote URL
[FTP] ← 213 <private>
[FTP] ← 150 <private>
```

## Open Decisions

None.

## Follow-ups

- SFTP is a separate Citadel client; 2026-08-31 dual-platform real-source evidence is recorded under [`2026-08-28-sftp-connection-validation.md`](2026-08-28-sftp-connection-validation.md).
- macOS os.Logger privacy redacts FTP command text and prefetch `source=`; iOS Console remains the clearer evidence path.
- `ftp://user:pass@host/path` on `MediaItem.fileURL` remains the known credential-in-URL trade-off.
