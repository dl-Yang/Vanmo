# OneDrive Connection Integration

**Status:** Completed
**Created:** 2026-10-27
**Completed:** 2026-10-27
**Plan type:** Implementation closeout, followed by real-source validation
**Related architecture authority:** [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md)
**Related security authority:** [`../../SECURITY.md`](../../SECURITY.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Make OneDrive usable end to end on Vanmo iOS and VanmoMac: sign in with a Microsoft account through the existing PKCE flow, browse folders and videos, play a listing, and download a file. `OneDriveService`, the shared OAuth coordinator, and both platform connection forms already existed; the work was the Entra credential gate, a service hardening pass, and dual-platform real-source acceptance.

This plan supersedes the deleted credential-gated plan `2026-08-28-onedrive-connection-validation.md`, which recorded that login stayed disabled while the client ID was empty.

## Outcome

Sign-in, first listing, playback, and download work on an iPhone 17 Pro (iOS 27.0.1) and on VanmoMac. The iPhone walk also re-authorized an existing connection on the final binary. One real defect was found during the run: Microsoft Graph omits the `@microsoft.graph.downloadUrl` instance annotation when a `$select` is used, so playback, thumbnails, and download all failed with "OneDrive 未返回可用下载直链" even though the item request returned `200`. The service now requests the complete `driveItem` for a single item.

## Credential Gate

- Microsoft Entra application (client) ID `4f24ca70-48e9-4a63-8e51-e35647350e64` is filled into `OAuthProviderConfiguration.clientID(for: .oneDrive)`.
- Public client, no client secret. Supported account types include personal and organizational accounts because the code uses the `/common` endpoints.
- Redirect URI registered as `vanmo://oauth/oneDrive` (case-sensitive path).
- "Allow public client flows" is enabled in the app registration.
- Delegated Microsoft Graph scopes: `Files.Read.All` and `offline_access`. Only read access is requested; Vanmo never writes to the drive.
- 2026-10-27 preflight: an unauthenticated `prompt=none` request to the authorize endpoint redirected to `vanmo://oauth/oneDrive?error=interaction_required`. That proves the client ID, redirect URI, sign-in audience, and scope are accepted by the login server; the expected error only means no browser session existed.

## Decisions

- Item metadata is fetched without `$select`. Microsoft Graph silently drops `@microsoft.graph.downloadUrl` when the request selects fields, and the phone run reproduced the missing URL. The full `driveItem` is small, so no field selection is used for a single item. A source comment records the reason.
- No `/content` redirect fallback was added. The default complete `driveItem` response carries the pre-signed URL for regular files, and the walk verified listing, thumbnails, playback, and download against that path. Shortcut or remote-item URL edge cases remain unverified and are listed under Risks.
- Graph errors now map to readable text: `403` permission/authorization, `404` missing item, `429` rate limit, and a generic message that prefers the Graph `error.message`. Debug logs record only the endpoint category (`children`/`item`) and HTTP status.
- OAuth tokens stay device-local in `OAuthCredentialStore`. A connection synced through CloudKit therefore arrives with `missingCredential=true` on the other device and needs one local sign-in; the macOS run confirmed that behavior instead of treating it as a defect.
- The OneDrive integration reuses the shared OAuth coordinator and the shared lazy playback URL strategy: the catalog keeps `vanmo://playback/...` placeholders and `streamURL(for:)` resolves the one-hour pre-signed link per playback or download.

## Scope

- Fill the operator-supplied client ID and keep the public-client, no-secret boundary.
- Add focused unit tests for the OneDrive OAuth configuration, redirect URI case sensitivity, factory registration, lazy playback URL, download eligibility, and readable Graph error mapping.
- Add low-noise `#if DEBUG` status logs for OneDrive Graph requests.
- Record dual-platform acceptance: sign-in, first listing, playback, and download on a physical iPhone and on VanmoMac.
- Update the durable documents that own this credential boundary and the evidence snapshot.

## Out of Scope

- Upload, rename, move, delete, or share operations; the requested scope is read-only.
- OneDrive for Business admin-consent review beyond the operator's own tenant.
- Automatic recurring directory sync or playback-progress sync; the shared lazy-URL behavior already covers scan persistence.
- A OneDrive thumbnail or official-poster integration. Covers keep using the existing keyframe path.
- Changes to other OAuth drives. Their client IDs remain empty and their login controls stay disabled.

## Verification Evidence

- `swift test --disable-sandbox --package-path Packages/VanmoCore` (2026-10-27, final tree): 287 tests, 0 failures, including the five `OneDriveOAuthTests` (four OAuth/factory/error cases plus the item-URL contract test). The baseline before this change was 282 tests. One earlier full-suite run hit the existing `PrefetchTests.testSessionDeduplicatesSameChunkAcrossConcurrentBodies` concurrency flake (`2` vs `1`); its focused suite passed 25/25, and the next full run passed 286/286 before the fifth test was added. The final full run after that test passed 287/287. The `--disable-sandbox` flag is required in this workspace because SwiftPM's nested sandbox cannot start inside the agent file sandbox.
- `./scripts/check-architecture-guards.sh` (2026-10-27): 0 failures.
- `./scripts/check-app-build.sh all` (2026-10-27, run `20261027-104028-72450` on the final tree; the earlier pre-contract-test run was `20261027-101036-67894`): `platform=ios-simulator status=pass`, `platform=macos status=pass`, `aggregate=pass failed_count=0`, both `xcodebuild_exit=0`. The macOS product of this script is compile-only and unsigned; launching it traps in `CKContainer(identifier:)` at `CloudStoreCloudKitAdoption.logAccountAndZones()`, which is why the macOS walk used the signed `./run_device.sh --macos` build.
- `./run_device.sh 00008150-00015C5936F8C01C` (2026-10-27): `BUILD SUCCEEDED`, app installed to the iPhone, and launched after the operator trusted the development certificate. The first launch was denied by iOS with "invalid code signature, inadequate entitlements or its profile has not been explicitly trusted by the user".
- `./run_device.sh --macos` (2026-10-27): `BUILD SUCCEEDED`; the signed app launched and attached the private CloudKit store.

### iOS physical-device walk (iPhone 17 Pro, iOS 27.0.1)

- Sign-in on the pre-fix build: `[Debug][OAuth] session finished type=oneDrive callback=oauth/oneDrive keys=code,state error=nil`, `[Debug][OAuth] token request host=login.microsoftonline.com status=200`.
- Pre-fix defect: `[Debug][OneDrive] request endpoint=item status=200` followed by `[Debug][Thumbnail] resolveFail ... 连接失败: OneDrive 未返回可用下载直链` for every listed video.
- Re-authorize on the final build (after the `$select` fix): `[Debug][OAuth] session finished type=oneDrive callback=oauth/oneDrive keys=code,state error=nil`, `[Debug][OAuth] token request host=login.microsoftonline.com status=200`, then `[Debug][OneDrive] request endpoint=children status=200`.
- First listing on the final build: repeated `[Debug][OneDrive] request endpoint=children status=200` lines for the root and shallow-scan subfolders. Thumbnails then resolved: `[Debug][Thumbnail] extractStart file=... scheme=https`, `extractOK ... bytes=1146001`, and `files result ... ok=true platform=ios`.
- Playback: `[Debug][Player] present mediaType=movie isFile=false ext=aspx`, `[Debug][Player] event=ksCreate ... url=http://127.0.0.1:50761/stream/...`, `[Debug][PlaybackPerf] event=ready platform=ios engine=ks elapsedMs=2948 hardware=true`, `event=firstFrame platform=ios engine=ks elapsedMs=11449`, and `event=sample platform=ios engine=ks fps=30.00 avSyncMs=11 droppedDelta=3 bufferingCount=0` with `[Debug][Prefetch] event=cacheSpan` growth. The played item was a 131-second movie; no title is recorded here.
- Download: `[Debug][Downloads] task=... status=downloading progress=... type=oneDrive media=movie`, then `status=completed progress=100 received=50593792 total=50593792 type=oneDrive media=movie`.

### VanmoMac walk

- The CloudKit-imported OneDrive row first logged `[Debug][CloudKit] activate type=oneDrive missingCredential=true`; the editor was then opened and the operator signed in.
- Sign-in: `[Debug][OAuth] session finished type=oneDrive callback=oauth/oneDrive keys=code,state error=nil`, `[Debug][OAuth] token request host=login.microsoftonline.com status=200`.
- Listing and covers: `[Debug][OneDrive] request endpoint=children status=200`, `[Debug][Thumbnail] extractStart ... scheme=https`, `extractOK ... bytes=1146001`, `posterSaved ...`.
- Playback: `[MacPlayerVM] KS using prefetch proxy for remote URL`, `[Debug][PlaybackPerf] event=ready platform=macos engine=ks elapsedMs=2556 hardware=true`, `event=firstFrame platform=macos engine=ks elapsedMs=7056`, and `event=sample platform=macos engine=ks fps=29.51 avSyncMs=-2 droppedDelta=0 bufferingCount=1`, with `[Debug][Prefetch] event=aheadFill` filling to the end and `event=cleanup platform=macos engine=ks prefetch=true` on close.
- Download: two `[Debug][Downloads] task=... status=completed progress=100 received=50593792 total=50593792 type=oneDrive media=movie` lines.

### Documentation checks

- `./scripts/check-harness-docs.sh` (2026-10-27): 23 failures, all pre-existing. They are the operator's uncommitted deletion of the `2026-08-28-*` validation plans that `docs/exec-plans/active/index.md` and `docs/exec-plans/completed/2026-09-08-library-scan-thumbnail.md` still link to; this plan did not delete them and does not restore them. The active index also carries the operator's existing 115 Open Platform section, which points at the still-untracked `2026-10-21-drive115-open-platform-integration.md`; it predates this task and was left in place. Every check that references `2026-10-27-onedrive-integration.md` passed: link resolution, completed-index listing, status match, and filename overlap.
- `./scripts/check-architecture-guards.sh` (2026-10-27, after the document edits): 0 failures.

## Remaining Verification

None required for this plan. Unverified paths, each needing its own walk if it matters: a token refresh after the one-hour access-token lifetime (re-authorize was tested instead), work/school tenant consent, OneDrive shortcut/remote-item download URLs, and a `429` backoff path.

## Risks

- iOS first frame took 11.4 s on the first OneDrive open (macOS: 7.1 s), likely because the prefetch size probe and keyframe extraction share the pre-signed download connection. Playback then held 30 fps with no rebuffering. A follow-up could profile OneDrive first-play latency.
- `@microsoft.graph.downloadUrl` links expire after roughly one hour. The catalog keeps only `vanmo://playback/...` placeholders and resolves links per playback/download, so a stale link cannot be persisted.
- OneDrive `429` responses are mapped to a readable retry message; the service does not implement `Retry-After` backoff.
- OneDrive shortcuts or files shared from another drive can return a `remoteItem` whose download URL may need the `/content` redirect path that is not implemented. Regular personal-drive files are covered by this walk.
- The macos compile-evidence product is unsigned by design and cannot be launched; macOS runtime evidence must come from `./run_device.sh --macos`.
- A pre-existing `PrefetchTests` concurrency dedup flake failed once and passed on rerun; it is unrelated to OneDrive.
- During the macOS walk an unrelated Google Drive token refresh logged `token request host=oauth2.googleapis.com status=400`. It belongs to an existing Google Drive row and was not investigated in this plan.

## Progress

- **2026-10-27 (operator):** Created the Entra application, enabled public client flows, registered `vanmo://oauth/oneDrive`, and supplied the client ID.
- **2026-10-27:** Preflight confirmed the registration is accepted; filled the client ID in `OAuthProviderConfiguration`.
- **2026-10-27:** Added `OneDriveOAuthTests` (initially four cases), readable Graph error mapping, and the `#if DEBUG` request-status log. Focused run passed 4/4.
- **2026-10-27:** Built and installed the signed device build, then walked iOS sign-in and listing. The walk exposed the missing download URL under `$select`.
- **2026-10-27:** Removed `$select` from the single-item request, re-ran the package suite (286/286 at that point), rebuilt both platforms (run `20261027-101036-67894`), reinstalled, and re-walked iOS: listing, thumbnail extraction, playback, and a 50.6 MB download all passed. Re-authorized on the final binary.
- **2026-10-27:** Post-task review found the documentation still recorded the pre-contract-test counts. Added `testItemRequestOmitsSelectSoGraphReturnsTheDownloadAnnotation` (asserts the item URL has no `$select`) and made `itemURL(for:)` internal for that test. Re-ran the full suite (287/287), rebuilt both platforms in run `20261027-104028-72450` (aggregate pass), and re-ran the architecture guards (0 failures). Also applied the review's documentation corrections: scoped the SECURITY log claim to the request-status log and bumped the QUALITY_SCORE date.
- **2026-10-27:** Ran the signed macOS build, completed sign-in, listing, playback through the prefetch proxy, and two 50.6 MB downloads.

## Open Decisions

None.