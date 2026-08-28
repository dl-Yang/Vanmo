# SMB 3.1.1 Encryption

**Product area:** Vanmo and VanmoMac Files  
**Source scope:** Shared `SMBService` login against servers that require SMB 3.1.1 AES-GCM encryption, plus `smb://` playback on that session.

## User-Visible Behavior

A user can add an SMB server that requires packet encryption, sign in with the same username and password used for an unencrypted share, browse readable shares, and play a listed video. The connection must negotiate SMB 3.1.1. Unreadable shares stay hidden. Mac File Sharing without encryption required is unchanged and is covered by [`smb-connections.md`](smb-connections.md).

**Current acceptance status:** Completed.

## Acceptance Criteria

All steps must pass on iOS and on VanmoMac against a server that requires encryption:

1. Add the encryption-required SMB server from Files and save after the operator enters host and credentials.
2. Login succeeds. Sanitized logs show dialect `0x311` and `encrypt=true`.
3. The first listing shows only readable shares, or the configured share when enumeration is unavailable.
4. Playing a listed video uses KSPlayer. On macOS, play still goes through the localhost prefetch proxy.
5. Record the platform, source type, and sanitized `[Debug][SMB]` lines without credentials or complete authenticated URLs.

## Evidence Rules

- Shared unit tests do not prove a real encrypted login.
- An app compile or launch does not establish encryption.
- iOS evidence does not prove macOS, and macOS evidence does not prove iOS.
- A File Sharing or other unencrypted run does not satisfy this specification.
- Mark acceptance completed only after both platform encrypted-server runs pass.
- The 2026-08-28 closeout recorded encrypted login and listing on VanmoMac and an iOS device (`dialect=0x311`, `cipher=0x0002`, `encrypt=true`). A later paste recorded VanmoMac prefetch `source=smb` and an iOS-device KSPlayer `smb://` load. The iOS run is a physical device, not the simulator.

## Related Plan

- [`../exec-plans/completed/2026-08-28-smb-311-encryption.md`](../exec-plans/completed/2026-08-28-smb-311-encryption.md)
