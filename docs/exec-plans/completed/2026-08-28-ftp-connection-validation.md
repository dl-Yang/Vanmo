# FTP Connection Validation

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-08-30  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that the current FTP entry matches the placeholder `FTPService` behavior on both Vanmo iOS and VanmoMac. A pass means the documented gap is visible, not that a real FTP server listed or played files.

## Scope

- Dual-platform Files add-and-connect confirmation under the shared rules in [`../active/index.md`](../active/index.md).
- Expected factory behavior: `connect` sets `isConnected` and logs a logical connect; `listDirectory` returns `[]`; `streamURL` throws `unsupportedProtocol`.

## Out of Scope

- Implementing FTP listing, streaming, or downloads
- Treating an empty listing as a successful media source
- Expanding `FTPService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac
- Optional: any host/port so the form can be saved. A real FTP server is not required.

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add FTP.
2. Confirm the add form is a host/account form, not an OAuth or official-cloud placeholder.
3. Save a connection. Confirm the listing is empty or play is unsupported. Do not treat this as a working FTP client.
4. Repeat the add-and-connect observation on VanmoMac with `./run_device.sh --macos`.
5. Record sanitized notes that the listing was empty and stream is unsupported.

The plan completes only when both platforms show the current placeholder behavior.

## Log prefix

`FTP connected to` from `VanmoLogger.network`

## Risks

- A future real FTP implementation would invalidate this expected-failure record; archive this plan and open a new real-source plan.
- Operators may assume a saved connection is production-ready because `isConnected` is true. The 2026-08-30 run used a reachable Windows FTP host and still listed nothing, which matches the placeholder `listDirectory` return.

## Progress

- **2026-08-28:** Validation plan created. No dual-platform placeholder confirmation is recorded.
- **2026-08-30:** iOS Simulator Debug launched with `./run_device.sh --simulator` on iPhone 17 Pro. Operator saved an FTP host/account connection to a Windows FTP service at `192.168.31.59:21`. Console recorded `FTP connected to 192.168.31.59` and `[Connections] Scan complete`. The Files browser listing was empty. Play was not reached because no file was listed.
- **2026-08-30:** VanmoMac Debug launched with `./run_device.sh --macos`. Operator saved the same FTP host/account form. Unified logs recorded `<private> connected to <private>` (os.Logger redaction). The Files browser listing was empty. Play was not reached.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-30 |
| iOS | iPhone 17 Pro simulator, Vanmo Debug |
| macOS | Vanmo-macOS Debug |
| Source | Windows FTP at `192.168.31.59:21`. The host was reachable enough to save and logically connect; `FTPService` still returned an empty listing. |

Credentials, complete authenticated URLs, and private media titles are omitted.

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Add FTP and save | Pass (host/account form, port 21) | Pass (host/account form, port 21) |
| 2. Connect | Pass (`FTP connected to 192.168.31.59`) | Pass (`<private> connected to <private>`) |
| 3. First listing | Pass as expected failure (empty directory) | Pass as expected failure (empty directory) |
| 4. Play listed video | Not reached; no listed file | Not reached; no listed file |
| 5. Sanitized logs | Pass | Pass (os.Logger redacted hosts as `<private>`) |

This is not a working FTP client. The empty listing is the documented placeholder gap.

## Sanitized logs

iOS Simulator:

```
[Connections] Connecting to Yingu (ftp://192.168.31.59:21) fullScan=false
FTP connected to 192.168.31.59
FTP connected to 192.168.31.59
[Connections] Scan complete for Yingu
```

VanmoMac:

```
<private> connected to <private>
<private> connected to <private>
```

## Open Decisions

None.

## Follow-ups

- A later real FTP listing/stream implementation should archive this expected-failure record and open a new real-source plan.
- Saved FTP connections report connected while the directory stays empty; do not treat that status as production-ready.
