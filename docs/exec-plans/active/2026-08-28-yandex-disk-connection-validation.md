# Yandex.Disk Connection Validation

**Status:** Blocked  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that Yandex.Disk OAuth login, browse, and play work on both Vanmo iOS and VanmoMac after developer credentials are present.

## Scope

- Credential gate first: Yandex.Disk requires both a client ID and a client secret in `OAuthProviderConfiguration`.
- After the gate, dual-platform login-list-play under the shared rules in [`index.md`](index.md).
- Redirect URI `vanmo://oauth/yandexDisk` must be registered at oauth.yandex.com.

## Out of Scope

- Implementation changes while the login button is disabled
- Committing secrets into the plan or evidence
- Downloads or automatic directory sync

## Prerequisites

- Yandex client ID and client secret filled into `OAuthProviderConfiguration`
- Redirect URI registered as `vanmo://oauth/yandexDisk`
- A Yandex account with at least one Disk video

## Verification

1. Confirm the Files Yandex.Disk login control stays disabled and shows the missing-credential hint while credentials are empty. Do not attempt a fake connect.
2. After the operator supplies ID and secret, confirm `OAuthProviderConfiguration.isConfigured(for: .yandexDisk)` is true.
3. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Complete Yandex login, list a folder, and play one video.
4. Repeat login, list, and play on VanmoMac with `./run_device.sh --macos`.
5. Paste sanitized outcome lines. Do not record tokens or the secret.

The plan stays blocked until step 2 is true. It completes only when both platform runs pass.

## Log prefix

Yandex.Disk has few structured service logs. Record UI success plus the absence of OAuth or HTTP 401/403 errors.

## Risks

- Token exchange fails if only the client ID is set.
- Scope `cloud_api:disk.read` must remain sufficient for list and play.

## Progress

- **2026-08-28:** Validation plan created. Yandex client ID and secret are empty, so login remains disabled. No connect run is authorized.

## Open Decisions

None.
