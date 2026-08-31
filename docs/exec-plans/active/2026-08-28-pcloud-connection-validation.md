# pCloud Connection Validation

**Status:** Blocked  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that pCloud OAuth login, browse, and play work on both Vanmo iOS and VanmoMac after developer credentials are present.

## Scope

- Credential gate first: pCloud requires both a client ID and a client secret in `OAuthProviderConfiguration`.
- After the gate, dual-platform login-list-play under the shared rules in [`index.md`](index.md).
- Redirect URI `vanmo://oauth/pCloudDrive` must be registered. The service auto-selects the US or EU data center.

## Out of Scope

- Implementation changes while the login button is disabled
- Committing secrets into the plan or evidence
- Downloads or automatic directory sync

## Prerequisites

- pCloud client ID and client secret filled into `OAuthProviderConfiguration`
- Redirect URI registered as `vanmo://oauth/pCloudDrive`
- A pCloud account with at least one playable video

## Verification

1. Confirm the Files pCloud login control stays disabled and shows the missing-credential hint while credentials are empty. Do not attempt a fake connect.
2. After the operator supplies ID and secret, confirm `OAuthProviderConfiguration.isConfigured(for: .pCloudDrive)` is true.
3. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Complete pCloud login, list a folder, and play one video.
4. Repeat login, list, and play on VanmoMac with `./run_device.sh --macos`.
5. Paste sanitized outcome lines. Do not record tokens or the secret.

The plan stays blocked until step 2 is true. It completes only when both platform runs pass.

## Log prefix

pCloud has few structured service logs. Record UI success plus the absence of OAuth or HTTP 401/403 errors.

## Risks

- Token exchange fails if only the client ID is set.
- US versus EU region mismatch can list nothing after a successful login.

## Progress

- **2026-08-28:** Validation plan created. pCloud client ID and secret are empty, so login remains disabled. No connect run is authorized.

## Open Decisions

None.
