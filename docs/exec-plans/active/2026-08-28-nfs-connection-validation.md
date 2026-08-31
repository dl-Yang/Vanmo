# NFS Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that the current NFS entry falls through to `GenericHTTPService` on both Vanmo iOS and VanmoMac. A pass means the documented gap is visible, not that an NFS export listed or played files.

## Scope

- Dual-platform Files add-and-connect confirmation under the shared rules in [`index.md`](index.md).
- Expected factory behavior: logical connect, empty `listDirectory`, no NFS client.

## Out of Scope

- Implementing NFS mount, listing, or streaming
- Kernel or userspace NFS clients
- Expanding `GenericHTTPService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac
- Optional: any host so the form can be saved. A real NFS export is not required.

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add NFS.
2. Save a connection. Confirm the listing is empty and no NFS mount occurs.
3. Repeat the add-and-connect observation on VanmoMac with `./run_device.sh --macos`.
4. Record sanitized notes that the listing was empty and no NFS protocol ran.

The plan completes only when both platforms show the current placeholder behavior.

## Log prefix

None specific. `GenericHTTPService` sets `isConnected` without a dedicated tag.

## Risks

- Operators may confuse this UI entry with macOS Finder NFS mounts.
- Default port `2049` may look ready while listing stays empty.

## Progress

- **2026-08-28:** Validation plan created. No dual-platform placeholder confirmation is recorded.

## Open Decisions

None.
