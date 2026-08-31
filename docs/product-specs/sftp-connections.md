# SFTP Connections

**Product area:** Vanmo and VanmoMac Files  
**Source scope:** Shared `SFTPService` connect, browse, KSPlayer prefetch playback, and Files-browser download on iOS and macOS.

## User-Visible Behavior

A user can add an SFTP server from the Files tab using a host/account form (name, host, port default `22`, optional path, username, password). Credentials are stored in Keychain. After save, Vanmo logs in over SSH/SFTP and lists the configured path or `/`.

The listing shows directories and files returned by the SFTP directory listing. Playing a listed video uses KSPlayer through the localhost prefetch proxy (`source=sftp`). Files can enqueue a supported video for download; the completed file plays locally.

FTP remains a separate protocol and is not covered here.

**Current acceptance status:** Completed. 2026-08-31 iOS Simulator and VanmoMac runs logged `[SFTP] login ok` at `192.168.1.77:22`, listed 21 then 4 entries, played through KSPlayer plus prefetch (`source=sftp`), and the operator completed a Files-browser download plus local play on both platforms.

## Acceptance Criteria

All steps must pass on iOS Simulator and on VanmoMac in recorded manual runs:

1. Add SFTP from Files and save after the operator enters host and credentials.
2. Login succeeds against a reachable password-authenticated SFTP server.
3. The first listing is non-empty.
4. Playing a listed video uses KSPlayer with prefetch `source=sftp`.
5. Files-browser download of that video completes and the local file plays.
6. Record the platform and sanitized `[SFTP]` / `[Prefetch]` lines without passwords or complete authenticated URLs.

## Evidence Rules

- Shared unit tests prove `sftp://` engine selection, path helpers, stream-URL encoding, and download eligibility only.
- An app compile or launch does not establish a real SFTP login.
- iOS evidence does not prove macOS, and macOS evidence does not prove iOS.
- Mark acceptance completed only after both platform runs pass.

## Related Plan

- [`../exec-plans/completed/2026-08-28-sftp-connection-validation.md`](../exec-plans/completed/2026-08-28-sftp-connection-validation.md)
