# FTP Connections

**Product area:** Vanmo and VanmoMac Files  
**Source scope:** Shared `FTPService` connect, browse, KSPlayer prefetch playback, and Files-browser download on iOS and macOS.

## User-Visible Behavior

A user can add an FTP server from the Files tab using a host/account form (name, host, port default `21`, optional path, username, password). Credentials are stored in Keychain. After save, Vanmo logs in over RFC 959 FTP and lists the configured path or `/`.

The listing shows directories and files returned by `MLSD` or `LIST`. Playing a listed video uses KSPlayer through the localhost prefetch proxy (`source=ftp`). Files can enqueue a supported video for download; the completed file plays locally.

SFTP is specified separately in [`sftp-connections.md`](sftp-connections.md) and is not covered here.

**Current acceptance status:** Completed. 2026-08-31 iOS Simulator and VanmoMac runs logged `[FTP] ← 230`, listed 468 then 4 entries, played through KSPlayer plus prefetch (`source=ftp` on iOS; macOS prefetch proxy with FTP `SIZE`/`RETR`), and the operator completed a Files-browser download plus local play on both platforms.

## Acceptance Criteria

All steps must pass on iOS Simulator and on VanmoMac in recorded manual runs:

1. Add FTP from Files and save after the operator enters host and credentials.
2. Login succeeds against a reachable FTP server (the recorded passing run used `192.168.1.77:21`).
3. The first listing is non-empty.
4. Playing a listed video uses KSPlayer with prefetch `source=ftp`.
5. Files-browser download of that video completes and the local file plays.
6. Record the platform and sanitized `[FTP]` / `[Prefetch]` lines without passwords or complete authenticated URLs.

## Evidence Rules

- Shared unit tests prove LIST/MLSD/PASV helpers, `ftp://` engine selection, and download eligibility only.
- An app compile or launch does not establish a real FTP login.
- iOS evidence does not prove macOS, and macOS evidence does not prove iOS.
- Mark acceptance completed only after both platform runs pass.

## Related Plan

- [`../exec-plans/completed/2026-08-30-ftp-real-source.md`](../exec-plans/completed/2026-08-30-ftp-real-source.md)
