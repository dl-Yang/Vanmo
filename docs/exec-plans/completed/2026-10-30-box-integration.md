# Box Connection Integration

**Status:** Completed
**Created:** 2026-10-30
**Completed:** 2026-11-01
**Plan type:** Implementation closeout, followed by real-source validation
**Related architecture authority:** [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md)
**Related security authority:** [`../../SECURITY.md`](../../SECURITY.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Make Box usable end to end on Vanmo iOS and VanmoMac: sign in with a Box account, browse folders and videos, play a listing, and download a file. `BoxDriveService`, the shared OAuth coordinator, the factory registration, and both platform connection forms already existed since the 2026-07-01 Box commit; the work is the credential gate, the Box-specific OAuth contract, a service hardening pass, focused tests, and dual-platform real-source acceptance.

The operator chose on 2026-10-30 to keep the Box app secret out of git: the repository keeps empty placeholders, the operator fills the client ID and secret on the build machine only, and the plan records the local walk. The committed tree therefore keeps the Box login control disabled until a build supplies its own Box app credentials.

## Credential Gate

Box does not support PKCE, so the shared PKCE public-client path used by OneDrive and Yandex.Disk cannot be reused:

- Box's `authorize` endpoint accepts `client_id`, `response_type`, `redirect_uri`, `state`, and `scope`; it has no `code_challenge` parameter. Token exchange requires the app's `client_secret`.
- The operator creates a Box Custom App (User Authentication / OAuth 2.0) in the Box Developer Console and enters the intended redirect URI `vanmo://oauth/box`. Box's public setup documentation only guarantees HTTPS or loopback redirect URIs, so whether the console accepts the custom scheme is confirmed at creation time; if it rejects it, the documented Box iOS SDK scheme below is the fallback.
- `OAuthProviderConfiguration.clientID(for: .box)` and `clientSecret(for: .box)` stay empty in git. The operator fills them locally before building; the filled values are never committed, logged, or copied into plans or fixtures. This is a controlled local-only exception, because Box has no public-client flow. Before committing, check `git diff` on that file shows empty Box values, and never `git add -A` while the local secret is filled.
- The requested scope is `root_readwrite`, not read-only. In the 2026-11-01 iOS Simulator walk, a read-only token still listed folders but `GET /files/{id}/content` returned `403 access_denied_insufficient_permissions`; the console app must therefore enable **Read and write all files and folders stored in Box**. Vanmo only calls read endpoints; it never uploads, renames, moves, deletes, or shares.
- The Box iOS SDK's documented mobile redirect format (`boxsdk-<clientID>://boxsdkoauth2redirect`) is the fallback if Box rejects the `vanmo://` scheme at registration time. That fallback also requires changes to `redirectURI(for:)`, `callbackURLScheme(for:)`, and `matchesCallback(_:type:)`, plus registering the client-ID-specific scheme in the iOS/macOS `Info.plist`; it is not a plist-only change.

## Found Defects and Fixes

- **Read-only scope blocked playback and download.** In the 2026-11-01 iOS Simulator walk, with `root_readonly`, listing returned `200` but every `/files/{id}/content` resolve returned `403 Access denied - insufficient permission`. Changing the app scope to read-write and requesting `root_readwrite` fixed it: the same endpoint returned `302` and the 50.6 MB file played and downloaded. The app still performs read-only operations.
- **Box folder titles showed item ids.** The browser derives a folder title from `currentPath`, and Box/OneDrive/Google Drive paths are opaque `/item/{id}` values, so entering `Movies` displayed `432596293452`. Both platform view models now keep a `directoryDisplayNames` map populated from the tapped `RemoteFile.name` (and from a folder bookmark's title), and the iOS header plus the macOS breadcrumbs resolve names through it.
- **Box token responses carry no `scope` field.** The diagnostic `authorize type=box scope=…` and `token granted type=box scope=-` Debug lines exist so a future scope regression can be distinguished from a console configuration problem without logging tokens.

## Operator Setup: Box Custom App

This is the exact console recipe the operator follows before the walk. It is also the recovery reference if a later Box setting changes.

### 1. Account

- Sign in at <https://app.box.com/developers/console>. If the account has no developer access yet, create a free developer account at <https://account.box.com/signup/developer>.
- A free developer account is enough for this plan: Platform Apps created there are authorized automatically and do not need Box Admin approval. `App Access Level` (`App Access Only` / `App + Enterprise Access`) applies only to JWT and Client Credentials apps and is intentionally left alone.
- The Box account used here must contain the folders and at least one playable video that the walk will browse. A separate free developer account with its own storage is fine.

### 2. Create the app

1. In the Developer Console select **New App** (older console wording: **Create Platform App**).
2. Choose app type **User** — "for apps where users link their Box accounts". Do not choose **Server**.
3. Confirm with **Create**. The app opens with **Authentication Method: OAuth 2.0**.

### 3. Configuration tab

- **General / Purpose**: any value is accepted; use **Other** (built by customer) or **Custom Portal**. The app name appears on the Box consent screen, so `Vanmo` is a good name.
- **Application Scopes**: enable **Read and write all files and folders stored in Box** (`root_readwrite`). Read-only is not enough: Box serves content downloads only to a read-write token, and the app will show `Box 权限不足` on playback/download otherwise. The app itself only reads.
- **OAuth 2.0 Redirect URI**: add `vanmo://oauth/box` exactly — lowercase `vanmo`, lowercase `box`, no trailing slash, no query, no whitespace. Box performs an exact-string match except for localhost/loopback ports.
  - Box's public documentation only promises HTTPS or localhost/loopback redirect URIs. If the console refuses the custom scheme or later returns `insecure_redirect_uri` / `redirect_uri_mismatch`, stop and report it; the fallback is the Box iOS SDK scheme in the next section, which needs code and `Info.plist` changes.
- **CORS Domains**: not needed; Vanmo is a native app, not browser JavaScript.
- **Advanced Features**: leave defaults.
- Click **Save Changes**. A free developer account re-authorizes the app automatically after saving.

### 4. Credentials

- Copy **Client ID** from the Configuration tab's **OAuth 2.0 Credentials** section. It is a public identifier and safe to keep locally; the repository keeps it empty regardless, because the same build must also carry the secret.
- Copy **Client Secret**. Box may require two-factor authentication before revealing it; enable 2FA on the account if prompted.
- The Configuration tab also shows a **Developer Token** (one hour, app-owner only). It is optional: it can be used for a manual `GET https://api.box.com/2.0/folders/0/items` sanity check in a terminal, but it is a live credential and must never be pasted into the repository, plans, logs, or fixtures. The Vanmo app does not consume it.

### 5. Local credential fill (never committed)

Edit `Packages/VanmoCore/Sources/VanmoCore/Network/OAuth/OAuthProviderConfiguration.swift`:

- `clientID(for:)`, `case .box:` → replace `""` with the Client ID.
- `clientSecret(for:)`, `case .box:` → replace `nil` with the Client Secret.

Alternatively give the two values to the agent, which writes them into the working tree only. Either way:

- Do not commit this file while the values are filled; `docs/SECURITY.md` documents this controlled local-only exception.
- Before committing anything, run `git diff -- Packages/VanmoCore/Sources/VanmoCore/Network/OAuth/OAuthProviderConfiguration.swift` and confirm the Box `clientID` and `clientSecret` are empty again.

### 6. Expected walk behavior and error triage

- Authorization URL: `https://account.box.com/api/oauth2/authorize?client_id=…&redirect_uri=vanmo%3A%2F%2Foauth%2Fbox&response_type=code&state=…&scope=root_readwrite`.
- `redirect_uri_mismatch` → the console value and `OAuthProviderConfiguration.redirectURI(for: .box)` do not match exactly.
- `invalid_client` → Client ID or Client Secret is wrong, or the secret was rotated in the console after being copied.
- `invalid_scope` → the console app does not enable `root_readwrite`.
- `403 access_denied_insufficient_permissions` on playback/download → the token is read-only; enable the read-write scope in the console, save, and re-authorize the connection. One walk round returned `403` immediately after a console scope change and a later fresh authorization returned `302`; treat a `403` right after changing scopes as a stale grant and re-authorize once more before investigating code.
- `invalid_grant` after roughly 60 days of inactivity → the refresh token expired; sign in again. The app now shows a readable re-authorize message.

### 7. Fallback redirect scheme (only if Box rejects `vanmo://oauth/box`)

Register `boxsdk-<CLIENT_ID>://boxsdkoauth2redirect` instead, then change:

- `OAuthProviderConfiguration.redirectURI(for: .box)` → the same string.
- `OAuthProviderConfiguration.callbackURLScheme(for: .box)` → `boxsdk-<CLIENT_ID>`.
- `matchesCallback(_:type:)` → match scheme `boxsdk-<CLIENT_ID>` and host `boxsdkoauth2redirect`.
- `Vanmo/Resources/Info.plist` and `VanmoMac/Resources/Info-Mac.plist` → add the `boxsdk-<CLIENT_ID>` URL scheme.

Because the Client ID is public, this fallback can stay in the committed tree once chosen; the Client Secret still follows rule 5.

## Scope

1. OAuth contract: mark `.box` as a secret-based authorization-code drive (no PKCE, no implicit grant), request `root_readwrite`, keep redirect/callback matching on `vanmo://oauth/box`, and stop sending Google's `access_type` parameter to Box.
2. Refresh safety: Box rotates refresh tokens and invalidates the previous one, so concurrent refreshes must be coalesced instead of racing (`invalid_grant` on the loser).
3. Service hardening: readable Box error mapping (`403`/`404`/`429`/`202`), low-noise `#if DEBUG` request-status logs without tokens or item names, and testable path/URL/item-mapping helpers.
4. Tests: `BoxOAuthTests` covering the OAuth contract, callback matching, factory/capability registration, item-id path mapping, list request shape, error text, and item JSON mapping; a focused test for refresh coalescing.
5. UI: keep directory display names for opaque `/item/{id}` paths so Box, OneDrive, and Google Drive folder headers and macOS breadcrumbs show the folder name instead of the item id, including navigation from a folder bookmark.
6. Documentation and guard: `ARCHITECTURE.md` (Box auth flow, secret boundary, rotating refresh tokens), `docs/SECURITY.md` (Box credential boundary), `todos.md`, this plan/index, and a `check-architecture-guards.sh` gate that fails when the committed or staged `.box` credentials are non-empty.
7. Dual-platform acceptance after the operator supplies credentials: iOS Simulator (agent-operated, operator completes the Box login) and VanmoMac (operator-driven).

## Out of Scope

- Upload, rename, move, delete, share, or collaboration APIs; the app only performs read-only browsing, playback, and download operations even though the token scope is read-write.
- Changing CloudKit sync or SwiftData models; tokens stay in `OAuthCredentialStore`.
- A Box thumbnail/official-poster integration; covers keep using the existing keyframe path.
- pCloud, MEGA, or other drive placeholders.
- Committing the Box client secret, or adding a hosted OAuth broker.

## Design Intent

### OAuth

- `OAuthProviderConfiguration` keeps `usesPKCE(.box) == false`, returns the `root_readwrite` scope, and keeps `vanmo://oauth/box` as the redirect URI. `isConfigured(for:)` requires both a client ID and a client secret, so the login control stays disabled until the operator fills both locally.
- `OAuthCoordinator` does not send the Google-only `access_type=offline` parameter to Box.
- Box refresh tokens are single-use and rotate on every refresh. `validAccessToken` coalesces concurrent refreshes per connection: the first caller performs the network request, later callers await the same task and receive the rotated credential. The rotated `refresh_token` from the token response continues to be persisted by `OAuthCredentialStore`.

### Service

- `connect(config:)` loads a valid access token, refreshing when expired.
- `listDirectory(path:)` treats `RemoteFile.path` as `/item/{id}` and the root as folder `0`, pages `GET /2.0/folders/{id}/items?fields=id,name,type,size,modified_at&limit=1000&offset=…`, and skips `web_link` entries.
- `streamURL(for:)` calls `/2.0/files/{id}/content` with the Bearer token, intercepts the `302`, and returns the anonymous `dl.boxcloud.com` `Location` so playback and download do not keep sending the token to the CDN. A `401` forces one token refresh and retries.
- `download(file:to:progress:)` downloads the resolved short-lived URL to a temporary file and moves it into place.
- Errors map to readable user text: `403` permission/scope guidance, `404` missing item, `429` rate limit, `202` file not yet ready, and a generic `Box API <status>: <server message>`.

### Tests

- No live endpoint in tests. OAuth configuration, callback matching, factory registration, path/URL helpers, error text, and item JSON mapping are pure and tested directly.
- Refresh coalescing is covered through a small typed single-flight helper with a counting operation, so the test does not need Keychain or network.

## Verification

Automated, in `Packages/VanmoCore`:

```bash
swift test --disable-sandbox --package-path Packages/VanmoCore
./scripts/check-cloud-sync-multiplatform-scope.sh
./scripts/check-architecture-guards.sh
./scripts/check-harness-docs.sh
./scripts/check-app-build.sh ios-simulator
./scripts/check-app-build.sh macos
```

Real-source validation, both platforms, after the operator fills local credentials:

1. Launch iOS Vanmo with `./run_device.sh --simulator` and VanmoMac with `./run_device.sh --macos`.
2. Add a Box connection, complete the Box login, and confirm the connection saves.
3. Confirm the first listing shows readable Box folders and files.
4. Play one listed video and record the engine path plus whether the prefetch proxy is used and whether seeking works.
5. Complete one file download and record its completion.
6. Repeat on the second platform; iOS evidence does not prove macOS.
7. Paste sanitized outcomes only: no tokens, no complete authenticated URLs, no private file names or item IDs.

## Verification Evidence

- Baseline before this change (2026-10-30): `swift test --disable-sandbox --package-path Packages/VanmoCore` passed 328 tests with 1 skipped and 0 failures.
- Final tree (2026-11-01): `swift test --disable-sandbox --package-path Packages/VanmoCore` passed 341 tests with 1 skipped and 0 failures, including the thirteen `BoxOAuthTests` (OAuth contract, callback matching, factory/capability registration, path/list-shape/JSON mapping, readable error text, token-form secret/PKCE contract, token-endpoint error mapping, and refresh coalescing/failure-retry).
- `./scripts/check-architecture-guards.sh` (2026-11-01, final tree): 0 failures, including the new Box credential guard that asserts `.box` `clientID`/`clientSecret` are empty in the git index and HEAD commit.
- `./scripts/check-cloud-sync-multiplatform-scope.sh` (2026-11-01, final tree): 0 failures.
- `./scripts/check-harness-docs.sh` (2026-11-01, final tree): 0 failures.
- `./scripts/check-app-build.sh all` (2026-11-01, final tree): an earlier attempt failed in both platforms with `Could not resolve package dependencies … ~/Library/Caches/org.swift.swiftpm/manifests/… Operation not permitted`, because the agent workspace sandbox blocks that cache path. The run with full file access produced `20261101-153211-32451`: `platform=ios-simulator status=pass`, `platform=macos status=pass`, `aggregate=pass failed_count=0`, both `xcodebuild_exit=0`.

### iOS Simulator walk (iPhone 17 Pro, agent-operated, operator completed the Box sign-in)

- Sign-in: `[Debug][OAuth] authorize type=box scope=root_readwrite`, `session finished type=box callback=oauth/box keys=code,state error=nil`, `token request host=api.box.com status=200`, `token granted type=box scope=-` (Box omits the granted scope from its response).
- Credential trap: with the console app still read-only, listing returned `folderItems status=200` but every `content` resolve returned `403`; the player showed `传输失败: Box 权限不足：Access denied - insufficient permission`. After enabling the read-write scope and re-authorizing, `content` returned `302`.
- Listing: repeated `[Debug][Box] request endpoint=folderItems status=200` for the root and `Movies`; the browser showed `Movies` and the three videos, and the folder header showed `Movies` rather than the previous item id.
- Playback: `[Debug][Player] event=videoQualityOpen quality=original direct path=http://127.0.0.1:56674/stream/…`, `event=firstFrame platform=ios engine=ks elapsedMs=4524`, `event=sample platform=ios engine=ks fps=30.01 avSyncMs=27 droppedDelta=0 bufferingCount=0`, and `[Debug][Prefetch] event=prefetchResponseSummary … bytes=50593792 elapsedMs=9334 depth=16 fetches=193` filling to `spanEnd=1.000000`. The signed Box link therefore supports the ranged prefetch requests.
- Download: `[Debug][Downloads] enqueued source=browser connection=box`; the app container contained `Documents/Downloads/J.mp4` at `50593792` bytes, matching the source size.

### VanmoMac walk (operator-driven)

- Sign-in: the same `authorize type=box scope=root_readwrite`, `session finished type=box callback=oauth/box`, `token request host=api.box.com status=200`, `token granted type=box scope=-` sequence from the `Vanmo-macOS` process; `folderItems status=200` for the root and `Movies`; `content status=302` on all resolves (no `403` in the run).
- Playback: `[MacPlayerVM] KS using prefetch proxy for remote URL`, `[Debug][PlaybackPerf] event=ready platform=macos engine=ks elapsedMs=1731 hardware=true`, `event=firstFrame platform=macos engine=ks elapsedMs=5232`, and `event=sample platform=macos engine=ks fps=29.99 avSyncMs=1 droppedDelta=0 bufferingCount=0`; a second open reached `ready 1429 ms` / `firstFrame 3429 ms`.
- Download: `[Debug][Downloads] enqueued source=browser connection=box`, then `status=completed progress=100 received=50593792 total=50593792 type=box media=movie`; the file landed at `~/Downloads/Vanmo/J (1).mp4` with `50593792` bytes (the unsuffixed name was already present from an earlier OneDrive walk).

## Remaining Verification

None required for this plan. Unverified paths, each needing its own walk if it matters: a scripted seek through the Box prefetch session, token refresh after the one-hour access-token lifetime, the offset cap on very large Box folders, the macOS folder-bookmark breadcrumb (code path compiled, not visually walked), and the root cause of the single `403` observed right after a console scope change and a re-authorization (a later fresh authorization returned `302`).

## Risks

- Box refresh tokens rotate and expire after 60 days. A device left offline longer than that returns `invalid_grant` from the token endpoint; `OAuthCoordinator.tokenErrorMessage` maps that to "Box 登录已过期或授权已被撤销，请重新授权登录。" instead of raw JSON, but the user still has to sign in again.
- Box's `dl.boxcloud.com` download links are short-lived. The walk proved ranged prefetch works (`depth=16`, `fetches=193`, a full 50.6 MB cache span), but an explicit scripted seek was not recorded.
- Box download links are bearer-like for their short lifetime; they must never be persisted in the catalog or logged. The catalog keeps `vanmo://playback/...` placeholders and resolves per play.
- Box folder listing is offset-based and offset is capped by Box for very large folders; folders beyond the cap would return an API error rather than silently truncate.
- The `vanmo://oauth/box` redirect scheme is accepted by Box only if the console saves it; Box's public docs only guarantee HTTPS or loopback URIs. The fallback is the documented Box iOS SDK scheme, which requires changing `redirectURI(for:)`, `callbackURLScheme(for:)`, `matchesCallback(_:type:)`, and registering the client-ID-specific scheme in both `Info.plist` files.
- The local filled client secret exists only in the operator's working tree; any rebuild from a clean checkout needs it re-entered. This is the accepted trade-off for keeping the public repository free of live credentials.
- A read-only Box token does block content downloads (`403`), so the app requests `root_readwrite` and the console app must keep that scope. The app never writes. If the console scope is ever reduced to read-only, playback and download break while listing still works.
- One re-authorization immediately after a console scope change still produced a token that returned `403`; a later fresh authorization returned `302`. The concrete condition was not isolated, so a `403` right after a scope change should be treated as a stale grant and retried with a fresh authorization before debugging code.
## Progress

- **2026-10-30:** Plan created. Baseline recorded: 328 VanmoCore tests pass (1 skipped). Operator confirmed no Box app exists yet, chose the `vanmo://oauth/box` redirect, and chose to keep the client secret out of git.
- **2026-10-30:** Implemented the Box OAuth contract, refresh coalescing, service hardening, tests, and documentation. Final-tree verification: 341 VanmoCore tests (1 skipped), architecture guards, CloudKit/multiplatform scope check, harness documentation check, and both app Debug compiles in run `20261030-141800-6696` (aggregate pass).
- **2026-10-30:** Ran the post-task code review. It returned "可优化" with no blocking defect. Applied: pure form-item helpers with Box secret/no-PKCE tests, token-endpoint `invalid_grant`/`invalid_client` readable mapping, single-flight self-clearing slot plus waiter-count and failure-retry tests, deterministic refresh test gate, `isConfigured` pure helper test, private wire models with an internal decode helper, and corrected documentation wording/evidence. Declined: a gitignored secret-injection channel, because Box has no public-client flow and SwiftPM cannot compile a missing optional source file; the controlled local-fill exception is documented in `docs/SECURITY.md` instead. Real-source acceptance is pending the operator's Box app credentials.
- **2026-10-30 → 2026-11-01:** Dual-platform walk. iOS: sign-in, listing, read-only `403` defect, scope change to read-write, re-authorization, `content 302`, playback through the prefetch proxy (`firstFrame 4524 ms`, 30 fps), and a 50,593,792-byte download. Fixed the folder-title item-id display while walking. macOS: sign-in, listing, `content 302`, prefetch-proxy playback (`ready 1731 ms`, `firstFrame 5232 ms`, 30 fps), and a completed 50,593,792-byte download. Finally re-ran the package suite (341 tests, 1 skipped), the three static checks, and both app Debug compiles in run `20261101-153211-32451` (aggregate pass).
- **2026-11-01:** Post-task review returned "不通过" on one blocker: the local Box client ID/secret were still filled in the tracked config file. Restored both to empty placeholders and added a `check-architecture-guards.sh` gate that fails if the `.box` values are non-empty in the git index or HEAD. Also fixed the macOS breadcrumb ancestor path (`/item/{id}` no longer invents an `/item` level), moved the iOS title lookup ahead of the empty-path-stack fallback, restored macOS bookmark ancestor breadcrumbs, and corrected the scope/registration/path-model wording across the docs.

## Next Step

None; the plan is complete. Optional follow-ups are the unverified paths above, the scope-change re-auth anomaly, and the documented local-only credential fill (the committed tree keeps the Box login control disabled by design).
