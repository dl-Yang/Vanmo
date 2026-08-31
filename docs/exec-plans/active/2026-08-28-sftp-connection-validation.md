# SFTP Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that the current SFTP entry matches the placeholder `SFTPPlaceholderService` behavior on both Vanmo iOS and VanmoMac. A pass means the documented gap is visible, not that SFTP listed or played files.

## Scope

- Dual-platform Files add-and-connect confirmation under the shared rules in [`index.md`](index.md).
- Expected factory behavior: logical connect, empty `listDirectory`, `streamURL` throws `unsupportedProtocol`.

## Out of Scope

- Implementing SFTP listing, streaming, or downloads
- SSH key or known-hosts support
- Expanding `FTPService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac
- Optional: any host/port so the form can be saved. A real SFTP server is not required.

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add SFTP.
2. Confirm the add form is a host/account form.
3. Save a connection. Confirm the listing is empty or play is unsupported.
4. Repeat the add-and-connect observation on VanmoMac with `./run_device.sh --macos`.
5. Record sanitized notes that the listing was empty and stream is unsupported.

The plan completes only when both platforms show the current placeholder behavior.

## Log prefix

`SFTP connected to` from `VanmoLogger.network`

## Risks

- A future real SFTP implementation would invalidate this expected-failure record.
- Default port `22` may look ready while listing stays empty.

## Progress

- **2026-08-28:** Validation plan created. No dual-platform placeholder confirmation is recorded.

## Open Decisions

None.
