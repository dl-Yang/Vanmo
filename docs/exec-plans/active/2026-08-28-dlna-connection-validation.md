# DLNA Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that the current DLNA entry falls through to `GenericHTTPService` on both Vanmo iOS and VanmoMac. A pass means the documented gap is visible, not that a DLNA device was discovered or played.

## Scope

- Dual-platform Files add-and-connect confirmation under the shared rules in [`index.md`](index.md).
- Expected factory behavior: logical connect, empty `listDirectory`, no SSDP or UPnP discovery.

## Out of Scope

- Implementing DLNA/UPnP discovery, browse, or streaming
- Bonjour or SSDP listeners
- Expanding `GenericHTTPService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac
- A LAN DLNA renderer or server is not required and must not be treated as in-scope success.

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add DLNA.
2. Confirm there is no automatic device discovery. If a host form can be saved, the listing stays empty.
3. Repeat the observation on VanmoMac with `./run_device.sh --macos`.
4. Record sanitized notes that no SSDP/UPnP discovery ran and the listing was empty.

The plan completes only when both platforms show the current placeholder behavior.

## Log prefix

None specific. `GenericHTTPService` sets `isConnected` without a dedicated tag.

## Risks

- Nearby Infuse or system DLNA devices can create the expectation that Vanmo will list them.
- `requiresAuth` is false for DLNA, so the form may look complete without credentials.

## Progress

- **2026-08-28:** Validation plan created. No dual-platform placeholder confirmation is recorded.

## Open Decisions

None.
