# SMB Connections

**Product area:** Vanmo and VanmoMac Files  
**Source scope:** Shared `SMBService` connect and browse behavior on iOS and macOS, plus `smb://` playback routing.

## User-Visible Behavior

A user can add an SMB server from the Files tab, sign in with a username and password, and browse readable shares. Host fields may be an IP, hostname, `smb://` URL, or UNC path. A username may include `DOMAIN\user` or `user@WORKGROUP`. Empty username and password are treated as guest. macOS File Sharing also requires the account to be checked under File Sharing → Options → Windows File Sharing so NTLM authentication can open the share.

The root listing shows only shares the account can open. Hidden, system, IPC, and administrative `*$` shares stay hidden. If a directory or share is not readable, it is omitted instead of failing the whole connection. When the connection has a configured path, browsing starts at that share.

**Current acceptance status:** Completed.

## Acceptance Criteria

All steps must pass on iOS Simulator and on VanmoMac in recorded manual runs:

1. Add an SMB server from Files and save after the operator enters host and credentials.
2. Login succeeds against a server that Infuse can already reach.
3. The first listing shows only readable shares, or the configured share when enumeration is unavailable.
4. Opening a readable share lists its visible files and folders. Playing a listed video uses KSPlayer. On macOS, seeks go through the localhost prefetch proxy as byte-range reads.
5. Unreadable shares and directories do not appear as openable items.
6. Record the platform, source type, and sanitized `[Debug][SMB]` lines without credentials or complete authenticated URLs.

## Evidence Rules

- Shared unit tests prove host, account, and visibility helpers only.
- An app compile or launch does not establish a real SMB login.
- iOS evidence does not prove macOS, and macOS evidence does not prove iOS.
- Mark acceptance completed only after both platform runs pass.
- The 2026-08-27 closeout recorded connect, list, and play-path logs on both platforms. macOS seek through the prefetch proxy was not separately logged.

## Related Plan

- [`../exec-plans/completed/2026-08-27-smb-connection-fix.md`](../exec-plans/completed/2026-08-27-smb-connection-fix.md)
