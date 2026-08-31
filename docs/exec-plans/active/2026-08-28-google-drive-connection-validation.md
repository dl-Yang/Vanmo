# Google Drive Connection Validation

**Status:** Not started  
**Created:** 2026-08-28  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that Google Drive OAuth login, browse, and play work on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files OAuth login using the already-configured Google iOS client in `OAuthProviderConfiguration`.
- Dual-platform evidence under the shared rules in [`index.md`](index.md).
- Browse after login, then play one video through `alt=media` with PrefetchProxy Bearer headers.

## Out of Scope

- Implementation changes
- Writing client IDs, tokens, or refresh material into this plan
- Shared-drive ACL edge cases beyond one readable folder
- Downloads or automatic directory sync (`requiresManualDirectorySync` is true)

## Prerequisites

- `OAuthProviderConfiguration.isConfigured(for: .googleDrive)` remains true
- A Google account with at least one Drive video the operator can play
- Matching `Info.plist` Google URL scheme if the client ID changes

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and choose Google Drive.
2. Complete account login. Confirm the login control is enabled and no missing-credential hint appears.
3. Confirm a folder listing after connect. Choose a directory if the UI requires manual sync.
4. Play one listed video. Confirm no 401/403 in Console. Do not record the Bearer token.
5. Repeat login, list, and play on VanmoMac with `./run_device.sh --macos`.
6. Paste sanitized outcome lines only.

The plan completes only when both platform runs pass.

## Log prefix

Google Drive has few structured service logs. Record UI success plus the absence of OAuth or HTTP 401/403 errors.

## Risks

- A Client ID change without updating the Google URL scheme breaks the callback.
- Read-only Drive scope is enough for play; write attempts are out of scope.
- Simulator OAuth may require a real Google account and network.

## Progress

- **2026-08-28:** Validation plan created. No real Google Drive login, list, or play run is recorded.

## Open Decisions

None.
