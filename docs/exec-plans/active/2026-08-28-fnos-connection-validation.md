# fnOS Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that an fnOS NAS can be added as the fnOS connection type over WebDAV, listed, and played on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files add-connect-list-play using `WebDAVService(type: .fnos)`.
- Dual-platform evidence under the shared rules in [`index.md`](index.md).
- Product-specific defaults: LAN HTTP `5005`, HTTPS `5006`, empty path.

## Out of Scope

- Implementation changes
- Using the SMB connection type against fnOS (covered by completed SMB plans)
- FN Connect remote-access hardening beyond noting port `443`
- Downloads or library-scan persistence

## Prerequisites

- An fnOS NAS with WebDAV enabled and folder permission granted
- Host, port, HTTPS flag, and account entered by the operator
- Path left empty unless the operator records a subdirectory

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add fnOS.
2. Confirm `[WebDAV] PROPFIND probe` returns 207 or 200, then `[WebDAV] Connected`.
3. Confirm `[WebDAV] Found N entries` and a visible directory listing.
4. Play one listed video. Record the engine path.
5. Repeat add, connect, list, and play on VanmoMac with `./run_device.sh --macos`.
6. Paste sanitized `[WebDAV]` lines. A 404 should say the path is usually empty.

The plan completes only when both platform runs pass.

## Log prefix

`[WebDAV]`

## Risks

- Choosing SMB instead of fnOS does not count as this plan's evidence.
- HTTPS with port `5005` is a common form error; the UI hints `5006`.
- FN Connect hostnames typically use port `443`, not the LAN WebDAV ports.

## Progress

- **2026-08-28:** Validation plan created. No real fnOS WebDAV connect, list, or play run is recorded.

## Open Decisions

None.
