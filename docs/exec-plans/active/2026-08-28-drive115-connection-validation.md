# 115 Drive Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that the 115 Drive entry remains an official-cloud placeholder on both Vanmo iOS and VanmoMac. A pass means save stays disabled and `UnsupportedOfficialCloudDriveService` is not used as a working source.

## Scope

- Dual-platform Files add-form confirmation under the shared rules in [`index.md`](index.md).
- Expected UI: official-access caption, save disabled (`isOfficialCloudDrive`).
- Expected factory behavior if a connection were created: `connect`, `listDirectory`, and `streamURL` throw `unsupportedProtocol`.

## Out of Scope

- Implementing 115 Open Platform login
- Unofficial APIs
- Expanding `UnsupportedOfficialCloudDriveService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and choose 115 Drive.
2. Confirm the official-access caption and that Save is disabled.
3. Repeat the form observation on VanmoMac with `./run_device.sh --macos`.
4. Record that no listing or play was attempted because save is disabled.

The plan completes only when both platforms show the placeholder form.

## Log prefix

None expected. Connect is not reachable from the current save path.

## Risks

- Editing a leftover historical row could still hit `unsupportedProtocol`; that is not a pass for a working 115 client.

## Progress

- **2026-08-28:** Validation plan created. No dual-platform placeholder confirmation is recorded.

## Open Decisions

None.
