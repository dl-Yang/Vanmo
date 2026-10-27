# Yandex.Disk Login SDK Integration

**Status:** Completed  
**Created:** 2026-10-21  
**Completed:** 2026-10-27  
**Plan type:** Implementation, followed by real-source validation  
**Related architecture authority:** [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md)  
**Related security authority:** [`../../SECURITY.md`](../../SECURITY.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Enable Yandex.Disk sign-in, browse, and play on Vanmo iOS and VanmoMac. iOS signs in with the official YandexLoginSDK (Yandex app when installed, SDK web flow otherwise). macOS has no SDK and uses the shared PKCE authorization-code flow. Both platforms reuse the existing `YandexDiskService` for listing, stream URLs, and download.

This plan supersedes the earlier credential-gated validation plan `2026-08-28-yandex-disk-connection-validation.md`, which recorded that login stayed disabled while the client ID and secret were empty.

## Outcome

Sign-in, listing, and playback work on a physical iPhone, the iOS Simulator, and macOS (2026-10-26). Cancel is verified on the iOS Simulator. Re-authorizing an existing connection is verified on the iOS Simulator (2026-10-26) and macOS (2026-10-27). iOS sign-in uses the SDK web flow; the Yandex-app hand-off did not trigger with the apps tested and is recorded as unverified.

## Decisions

- SDK: `yandexmobile/yandex-login-sdk-ios` `exactVersion: 3.2.0`, iOS target only. The `2.1.1` tag exposes the Objective-C `YXLSdk` API and uses `unsafeFlags`; 3.2.0 matches the documented Swift API and is version-pinnable.
- Authorization strategy: `.default`. This requires `LSApplicationQueriesSchemes` (`primaryyandexloginsdk`, `secondaryyandexloginsdk`), the `yx{client ID}` URL scheme, and the associated domain `applinks:yx{client ID}.oauth.yandex.com`. SDK 3.2.0 always sends a PKCE challenge, so its redirect is always the `yx{client ID}:///auth/finish` deep link delivered to `onOpenURL`; the universal-link path is kept only as a documented fallback.
- No client secret in source. Yandex accepts a PKCE `code_verifier` instead of `client_secret`, so `usesPKCE(.yandexDisk)` is true and `clientSecret(.yandexDisk)` stays `nil`.
- Scope is `cloud_api:disk.read` only. `YandexDiskService` calls only `resources` and `resources/download`. The scope must stay a subset of the permissions registered for the client ID.
- The shared PKCE flow keeps `prefersEphemeralWebBrowserSession = true` for every provider except Yandex.Disk. Yandex sign-in through a social provider (Google) lands on the Yandex ID profile page instead of returning to the consent page; with an ephemeral session every retry starts signed out and the user can never reach consent. A persistent session lets the second attempt go straight to consent. The cost is that the Yandex session is shared with the system browser.
- A `403 DiskUnsupportedUserAccountTypeError` is mapped to a readable message. Yandex accounts without a Yandex Mail mailbox (for example accounts registered only through Google) can obtain a token, but the Disk API rejects every call.
- `OAuthCoordinator.externalAuthenticators` lets the iOS app inject `YandexLoginAuthenticator` without `VanmoCore` importing UIKit. When SDK activation fails, nothing is registered and iOS falls back to the PKCE web flow.
- The SDK returns an access token only. It is stored with an empty refresh token and the existing long default lifetime; a server 401 surfaces the existing re-authorize path. The authenticator calls `logout()` before each `authorize` so a cached SDK result does not skip the prompt, and again after success so the token lives only in `OAuthCredentialStore`.
- SDK callback errors (denied in the Yandex app, failed state check) are thrown by the non-`try*` SDK handlers and end the pending sign-in. Task cancellation (`cancelAndClose`) ends the wait through `withTaskCancellationHandler`, keyed by a per-attempt ID so a late cancel cannot end a newer attempt.

## Yandex OAuth Console Prerequisites (operator)

- Client ID `4cbf02a3c61e404a89d3af6c83e71a64`. It must match `OAuthProviderConfiguration.clientID(.yandexDisk)`, the `yx{client ID}` URL scheme in `Vanmo/Resources/Info.plist`, and the associated domain in `project.yml`.
- iOS platform: App ID `HYGMY7H2C5.com.vanmo.app`.
- Web services platform: Redirect URI `vanmo://oauth/yandexDisk` (macOS, and the iOS fallback).
- Permissions: `cloud_api:disk.read` and `cloud_api:disk.info` (public client info, 2026-10-26). Vanmo requests only `cloud_api:disk.read`.
- `https://oauth.yandex.com/client/<client ID>/info` is a quick public check that the console edits apply to the expected client ID.

## Progress

- **2026-10-21:** Implemented the `OAuthExternalAuthenticator` hook, a public `OAuthCredential` initializer, Yandex PKCE configuration with the public client ID, the iOS `YandexLoginAuthenticator`, URL / user-activity forwarding in `ContentView`, the `project.yml` package and associated domain, and the iOS `Info.plist` schemes. Regenerated the Xcode project with XcodeGen.
- **2026-10-23 (operator):** Console screenshot confirms Web services Redirect URI `vanmo://oauth/yandexDisk` and iOS App ID `HYGMY7H2C5.com.vanmo.app`. The consent preview lists "Read all of Yandex.Disk" and "Access to information about Yandex.Disk", and shows "Service not verified". The public client info page still returned the old cached callback at the time.
- **2026-10-23:** Applied the post-task review findings (callback error handling, cancellation, clearing the SDK token copy). Narrowed the Yandex scope to `cloud_api:disk.read` after the public client info page showed it is the only registered permission. Marked the plan Blocked on console redirect registration and operator sign-in.
- **2026-10-26 (device debugging):** Diagnosed with temporary `#if DEBUG` logs and operator screenshots. Four issues were found, in order:
  1. Google social sign-in inside the auth sheet lands on the Yandex ID profile page, so the first attempt never reaches consent. On macOS the ephemeral session made every retry start signed out. Fixed with the per-provider ephemeral switch described in Decisions.
  2. Once signed in, both platforms got Yandex `400` "redirect_uri does not match the Callback URL". The public client info showed the code's client ID still had only the default callback: the console edits had been made on a different app. The operator corrected the environment variables, and the client ID moved to `4cbf02a3c61e404a89d3af6c83e71a64` in code, `Info.plist`, and `project.yml` (XcodeGen regenerated).
  3. The Disk API then returned `403 DiskUnsupportedUserAccountTypeError` for an account registered through Google without Yandex Mail. Mapped to a readable error. The operator switched to an account with Yandex Mail.
  4. With that account, sign-in, listing, and playback succeeded on both platforms.
- **2026-10-26:** Trimmed the temporary logs. Remaining `#if DEBUG` lines: one SDK sign-in outcome line on iOS, one auth-session outcome and one token-status line in `OAuthCoordinator`, and one status line per Yandex.Disk API request. None records tokens, codes, query values, or file paths.

## Verification Evidence

- `swift test --package-path Packages/VanmoCore` (2026-10-23): 281 tests, 0 failures, including `YandexDiskOAuthTests` (PKCE public-client configuration, scope, and external-authenticator routing). Baseline before the change: 279 tests, 0 failures.
- `./scripts/check-architecture-guards.sh` (2026-10-23): 0 failures.
- `./scripts/check-app-build.sh ios-simulator` (2026-10-23, after the review fixes and scope change): `BUILD SUCCEEDED`; no warnings from `YandexLoginAuthenticator.swift`. YandexLoginSDK 3.2.0 and its C++20 CertificateTransparency target compiled.
- `./scripts/check-app-build.sh macos` (2026-10-23, run after iOS): `BUILD SUCCEEDED`.
- `./run_device.sh --simulator` (2026-10-21, before the review fixes): app launched. `log show --last 5m` for the Vanmo process had 412 lines and no `[YandexLogin] activate failed`. The installed app's `Info.plist` contains `LSApplicationQueriesSchemes` (`primaryyandexloginsdk`, `secondaryyandexloginsdk`) and the `YandexLoginSDK` `yx{client ID}` URL type. This is launch evidence only, not a sign-in.
- `./scripts/check-harness-docs.sh`: failures are limited to the operator's uncommitted deletion of `2026-08-28-*-connection-validation.md` active plans that `index.md` and one completed plan still link to. No failure references files touched by this plan.

- After the 2026-10-26 fixes and log trim: `swift test --package-path Packages/VanmoCore` 282 tests, 0 failures (adds the persistent-session and `DiskUnsupportedUserAccountTypeError` message assertions); `./scripts/check-architecture-guards.sh` 0 failures; `./scripts/check-app-build.sh ios-simulator` then `macos`, both `status=pass`, no warnings from the touched files; `./scripts/check-harness-docs.sh` failures are still limited to the deleted `2026-08-28-*` plans.
- macOS operator walk (`./run_device.sh --macos`, 2026-10-26, local `log stream`): `[Debug][OAuth] session finished type=yandexDisk callback=oauth/yandexDisk keys=cid,code,state error=nil`, then `token request host=oauth.yandex.com status=200`, then `[Debug][YandexDisk] request endpoint=resources status=200` (root listed 2 items) and four `endpoint=resources/download status=200`. The operator reported that playback worked.
- iOS physical device walk (`./run_device.sh`, iPhone 17 Pro, 2026-10-26, operator-copied Console lines): `[Debug][YandexDisk] request endpoint=resources status=200` (root listed 1 item), `endpoint=resources/download status=200`, then KSPlayer `readyToPlay, duration: 77s`, first frame at 24.0 s, and steady 30 fps samples with `bufferingCount=0`, including one seek (`seekEnd elapsedMs=418`). The operator reported that sign-in succeeded. The copied excerpt began after sign-in, so the SDK outcome line itself was not captured.
- Earlier failed attempts are diagnostic evidence only: `WebAuthenticationSession#1` cancellations, Yandex `400` redirect mismatch screenshots, and the `403 DiskUnsupportedUserAccountTypeError` screenshot.

- Yandex-app path (2026-10-26, physical iPhone): the SDK's universal link `https://loginsdk.passport.yandex.ru/am/loginsdk/primary|secondary` is claimed in that host's apple-app-site-association only by `ru.yandex.mobile` (Yandex with Alice AI), `ru.yandex.mobile.kluch` (Yandex ID), `ru.yandex.ytaxi` (Yandex Go), and internal builds. With Yandex ID (`ru.yandex.mobile.kluch`) and Yandex Browser (`ru.yandex.mobile.search`, not claimed) installed, sign-in still opened the SDK web flow. The reason the hand-off did not happen was not captured (no `canOpenURL` result was recorded). The operator chose to keep the current behavior, and the `.default` strategy is unchanged.

- iOS Simulator agent walk (`./run_device.sh --simulator`, iPhone 17 Pro Simulator, iOS 26.0, 2026-10-26, `idb ui tap` plus `simctl io screenshot`, logs from `simctl spawn ... log stream`; screenshots under the git-ignored `build/yandex-sim-evidence/`):
  - Cancel: Files → Add → Yandex.Disk → sign in showed the system "Vanmo Wants to Use yandex.ru to Sign In" prompt. Tapping Cancel logged `[Debug][YandexLogin] finish outcome=failure NSError com.apple.AuthenticationServices.WebAuthenticationSession#1`. The form showed `连接失败: 已取消授权` with the sign-in button still enabled.
  - Sign-in: a retry opened the Yandex ID page in the SDK web sheet. The operator entered the credentials (the agent did not). The flow logged `finish outcome=success`, and the connection was saved.
  - List and play: the root listed 3 files (`resources status=200`). `L.mp4` played through KSPlayer: `readyToPlay` 47.8 s and first frame 58.3 s after open (Simulator, with a concurrent thumbnail extraction), then 30 fps samples with `bufferingCount=0`.
  - Re-authorize: after an app relaunch, Edit → `重新登录 Yandex.Disk` showed the system prompt again instead of reusing a cached token. Yandex showed the consent page for the already signed-in account, and confirming logged `finish outcome=success`. The first listing after that timed out (`[Files] Failed to browse Yandex.Disk: ... The request timed out.`, no HTTP response). The next open listed the same 3 files (`resources status=200`), which points to a transient network failure, not a token problem.

- macOS re-authorize (`./run_device.sh --macos`, 2026-10-27, local `log stream`; the operator clicked Edit → `重新登录 Yandex.Disk` and confirmed consent): `[Debug][OAuth] session finished type=yandexDisk callback=oauth/yandexDisk keys=cid,code,state error=nil`, `token request host=oauth.yandex.com status=200`, then `[Debug][YandexDisk] request endpoint=resources status=200` and three `endpoint=resources/download status=200`.

Not yet verified: an actual hand-off to a Yandex app (not reached with the apps above; Yandex Go and Yandex with Alice AI untested); denying inside a Yandex app (unreachable without the hand-off); closing the Yandex web consent page itself (only Cancel on the system sign-in prompt was verified); a token refresh without `client_secret` on macOS.

## Remaining Verification

None. The unverified paths above need no further walk for this plan.

## Risks

- Users who sign in to Yandex through Google must retry once after landing on the Yandex ID profile page. This is Yandex web behavior and cannot be fixed in Vanmo.
- Yandex accounts without Yandex Mail cannot use the Disk API even after a successful sign-in.
- iOS cold start on a Yandex stream took about 20 s to `readyToPlay`. The prefetch `HEAD` probe failed (Yandex download URLs redirect across hosts), and thumbnail extraction ran concurrently. Playback performance was not investigated in this plan.
- Failed sign-in attempts during debugging left extra Yandex.Disk connection rows without credentials, synced through CloudKit. The operator can delete them; no code change is needed.
- Associated Domains requires automatic signing to refresh the provisioning profile.
- If the user leaves for the Yandex app and never returns, the pending request stays open until the user cancels or starts another sign-in.
- A late `/token` or JWT response from an earlier SDK attempt could resume a newer attempt; both use the same client, so only the account could differ. The SDK callback carries no attempt identifier, so this cannot be filtered in Vanmo; the pre-authorize `logout()` already makes late redirect URLs fail the SDK state check.
- A Yandex-app return that arrives after the user abandoned sign-in is still handled by the SDK, which saves its own token copy until the next sign-in's `logout()` clears it.
- SDK tokens carry no expiry; revoked or expired tokens rely on the 401 re-authorize path. Yandex refresh without `client_secret` (macOS) is unverified.

## Next Step

None for this plan. Possible follow-ups, each needing its own plan: the slow first play of Yandex streams on iOS (prefetch `HEAD` probe across the redirect), and a Yandex-app hand-off check with Yandex Go.
