# Baidu Netdisk Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that Baidu Netdisk implicit OAuth login, browse, and play work on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files OAuth login using the configured Baidu AppKey.
- Dual-platform evidence under the shared rules in [`index.md`](index.md).
- List a directory, resolve an ephemeral dlink at play time, and stream with `User-Agent: pan.baidu.com`.

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

Baidu Netdisk has few structured service logs. Record UI success plus the absence of OAuth or HTTP 401/403 errors.

## Risks

- Open-platform quota or audit limits can fail listing or dlink exchange.
- Access tokens expire and require a new login.
- Server-side rate limits can stall play without a connect failure.

## Progress

- **2026-08-28:** Validation plan created. No real Baidu Netdisk login, list, or play run is recorded.

## Open Decisions

None.
