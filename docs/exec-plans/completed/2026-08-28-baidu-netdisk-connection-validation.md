# Baidu Netdisk Connection Validation

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-09-11  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that Baidu Netdisk implicit OAuth login, browse, and play work on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files OAuth login using the configured Baidu AppKey.
- Dual-platform evidence under the shared rules in [`../active/index.md`](../active/index.md).
- List a directory, resolve an ephemeral download `dlink` at play time, and open it with `User-Agent: pan.baidu.com` (follow 302). The public open platform does not expose an own-file M3U8 stream.

## Out of Scope

- Implementation changes
- Recording dlink URLs, access tokens, or AppKey values
- Background token refresh (implicit grant has no refresh token)
- Downloads or automatic directory sync

## Prerequisites

- `OAuthProviderConfiguration.isConfigured(for: .baiduNetdisk)` remains true
- A Baidu Netdisk account with at least one playable video
- Operator completes the simplified-mode OAuth consent

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and choose Baidu Netdisk.
2. Complete account login. Confirm the login control is enabled and no missing-credential hint appears.
3. Confirm a directory listing after connect.
4. Play one listed video. Do not paste dlink query strings.
5. Repeat login, list, and play on VanmoMac with `./run_device.sh --macos`.
6. Paste sanitized outcome lines only.

The plan completes only when both platform runs pass.

## Log prefix

Baidu Netdisk has few structured service logs. Record UI success plus the absence of OAuth or HTTP 401/403 errors. Play path: `official download link, skip prefetch`.

## Risks

- Open-platform quota or audit limits can fail listing or dlink exchange.
- Access tokens expire and require a new login. CloudKit-imported connections have no Keychain token until that device re-authenticates.
- Server-side rate limits can stall play without a connect failure.
- `dlink` is a download URL. Prefetch Range probes time out; play must keep the User-Agent and follow 302. Large files may still start slowly or fail if the CDN does not expose a usable media header.

## Progress

- **2026-08-28:** Validation plan created. No real Baidu Netdisk login, list, or play run is recorded.
- **2026-09-11:** iOS Simulator recorded list plus one sanitized `dlink` play (`official download link, skip prefetch`, KSPlayer `readyToPlay` / `playing`, duration 2002s).
- **2026-09-11:** Vanmo-macOS Debug re-authenticated a CloudKit-imported Baidu connection (`accept reauth ok=true`). Files listed 19 entries with a video. `connectAndScan` inserted 4 local catalog rows. Play used `MacKSPlayerEngine` with `KS official download link, skip prefetch` and `load complete` after `readyToPlay`. No token, dlink query, or private title is recorded.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-09-11 |
| iOS | iPhone 17 Pro simulator, Vanmo Debug |
| macOS | Vanmo-macOS Debug, local OAuth re-login on a CloudKit-imported connection |
| Source | Operator Baidu Netdisk account with at least one playable video |

Credentials, complete authenticated URLs, and private media titles are omitted.

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Open Baidu Netdisk | Pass | Pass (imported connection, then local reauth) |
| 2. Connect / login | Pass | Pass (`accept reauth ok=true`) |
| 3. First listing | Pass | Pass (`accept listed=19 hasVideo=true`) |
| 4. Play listed video | Pass (KSPlayer, `official download link, skip prefetch`, `readyToPlay` 2002s, `playing`) | Pass (`MacKSPlayerEngine`, `KS official download link, skip prefetch`, `load complete`) |
| 5. Sanitized logs | Pass | Pass |

## Sanitized logs

iOS Simulator:

```
official download link, skip prefetch
readyToPlay duration=2002s
state=playing
```

VanmoMac:

```
[Debug][LibraryScan] accept start type=baiduNetdisk actions=play,reauth
[Debug][LibraryScan] accept reauth ok=true error=
Remote scan finished … inserted=4 updated=0 unchanged=0 pruned=0
[Debug][LibraryScan] accept listed=19 hasVideo=true
[MacPlayerVM] KS official download link, skip prefetch
[MacKSEngine] load() called
[MacKSEngine] load complete
```

## Open Decisions

None.
