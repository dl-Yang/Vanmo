# 115 Drive Open Platform Integration

**Status:** Blocked  
**Created:** 2026-10-21  
**Plan type:** Implementation, followed by real-source validation  
**Related architecture authority:** [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md)  
**Related security authority:** [`../../SECURITY.md`](../../SECURITY.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Replace the 115 official-cloud placeholder with a real client built only on the official 115 Open Platform API: QR-code authorization, directory listing, stream resolution, and download, on both Vanmo iOS and VanmoMac. A pass means a signed-in 115 account lists a real folder and plays one video, with credentials kept in Keychain and no unofficial endpoint in the code path.

The 2026-10-21 placeholder validation ([`../completed/2026-08-28-drive115-connection-validation.md`](../completed/2026-08-28-drive115-connection-validation.md)) is the baseline this plan supersedes. Until this plan lands, `.drive115` keeps the disabled Save control.

## Blocker

An approved 115 Open Platform application is required before any code can be verified:

- 115 Open Platform developer application in the approved state, yielding an application ID (public client) and, if the platform requires it, a client secret.
- A 115 account that can authorize the application and hold at least one folder with a playable video.
- Confirmation from the 115 console of the authorized redirect/device-code settings, requested scopes, and API rate limits.

Without the application ID the login control stays disabled and no connect, listing, or play can be recorded. Code may be written and unit-tested behind that gate, but the plan cannot leave `Blocked` or reach completion without it.

Official references to pin before implementation:

- 115 Open Platform portal: <https://open.115.com>
- Official authorization document (QR / PKCE mode): <https://www.yuque.com/115yun/open/shtpzfhewv5nag11>
- Third-party integration notes used only for account and token constraints: <https://alist.iots.vip/guide/drivers/115_open.html>

Endpoint hosts, parameter names, and scope strings must be taken from the official documents at implementation time. The shapes below are design intent, not verified API facts.

## Current State (2026-10-21)

- `RemoteServiceFactory.create(for: .drive115)` returns `UnsupportedOfficialCloudDriveService`, whose `connect`, `listDirectory`, `streamURL`, and `download` all throw `NetworkError.unsupportedProtocol` ([`ServiceFactory.swift`](../../../Packages/VanmoCore/Sources/VanmoCore/Network/ServiceFactory.swift)).
- `.drive115` is grouped with `.removedOfficialCloudDrive`, `.quarkDrive`, and `.mega` by `isOfficialCloudDrive`, which drives the disabled Save in both add forms and the placeholder captions.
- `supportsOAuthLogin` currently means authorization-code or implicit browser flows (`isOAuthCloudDrive` / `isImplicitOAuthCloudDrive`); there is no device-code/QR flow.
- `OAuthProviderConfiguration` holds public client IDs per provider and a `isConfigured(for:)` gate that disables the login control.
- `OAuthCoordinator` handles `ASWebAuthenticationSession` authorization-code and implicit flows, access-token refresh, and Keychain persistence through `OAuthCredentialStore`.
- OAuth-backed cloud drives share a service shape: `connect` loads a valid access token, `listDirectory` pages the provider listing, `streamURL` resolves a short-lived download URL, and playback reuses `StreamingRequestHeaders` plus the prefetch proxy (Baidu Netdisk is the closest precedent).

## Scope

1. Capability model: give `.drive115` its own capability flag (device-code/QR OAuth), remove it from `isOfficialCloudDrive`, extend `supportsOAuthLogin`, and update every switch that relies on those flags.
2. Configuration: add the 115 application ID to `OAuthProviderConfiguration`, including its `isConfigured` gate and the developer-console row in that file's documentation table. Public client IDs live in source like the existing providers; any client secret must come from Keychain or the console, never from source or fixtures.
3. Authorization: add a device-code/QR authorization flow to `OAuthCoordinator` (request code, render QR, poll for approval with cancellation and timeout, exchange for tokens) plus the 115 refresh path, including refresh-token rotation.
4. Service: add `Drive115Service` in `Packages/VanmoCore/Sources/VanmoCore/Network/CloudDrive/` implementing `RemoteFileService`.
5. UI: replace the placeholder form with the QR/login section on both platforms, including cancelled, expired, and failed states.
6. Documentation: update `ARCHITECTURE.md` (protocol capability and token flow), `docs/SECURITY.md` (token rotation and QR handling), and add a product spec for the user-visible 115 behavior.

## Out of Scope

- Unofficial 115 APIs, cookie scraping, or web-session tokens
- Upload, share-link, offline-download-task, and account-management APIs
- Multi-account selection or per-folder connection editing beyond the existing path field
- Changing CloudKit sync or SwiftData schema; credentials stay in Keychain only
- Expanding `.quarkDrive`, `.mega`, or `.removedOfficialCloudDrive`
- Downloads or library-scan persistence behavior beyond what the existing shared pipeline already provides

## Design Intent

### Capability and factory

- `ConnectionType.isDeviceCodeOAuthCloudDrive` returns `true` for `.drive115`; `isOfficialCloudDrive` drops `.drive115`.
- `supportsOAuthLogin` becomes `isOAuthCloudDrive || isImplicitOAuthCloudDrive || isDeviceCodeOAuthCloudDrive`, so both add forms route `.drive115` to a dedicated login section instead of the host form.
- `RemoteServiceFactory.create(for: .drive115)` returns `Drive115Service`. `UnsupportedOfficialCloudDriveService` keeps serving `.removedOfficialCloudDrive`, `.quarkDrive`, and `.mega`.
- Audit every `isOfficialCloudDrive` / `isOAuthCloudDrive` / `supportsOAuthLogin` switch (`ConnectionModels`, `DownloadModels`, `BrowserViewModel`, `MacConnectionsViewModel`, both add forms, sidebar and group models) and update the ones that mean "cannot authenticate yet".

### Authorization

- New `OAuthCoordinator.authenticateDeviceCode(type:) async throws -> OAuthCredential` sibling to the existing flows: request the authorization/QR code, publish the QR payload to the UI, poll until approved or expired, then exchange for `access_token` + `refresh_token` and save through `OAuthCredentialStore`.
- The UI needs a QR payload plus a status stream, so the coordinator exposes a small observable state (`pending(qrPayload:)`, `approved`, `expired`, `failed`) rather than only a final credential.
- 115 rotates the refresh token. `refresh` must persist the rotated value and keep the stored access token valid on retry; a failed rotation must surface a re-login prompt instead of looping.
- Cancellation must cancel the poll task and drop the pending credential.

### Service

- `connect(config:)`: load the valid access token for the connection (refreshing when expired), then mark connected.
- `listDirectory(path:)`: 115 lists by file ID rather than by path, so the service keeps a path→ID map seeded from the connection root and populated as directories are listed; `RemoteFile.stableId` carries the provider file ID and `path` stays the human path used by the browser. Pagination and empty directories must be covered.
- `streamURL(for:)`: resolve the short-lived download URL at play time, then hand it to the existing playback path with the headers 115 requires (application User-Agent and any required accept/referer header) through `StreamingRequestHeaders`. Do not persist resolved URLs or tokens in logs.
- `download(file:to:progress:)`: range-based download with cancellation, safe-name handling, and provider error mapping.
- Error mapping: `401`/expired token → re-auth surfaced to the browser; quota/rate-limit responses → a dedicated user message; provider error codes → `NetworkError` cases consistent with the other cloud drives.

### UI

- iOS `AddConnectionView`: `.drive115` shows a login section with the QR image/text, a "waiting for scan" state, cancel, and a re-login action for existing connections; Save stays disabled until a credential exists, then creates the connection exactly like the other OAuth drives.
- `MacAddConnectionView`: the same states in the macOS add-connection sheet, with the Figma-sourced layout rules in [`../../FRONTEND.md`](../../FRONTEND.md). QR rendering follows the existing design tokens; a missing Figma frame for this sheet must be designed first per the frontend rules.
- Captions and empty states stop claiming the entry is unavailable.

## Verification

Automated, in `Packages/VanmoCore`:

- QR/device-code state machine: pending → approved → token exchange, expiry, cancel, and a failed poll.
- Refresh-token rotation: rotated refresh token is stored, the previous one is discarded, and a failed rotation requests re-login.
- Listing: pagination across pages, directory-only and file-only folders, empty folder, and stable provider IDs mapped to paths.
- Streaming: resolved URL never leaks the access token; required headers are attached; a `401` at resolve time maps to re-auth.
- Downloads: range resume and cancellation.
- All network code exercised through the existing URL protocol stubs; no live endpoint in tests.

Commands, in order:

```bash
swift test --package-path Packages/VanmoCore
./scripts/check-cloud-sync-multiplatform-scope.sh
./scripts/check-architecture-guards.sh
./scripts/check-harness-docs.sh
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
```

Real-source validation, both platforms, after the application ID is configured:

1. Launch iOS Vanmo with `./run_device.sh --simulator` (or a signed device) and VanmoMac with `./run_device.sh --macos`.
2. Open Files, add 115 Drive, scan the QR code with the 115 app, and confirm the login control completes and the connection saves.
3. Confirm the first listing shows readable directories and files from the account.
4. Play one listed video and record the engine path plus whether prefetch is used.
5. Repeat on the second platform; iOS evidence does not prove macOS.
6. Paste sanitized outcomes only: no tokens, no complete authenticated URLs, no private file names.

## Risks

- Token rotation limits: 115 documents that one application can issue a limited number of refresh tokens per account before older ones are invalidated. Users who authorize repeatedly may invalidate an earlier connection; the UI must recover by prompting re-login rather than silently failing.
- Account terms: 115 restricts sharing, hosting, and some external playback uses. The product copy must not encourage those uses, and the plan itself must not validate them.
- Playback compatibility: the download URL's required headers and range behavior determine whether KSPlayer can seek. If 115 rejects ranged or proxied requests, the plan records that as an evidence gap rather than forcing a workaround outside the official API.
- Path model mismatch: 115 identifies directories by numeric IDs while the browser keys on paths. A wrong map produces empty or duplicated listings; the map and its invalidation need tests.
- Credential handling: QR payloads, tokens, and resolved URLs must never reach logs, plans, fixtures, or screenshots. QR screenshots are equivalent to a pending credential.
- Rate limiting during development can look like a broken client; record the response before changing retry policy.

## Open Decisions

- Whether the 115 application type requires PKCE only or also a client secret; the configuration and Keychain handling differ.
- Whether the in-app login renders a locally generated QR image from the returned payload or the provider-supplied QR URL.
- Whether to offer a "paste refresh token" advanced path for personal use; it lowers friction but enlarges the credential-handling surface.
- Whether 115 playback goes through the prefetch proxy with required headers or bypasses prefetch like Baidu Netdisk's official links; decide from measured first-frame and seek behavior.
- Whether the placeholder captions on `.quarkDrive` and `.mega` should be rewired once the device-code flow exists (still out of scope here, but the code shape will make it cheaper).

## Progress

- **2026-10-21:** Plan created after the placeholder validation closed. Status `Blocked` on the 115 Open Platform application; no code changed.

## Next Step

Obtain the approved 115 Open Platform application ID (and scope confirmation), then start with the capability-model and configuration phase, which is the only phase that can be unit-tested before credentials exist.