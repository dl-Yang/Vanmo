# OneDrive Connection Validation

**Status:** Blocked  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that OneDrive OAuth login, browse, and play work on both Vanmo iOS and VanmoMac after developer credentials are present.

## Scope

- Credential gate first: `OAuthProviderConfiguration.clientID(for: .oneDrive)` must be a Microsoft Entra application ID.
- After the gate, the same dual-platform login-list-play path as Google Drive, using PKCE and no client secret.
- Redirect URI `vanmo://oauth/oneDrive` must be registered in the Entra app.

## Out of Scope

- Implementation changes while the login button is disabled
- Inventing or committing a placeholder client ID
- Downloads or automatic directory sync

## Prerequisites

- An Entra application (client) ID filled into `OAuthProviderConfiguration`
- Redirect URI registered as `vanmo://oauth/oneDrive`
- A Microsoft account with at least one OneDrive video

## Verification

1. Confirm the Files OneDrive login control stays disabled and shows the missing-credential hint while the client ID is empty. Do not attempt a fake connect.
2. After the operator supplies a client ID, confirm `OAuthProviderConfiguration.isConfigured(for: .oneDrive)` is true.
3. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Complete OneDrive login, list a folder, and play one video.
4. Repeat login, list, and play on VanmoMac with `./run_device.sh --macos`.
5. Paste sanitized outcome lines. Do not record tokens.

The plan stays blocked until step 2 is true. It completes only when both platform runs pass.

## Log prefix

OneDrive has few structured service logs. Record UI success plus the absence of OAuth or HTTP 401/403 errors.

## Risks

- Personal and work/school tenants can require different admin consent.
- An unregistered `vanmo://oauth/oneDrive` redirect fails the callback.

## Progress

- **2026-08-28:** Validation plan created. OneDrive client ID is empty, so login remains disabled. No connect run is authorized.

## Open Decisions

None.
