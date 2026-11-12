# Plex PIN Sign-In and Server Discovery

**Status:** Completed
**Created:** 2026-10-29
**Completed:** 2026-10-29
**Plan type:** Implementation and dual-platform validation
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Replace the password-based Plex connection flow with the official plex.tv PIN authorization (four-character code at `plex.tv/link`), discover the signed-in account's Plex Media Servers automatically, keep the `X-Plex-Token` per connection in Keychain, and record dual-platform evidence for sign-in, discovery, listing, and playback.

## Context

- `PlexService` already lists `/library/sections`, streams and downloads parts, feeds the media-server catalog sync, and backs the Plex detail, episode, and intro-marker fetchers. It was added in 2026-08 and has never been validated against a real PMS.
- `PlexService.connect(config:)` requires `config.username` and `config.password`, and re-runs `POST https://plex.tv/api/v2/users/signin` on every connect. Accounts with two-factor authentication or an app-specific password fail. There is no server discovery.
- The X-Plex-Token lives in one global Keychain slot (`plex.token`) plus `plex.baseURL` in UserDefaults, so a second Plex server would overwrite the first. Detail, metadata, and playback-quality readers use that global slot.
- `SavedConnection` has no token or Plex-specific column. The `conn_<UUID>` Keychain slot currently holds the Plex account password.
- The 2026-08-28 Plex validation plan was retired in `58e4ec1`; no Plex plan or product spec remains. There is no PIN or discovery code anywhere in the repository.

## Scope

- `VanmoCore`: `PlexAuthAPI` (PIN creation and polling, `/api/v2/resources` discovery, account lookup, endpoint probing), per-connection token storage in `PlexCredentialStore`, token-first `PlexService.connect` with a legacy password fallback, and `MediaServerConnectionSnapshot.config` carrying `connectionId`.
- iOS: a Plex branch in Add Connection, a PIN sign-in sheet with the code, the browser hand-off, and the server picker, plus save and re-login paths.
- macOS: the same flow with AppKit-styled presentation.
- Documentation: this plan, `ARCHITECTURE.md`, `QUALITY_SCORE.md`, and `todos.md`.

Out of scope: downloads of new Plex content, library-scan persistence changes, CloudKit token sync, multiple simultaneous Plex servers sharing the global credential mirror, and Figma changes.

## Design Decisions

1. **PIN authorization, not passwords.** `POST https://plex.tv/api/v2/pins` (no `strong`) returns `id`, `code` (four characters), `expiresIn` 900 seconds, and a null `authToken`. The app shows the code and opens `https://plex.tv/link`, where the user enters it. The 2026-10-29 iOS walk showed that `app.plex.tv/auth` accepts only strong (25-character) PINs: with a four-character code it rendered the consent page and then "We were unable to complete this request", and the PIN never received a token. It polls `GET https://plex.tv/api/v2/pins/<id>` every two seconds with the same `X-Plex-Client-Identifier` until `authToken` is present. No password is sent or stored.
2. **Discovery through plex.tv.** `GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1` with the account token and client identifier returns resources; keep those whose `provides` contains `server`. Each resource carries `name`, `clientIdentifier`, `productVersion`, `owned`, an optional `accessToken` (shared servers), and `connections` with `uri`, `address`, `port`, `local`, `relay`, and `protocol`.
3. **Endpoint choice and probing.** Order candidates by non-relay first, then local, then https, then IPv4, and probe `GET /identity` with a short timeout in that order; use the first reachable endpoint. Store that endpoint's `uri` in `SavedConnection.host` (scheme, host, and port included) and its port in `SavedConnection.port`, so LAN and remote servers both work without extra columns.
4. **Per-connection token storage.** Save the token through `PlexCredentialStore` under Keychain account `conn_<uuid>_plex`; `PlexService.connect` resolves it from `config.connectionId`. Keep the existing global `plex.token`/`plex.baseURL` mirror updated on connect because the Plex detail, episode, intro-marker, and playback-quality readers still use it. The sign-in flow never writes the token to `SavedConnection`, CloudKit, logs, or a source file. Library-scan `MediaItem` URLs in the local store still embed `X-Plex-Token` (pre-existing behavior; see Risks). When CloudKit duplicates of one Plex identity collapse, `ConnectionIdentity.remapLocalReferences` copies the loser's `conn_<uuid>_plex` token to the winner if the winner has none, matching the password rule.
5. **Legacy fallback.** A saved Plex row that still has a password in `conn_<uuid>` keeps connecting through the old plex.tv signin path and then saves the returned token under `conn_<uuid>_plex`, so later connects are token-first; the PIN flow replaces the add and edit form for new sign-ins. A row with neither a token nor a password fails with `authenticationFailed` and prompts a Plex re-login; it never borrows the global mirror token. No data migration is needed.
6. **Re-login.** Editing an existing Plex connection shows the signed-in account and the current server with a re-login entry. A successful PIN run updates the token and the stored endpoint, and keeps the user's connection name unless the row is new.
7. **No Figma frame exists for this sheet.** Reuse the existing dialog, button, token, spacing, and accessibility conventions of each platform's Add Connection sheet. Do not introduce a new design language, and record this decision in the plan. The `ui-ux-pro-max` run confirmed `Form`, `ProgressView` loading, and error-with-retry guidance; its generated palette and fonts were not applied because existing tokens take precedence.
8. **Identity reuse on save.** Both platforms save through `ConnectionIdentity.resolveForSave` (`type + host + port + username`). Signing in again to the same server and account reuses the existing row and UUID instead of inserting a duplicate that `loadSavedConnections` would collapse, which would orphan the token on a deleted UUID.
9. **macOS catalog playback path.** VanmoMac re-resolves library playback through the connection service. For Plex the remote path is the part path stored in `MediaItem.fileURL` (`/library/parts/...`), not `serverId`, which holds the ratingKey; the 2026-10-29 walk showed the ratingKey path requesting `GET /4`.
10. **No plaintext token on the internet.** `resolveEndpoint` skips plain-`http` candidates that are not marked `local`, so the token is only sent over HTTPS or on the LAN. Post-task review found that the original ranking would probe a remote `http` endpoint before the relay.

## API Contract (VanmoCore)

```swift
public struct PlexPin: Sendable, Equatable {
    public let id: Int
    public let code: String
    public let authURL: URL
    public let expiresAt: Date
    public var isExpired: Bool
}

public struct PlexAccount: Sendable, Equatable {
    public let username: String
    public let email: String?
}

public struct PlexServerConnection: Codable, Sendable, Equatable, Identifiable {
    public let uri: String
    public let address: String?
    public let port: Int
    public let isLocal: Bool
    public let isRelay: Bool
    public let protocolName: String
    public var id: String { uri }
}

public struct PlexServerResource: Codable, Sendable, Equatable, Identifiable {
    public let name: String
    public let clientIdentifier: String
    public let product: String?
    public let productVersion: String?
    public let platform: String?
    public let isOwned: Bool
    public let accessToken: String?
    public let connections: [PlexServerConnection]
    public var id: String { clientIdentifier }
    public var orderedConnections: [PlexServerConnection]
}

public enum PlexAuthError: Error, LocalizedError, Equatable {
    case requestFailed(String)
    case pinExpired
    case authorizationTimedOut
    case authorizationCancelled
    case noServer
    case serverUnreachable(String)
}

public struct PlexAuthAPI: Sendable {
    public init(session: URLSession = .shared, clientIdentifier: String = PlexCredentialStore.clientIdentifier)
    public func createPin() async throws -> PlexPin
    public func awaitAuthorization(pinId: Int, timeout: TimeInterval, pollInterval: TimeInterval) async throws -> String
    public func fetchServers(token: String) async throws -> [PlexServerResource]
    public func fetchAccount(token: String) async throws -> PlexAccount?
    public func resolveEndpoint(for server: PlexServerResource, token: String) async throws -> PlexServerConnection
}

public extension PlexCredentialStore {
    static func saveToken(_ token: String, forConnectionId connectionId: UUID) throws
    static func token(forConnectionId connectionId: UUID) -> String?
    static func deleteToken(forConnectionId connectionId: UUID) throws
}
```

Platform view-model contract (both apps):

```swift
func savePlexConnection(name: String?, token: String, server: PlexServerResource,
                        endpoint: PlexServerConnection, account: PlexAccount?) async -> Bool
func reloginPlexConnection(_ connection: SavedConnection, token: String,
                           server: PlexServerResource, endpoint: PlexServerConnection,
                           account: PlexAccount?) async -> Bool
```

Both methods return whether the connection was saved and scanned, set `errorMessage` on failure, store the token with the connection UUID before connecting, refresh the sidebar selection, request CloudKit sync, and call `connectAndScan`.

## Files

- `Packages/VanmoCore/Sources/VanmoCore/Network/Plex/PlexAuthAPI.swift` (new)
- `Packages/VanmoCore/Sources/VanmoCore/Network/PlexService.swift` (token-first connect, base URL handling, credential store additions)
- `Packages/VanmoCore/Sources/VanmoCore/Models/ConnectionModels.swift` (snapshot `config` carries `connectionId`)
- `Packages/VanmoCore/Tests/VanmoCoreTests/PlexAuthTests.swift` (new)
- `Packages/VanmoCore/Sources/VanmoCore/Localization/*` (new copy through `scripts/generate-l10n.py`)
- `Vanmo/Features/Browser/Views/AddConnectionView.swift`, `Vanmo/Features/Browser/Views/PlexSignInView.swift` (new), `Vanmo/Features/Browser/ViewModels/BrowserViewModel.swift`
- `VanmoMac/UI/Browser/Views/MacAddConnectionView.swift`, `VanmoMac/UI/Browser/Views/MacPlexSignInView.swift` (new), `VanmoMac/UI/Browser/ViewModels/MacConnectionsViewModel.swift`
- `Vanmo.xcodeproj/project.pbxproj` (regenerated by XcodeGen after the new app files)
- `ARCHITECTURE.md`, `docs/QUALITY_SCORE.md`, `docs/exec-plans/tech-debt-tracker.md`, `todos.md`, this plan, and the plan indexes

## Verification

1. `swift test --package-path Packages/VanmoCore --disable-sandbox` (the sandbox blocks SwiftPM's own `sandbox-exec` on this machine) with new `PlexAuthTests` for PIN creation, polling transitions, timeout and cancellation, discovery filtering and ordering, endpoint probing, token-first connect, legacy fallback, and no token in log text.
2. `xcodegen generate` plus `./scripts/check-architecture-guards.sh`.
3. `./scripts/check-app-build.sh ios-simulator` then `./scripts/check-app-build.sh macos`, serially.
4. iOS Simulator walk with `./run_device.sh --simulator`: Plex entry shows the PIN sheet, the code appears, the browser page opens, a completed authorization lists servers, a chosen server lists a library, and one video plays. Capture `simctl` screenshots.
5. Real PMS on both platforms: iOS Simulator and VanmoMac sign in with the operator's Plex account, discover the server, list a section, and play one item. Record sanitized `[Plex]` console lines without codes, tokens, addresses, or media titles.
6. `./scripts/check-harness-docs.sh` after the documentation updates.

## Evidence

Local screenshots and sanitized logs live under `build/plex-pin-evidence/` and are not committed.

1. `swift test --package-path Packages/VanmoCore --disable-sandbox`: 328 tests, 0 failures, 1 skipped. `PlexAuthTests` ran 27 tests; `testPlexCredentialStoreRoundTripsPerConnectionToken` skips because the unsigned test process has no Data Protection Keychain. The app walks below exercise that path.
2. `xcodegen generate` left the committed project unchanged; `./scripts/check-architecture-guards.sh` reported 0 failures.
3. `./scripts/check-app-build.sh` passed serially after the walk fixes (iOS Simulator `20261029-175824-80127`, macOS `20261029-175858-80539`) and again after the post-task review fixes (iOS Simulator `20261029-182958-84122`, macOS `20261029-183030-84448`). No warnings in the Plex files. The review fixes (token handover on identity collapse, relogin re-fetch, disabled Cancel while connecting, no remote plain-HTTP probe) are covered by the package suite and builds only; the real-server walk ran before them.
4. iOS Simulator (agent-operated with `idb`, iPhone 17 Pro simulator, Debug): Add Connection → Plex showed the sign-in entry (`ios-02-plex-form.png`), the sheet showed a live four-character code (`ios-09-pin2.png`), and after the operator entered it at `plex.tv/link` the sheet listed one owned server with Local and Relay badges and the account name (`ios-10-servers.png`). Choosing it probed a local endpoint, saved the connection (`ios-13.png`), listed `Movies` (`ios-14-listing.png`) and three videos (`ios-17-movies.png`), and played one on KSPlayer (`ios-18-playback.png`; `engine=ks fps=29.97 bufferingCount=0`).
5. VanmoMac (operator-driven, agent-monitored logs): sign-in, discovery, local endpoint probe, connect with `auth=connection`, a three-item section import, Files playback, and library-detail playback after the fix in decision 9. The Plex Media Server log showed `206 GET /library/parts/...` for the detail play, and KSPlayer sampled `fps=29.99`/`30.27` with `bufferingCount=0` through the prefetch proxy.
6. Sanitized `[Plex]` lines from both platforms contain phases, counts, and endpoint kinds only. A search for codes, tokens, `plex.direct` hosts, and LAN addresses found none.

Findings during the walks:

- `app.plex.tv/auth` rejects four-character PINs; the browser hand-off now opens `plex.tv/link` (decision 1).
- The host Mac's system HTTP proxy (`127.0.0.1:7890`) routed `*.plex.direct` away from the LAN, so every `URLSession` probe timed out while curl, which ignores the system proxy, succeeded in 1.8 s. The operator added a proxy bypass and declined a LAN HTTP fallback. Recorded in the tech-debt tracker.
- VanmoMac detail playback requested `GET /4` until decision 9; Files playback was unaffected.
- The first macOS attempt ran a VanmoMac process launched on 2026-10-28, because `run_device.sh --macos` activated the running instance instead of the new build. Quitting it and relaunching loaded the new build.

## Risks

- PIN polling survives sheet dismissal by cancelling the UI task; a backgrounded iOS app resumes polling when it returns. Expiry after 900 s shows the expired state with a new-code button.
- Endpoint probing uses only plex.tv-provided URIs with a 4 s timeout per candidate. A system proxy or DNS-rebinding protection that breaks `*.plex.direct` leaves the server unreachable (tech-debt tracker).
- The global `plex.token`/`plex.baseURL` mirror remains single-server for the detail, metadata, and quality readers without a connection snapshot (tech-debt tracker).
- Plex items first saved from Files keep the part path as `serverId`, so their intro markers and detail metadata return 404 (non-fatal; tech-debt tracker).
- Persisted `MediaItem.fileURL` values already embed the token (pre-existing behavior, unchanged).
- The connection keeps one endpoint, the first reachable at sign-in, which is usually a LAN endpoint at home. Away from that network `PlexService.connect` does not rediscover or fall back to remote or relay endpoints, so the user must sign in again (tech-debt tracker).
- Re-login lists every server on the account. Choosing a different server repoints the existing connection UUID, while its library items still come from the previous server.
- Cancel is disabled once a server is chosen, because saving and the first scan are already running.
- iOS evidence is Simulator Debug, not a physical device; CloudKit-imported Plex rows on a second device need their own sign-in and were not walked.

## Progress

- **2026-10-29:** Plan created. Recon confirmed the current password flow, the global credential slot, the redirect-bound OAuth infrastructure, and that no PIN or discovery code exists. Live plex.tv probes confirmed the PIN create/poll shapes and that `/api/v2/resources` requires the account token.
- **2026-10-29:** Implemented `PlexAuthAPI`, per-connection tokens, token-first connect, and the iOS and macOS sign-in sheets. Removed a global-token fallback in `PlexService.connect` that would have reused another server's token for a row without credentials. Both platforms save through `ConnectionIdentity`.
- **2026-10-29:** Real-server walks on the iOS Simulator and VanmoMac passed sign-in, discovery, listing, and playback after switching the browser hand-off to `plex.tv/link` and fixing the macOS Plex catalog playback path. Plan completed.

## Open Decisions

None.