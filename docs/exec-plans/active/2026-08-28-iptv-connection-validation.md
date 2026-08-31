# IPTV Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that an M3U or M3U8 playlist can be added as IPTV, listed as channels, and played on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files add-connect-list-play using `IPTVService`.
- Dual-platform evidence under the shared rules in [`index.md`](index.md).
- Optional EPG fetch when the playlist declares `url-tvg` or `x-tvg-url`. EPG failure does not block a connect-and-play pass.

## Out of Scope

- Implementation changes
- IPTV download (the service throws `unsupportedProtocol`)
- Playlist hosting, EPG completeness, or channel-guide UI fidelity
- Library-scan persistence

## Prerequisites

- A reachable M3U or M3U8 URL entered in host or path
- At least one playable channel in that playlist

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add IPTV with the playlist URL.
2. Confirm the channel list appears after connect.
3. Play one channel. Live streams may have no duration; record playing or buffering, not a finite runtime.
4. If the playlist declares an EPG URL, note any `[IPTV] EPG` warning. A warning is allowed.
5. Repeat add, list, and play on VanmoMac with `./run_device.sh --macos`.
6. Paste sanitized host/path and player-state lines. Do not record the full playlist.

The plan completes only when both platform runs pass.

## Log prefix

`[IPTV]`

## Risks

- Public playlists expire or return HTTP errors.
- TLS or certificate failures look like a Vanmo connect bug.
- Live HLS may never report duration; do not treat that as a play failure.

## Progress

- **2026-08-28:** Validation plan created. No real IPTV connect, list, or play run is recorded.

## Open Decisions

None.
