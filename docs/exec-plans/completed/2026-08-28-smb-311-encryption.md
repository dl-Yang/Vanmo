# SMB 3.1.1 Encryption

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-08-28  
**Plan type:** Implementation plus real-source acceptance  
**Related spec:** [`../../product-specs/smb-311-encryption.md`](../../product-specs/smb-311-encryption.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Connect, browse, and play against an SMB server that requires SMB 3.1.1 AES-GCM encryption, on both Vanmo iOS and VanmoMac.

## Scope

- Pin `SMBClient` to the MIT-licensed [PR #234](https://github.com/kishikawakatsumi/SMBClient/pull/234) commit that adds 3.1.1 preauth contexts and AES-GCM transform wrapping, on top of the already-used `66eafaa` signing revision.
- Advertise SMB 3.1.1 after the existing SMB 2.x / 3.0–3.02 attempts so Mac File Sharing can still negotiate 2.10.
- Keep requiring signing. Accept `encryptData` when the session negotiated 3.1.1 GCM; refuse a clear error when the server requires encryption on 3.0/3.02 CCM only.
- Record sanitized `[Debug][SMB]` lines that show dialect `0x311` and `encrypt=true`.
- Record one iOS and one macOS connect-list-play run against a server with encryption required.

## Out of Scope

- SMB 3.0 / 3.02 AES-CCM encryption
- Multi-channel, persistent handles, or directory leasing
- Changing the File Sharing connect/play record from 2026-08-27
- Replacing KSPlayer or libsmbclient
- Physical-device XCUITest or automated credential entry
- Figma or connection-form visual changes

## Verification

1. `swift test --package-path Packages/VanmoCore` still passes.
2. `./scripts/check-harness-docs.sh` passes after the new spec and plan are indexed.
3. Launch iOS Vanmo with `./run_device.sh --simulator`, add the operator's encryption-required SMB server, and wait for credentials.
4. Confirm login lists a readable share or the configured share. Logs must show `dialect=0x311` and `encrypt=true`.
5. Play one listed video through KSPlayer.
6. Repeat connect, list, and play on VanmoMac with `./run_device.sh --macos`. macOS play must still use the SMB prefetch proxy.
7. Record sanitized `[Debug][SMB]` lines without passwords or complete authenticated URLs.

The plan completes only when both platform encrypted-server runs pass.

## Risks

- PR #234 is unmerged. Vanmo pins the fork revision and should move back to upstream `kishikawakatsumi/SMBClient` when that commit lands on `main`.
- Servers that require encryption but cap the dialect at 3.0/3.02 (AES-CCM) will still fail.
- iOS playback still uses libsmbclient on the `smb://` URL. Browse and macOS prefetch use `SMBService`. A pass on one path does not prove the other.
- A guest-mapped session never encrypts; a server that requires encryption will then drop the tree connect.

## Progress

- **2026-08-28:** Plan and product spec created.
- **2026-08-28:** `SMBClient` is pinned to `thatcube/SMBClient` `d8baadc` (PR #234 on `66eafaa`). `SMBService` now offers 3.1.1 after 2.x and 3.0–3.02, logs `cipher=`, and accepts `encryptData` only on dialect `0x311`. `swift test --package-path Packages/VanmoCore` passed 61 tests. `./scripts/check-harness-docs.sh` passed.
- **2026-08-28:** VanmoMac connected to the encryption-required share at `192.168.1.77`. SMB 2.x and 3.0/3.02 returned `Not Supported`. 3.1.1 negotiated `dialect=0x311`, `cipher=0x0002`, `encrypt=true`, `guest=false`. Listing showed `listShares count=2` and `list path=/MacShare count=6`. A later connect used `share=MacShare`. Operator confirmed play. This paste has no `[Prefetch]` or KSPlayer state lines.
- **2026-08-28:** An iOS device run against the same server recorded the same `0x311` / AES-128-GCM / `encrypt=true` login, `listShares count=2`, `list path=/MacShare count=6`, and a later tree connect to `MacShare`. Operator confirmed play. The iOS verification step named the simulator; the recorded run is a physical device.
- **2026-08-28:** Later Console pastes recorded VanmoMac `[Prefetch] … source=smb` plus `[MacPlayerVM] KS using prefetch proxy`, and an iOS-device KSPlayer `smb://` load with `readyToPlay`.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-28 |
| iOS | Physical-device Vanmo Debug |
| macOS | Vanmo-macOS Debug |
| Source | Encryption-required SMB at `192.168.1.77`, share `MacShare` |
| Dialect | SMB 3.1.1 (`0x311`), cipher `0x0002`, `guest=false`, `encrypt=true`, `clientWillSign=true` |

Credentials, complete authenticated URLs, and media titles are omitted.

## Acceptance Record

| Step | iOS device | VanmoMac |
| --- | --- | --- |
| 1. Add encryption-required server | Pass | Pass |
| 2. Login `0x311` + `encrypt=true` | Pass | Pass |
| 3. First listing | Pass (`listShares count=2`, `list path=/MacShare count=6`) | Pass |
| 4. Play listed video | Pass (KSPlayer `smb://` load, `readyToPlay`, duration present) | Pass (`[Prefetch] … source=smb`, `[MacPlayerVM] KS using prefetch proxy`) |
| 5. Sanitized logs | Pass | Pass |

A later paste recorded the missing engine lines: VanmoMac `[Prefetch] … source=smb` and an iOS-device KSPlayer `smb://` load with `readyToPlay`. The iOS run is a physical device, not the simulator named in Verification step 3.

## Open Decisions

None.

## Follow-ups

- Return the package URL to upstream when PR #234 merges.
- AES-CCM for 3.0/3.02 remains unsupported.
- Encrypted play engine lines were later copied: VanmoMac prefetch `source=smb`, iOS KSPlayer `smb://` load.
