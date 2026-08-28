# SMB Connection Fix

**Status:** Completed  
**Created:** 2026-08-27  
**Completed:** 2026-08-27  
**Plan type:** Implementation plus real-source acceptance  
**Related spec:** [`../../product-specs/smb-connections.md`](../../product-specs/smb-connections.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Make a readable SMB server connectable from both Vanmo iOS and VanmoMac, and hide shares or directories the signed-in account cannot read.

## Scope

- Normalize SMB host, port, share, and `DOMAIN\user` / `user@WORKGROUP` input in `VanmoCore`.
- Negotiate SMB 2.02, 2.10, 3.0, and 3.02 instead of SMB 2.x only.
- Fall back to a configured share when share enumeration fails.
- Probe share readability and hide `ACCESS_DENIED` entries.
- Route `smb://` playback to KSPlayer. iOS plays the URL directly; macOS serves it through the localhost prefetch proxy with `SMBService` range reads.
- Record one iOS Simulator and one macOS real-source connect-and-play run.

## Out of Scope

- SMB download resume or library scan changes
- A new Domain form field
- Replacing `SMBClient` or adding SMB 1.0 / SMB 3.1.1 encryption
- Physical-device XCUITest or automated credential entry
- Figma or connection-form visual changes

## Verification

1. `swift test --package-path Packages/VanmoCore` includes the new SMB unit tests.
2. Launch iOS Vanmo with `./run_device.sh --simulator`, open Files, add an SMB server, and wait for the operator to enter credentials.
3. Confirm the simulator lists only readable shares or the configured share.
4. Play one listed video and confirm the engine is KSPlayer. Seeking should not stall on a corrupt-packet error.
5. Repeat the same add-and-connect flow on VanmoMac with `./run_device.sh --macos`.
6. Record sanitized `[Debug][SMB]` console lines without passwords or complete authenticated URLs.

The plan completes only when both platform connect runs pass.

## Risks

- Servers that require SMB 3.1.1 preauth or mandatory encryption can still fail.
- The iOS Simulator must share a LAN with the NAS; `localhost` is the simulator itself.
- Probing each share adds one tree-connect round trip.
- Share enumeration can be disabled even after a successful login.
- macOS File Sharing needs the account checked under File Sharing → Options → Windows File Sharing so NTLM clients can open the share.
- Direct libsmbclient seek on macOS can return partial NAL units; macOS playback therefore uses the prefetch proxy.

## Progress

- **2026-08-27:** Plan and product spec created. Implementation and real-source runs have not been recorded.
- **2026-08-27:** Shared SMB host/account normalization, SMB 2.02–3.02 negotiate, share-enumeration fallback, and unreadable-share hiding landed in `VanmoCore`.
- **2026-08-27:** Operator logs showed `negotiate ok` and `sessionSetup ok`, then `listShares failed status=Access Denied` with no configured share. Login is not the failure.
- **2026-08-27:** The server is this Mac's File Sharing (`192.168.1.77`). Tree connect to `yinguSMB` returned Access Denied until SMBClient was pinned to `66eafaa` and login required signing.
- **2026-08-27:** iOS Simulator connect, list, and KSPlayer play passed. macOS connect and list passed; macOS libsmbclient seek failed with `partial file` / invalid NAL size. Follow-up served macOS playback through the prefetch proxy.
- **2026-08-27:** macOS play passed with `[Prefetch] registered session … source=smb` and `[MacPlayerVM] KS using prefetch proxy for remote URL`. Required evidence for both platforms is recorded.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-27 |
| iOS | iPhone 17 Pro simulator, Vanmo Debug |
| macOS | Vanmo-macOS Debug |
| Source | This Mac File Sharing at `192.168.1.77`, share `yinguSMB` |
| Dialect | SMB 2.10 (`0x210`), `guest=false`, `encrypt=false`, `clientWillSign=true` |

Credentials, complete authenticated URLs, and media titles are omitted.

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Add SMB server and save | Pass | Pass |
| 2. Login | Pass (`sessionSetup ok`, not guest) | Pass |
| 3. First listing | Pass (`list path=/yinguSMB count=3`) | Pass |
| 4. Play listed video | Pass (KSPlayer, duration 131s, `playing` then `ended`) | Pass (prefetch `source=smb`, KSPlayer) |
| 5. Sanitized logs | Pass | Pass |

Seek on macOS was not separately logged. Closure uses the prefetch-path lines plus operator confirmation that the macOS run passed; this record does not mark seek as independently evidenced.

## Open Decisions

None.

## Follow-ups

- SMB download resume remains unverified.
- Physical-device XCUITest was not part of this plan.
- Servers that require SMB 3.1.1 encryption are tracked in the later 2026-08-28 encryption plan.
- macOS seek was not separately logged after the prefetch-proxy change.
