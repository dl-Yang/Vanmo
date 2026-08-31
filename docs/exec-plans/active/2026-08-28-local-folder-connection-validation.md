# Local Folder Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that a local folder can be authorized with a security-scoped bookmark, listed, and played on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files add-connect-list-play using `LocalFolderService`.
- Dual-platform evidence under the shared rules in [`index.md`](index.md).
- iOS `.fileImporter` and macOS `NSOpenPanel` security-scoped bookmark restore.

## Out of Scope

- Implementation changes
- CloudKit bookmark reuse on a second device
- iCloud Drive or third-party File Provider edge cases beyond one chosen folder
- Downloads

## Prerequisites

- A local folder that contains at least one video
- Operator permission through the platform folder picker

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add a local folder.
2. Confirm `LocalFolder connected:` and a visible file listing.
3. Play one listed video. Record the engine path.
4. Repeat add, list, and play on VanmoMac with `./run_device.sh --macos`.
5. Paste sanitized `LocalFolder` lines. Record only the last path component, not the full home directory.

The plan completes only when both platform runs pass.

## Log prefix

`LocalFolder`

## Risks

- A stale bookmark after restart can fail reconnect; this plan records first-session connect.
- Simulator access is limited to folders the simulator can see.
- External File Provider directories may deny `startAccessingSecurityScopedResource`.

## Progress

- **2026-08-28:** Validation plan created. No real local-folder connect, list, or play run is recorded.

## Open Decisions

None.
