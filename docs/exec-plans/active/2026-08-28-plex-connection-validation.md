# Plex Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that a real Plex Media Server can be added, authenticated through plex.tv, listed, and played on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files add-connect-list-play against one PMS using `PlexService`.
- Dual-platform evidence under the shared rules in [`index.md`](index.md).
- Sanitized `[Plex]` console lines for plex.tv sign-in, PMS connect, and `/library/sections` listing.

## Out of Scope

- Implementation changes
- Downloads, library-scan persistence, or playback-progress reporting
- Plex two-factor recovery, remote relay, or shared-server invites
- Physical-device XCUITest or automated credential entry

## Prerequisites

- A Plex account email and password
- A reachable PMS (default port `32400`)
- Operator-entered host, HTTPS flag, and credentials; do not store them in this plan

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add Plex.
2. Confirm `[Plex] Authenticating to plex.tv` then `[Plex] Connected to PMS`.
3. Confirm `[Plex] Listing: /library/sections` and a visible library list. Plex auto-syncs after connect (`requiresManualDirectorySync` is false).
4. Play one listed video. Record the engine path without the `X-Plex-Token` query value.
5. Repeat add, connect, list, and play on VanmoMac with `./run_device.sh --macos`.
6. Paste sanitized `[Plex]` lines only.

The plan completes only when both platform runs pass.

## Log prefix

`[Plex]`

## Risks

- Plex two-factor or app-specific password can fail plex.tv sign-in.
- Enabling HTTPS against an HTTP-only PMS produces a false connection failure.
- Remote Plex relay is unverified and is not required for this plan.

## Progress

- **2026-08-28:** Validation plan created. No real Plex connect, list, or play run is recorded.

## Open Decisions

None.
