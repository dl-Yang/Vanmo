# iCloud Keychain Password Sync

**Status:** Accepted  
**Decision area:** Credentials / Keychain  
**Date:** 2026-09-03  
**Update trigger:** An explicit request to revisit iCloud Keychain (`kSecAttrSynchronizable`) or to put secrets in CloudKit.

**Decision:** Keep option A. Connection passwords and OAuth tokens stay in the on-device Keychain. Do not enable iCloud Keychain sync. Do not put secrets in CloudKit.

Related: [`../SECURITY.md`](../SECURITY.md), [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md) §5–6, [`../exec-plans/completed/2026-09-02-icloud-debug-device.md`](../exec-plans/completed/2026-09-02-icloud-debug-device.md).

## Current State

CloudKit already syncs non-secret `SavedConnection` configuration. Passwords and OAuth tokens stay in Keychain.

| Fact | iOS | macOS |
| --- | --- | --- |
| Bundle ID | `com.vanmo.app` | `com.vanmo.app.mac` |
| Keychain access group | `$(AppIdentifierPrefix)com.vanmo.app` | `$(AppIdentifierPrefix)com.vanmo.app.mac` |
| `KeychainManager` service | `com.vanmo.app` on both | same |
| Accessibility | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | same |
| `kSecAttrSynchronizable` | not set (defaults to false) | same |
| `kSecUseDataProtectionKeychain` | true | true |

Connection passwords use `conn_<SavedConnection.id>`. OAuth uses `conn_<id>_oauth`. Emby and Plex also keep **global** tokens (`emby.accessToken`, `plex.token`) that are not scoped to a connection id. OpenSubtitles stores its own API key, username, password, and token through the same `KeychainManager`.

The 2026-09-03 activation path handles a missing local password: the edit-connection sheet opens and says iCloud does not sync credentials. A 2026-09-03 macOS Debug run confirmed that path for an iOS-synced Emby connection: `activate type=emby missingCredential=true`, the operator entered the password, then `local save reason=connection-updated` and the home library refreshed.

## Options

### A. Keep on-device Keychain (current)

No entitlement or Keychain attribute change. New devices re-enter passwords. Already implemented.

**Pros**

- Credentials never leave the device through Vanmo.
- No iCloud Keychain dependency, no access-group merge, no item rewrite.
- Matches current Settings copy, privacy text, and `SECURITY.md`.
- Compromise of the Apple ID does not expose NAS / Emby / SFTP passwords stored by Vanmo.

**Cons**

- Synced Emby / SFTP / WebDAV rows stay unusable until the user types the password on that device.
- Automatic connect after CloudKit import fails whenever `conn_<id>` is missing.
- Two platforms cannot read each other's existing items even on the same Mac/iPhone Apple ID, because the access groups differ.

### B. iCloud Keychain (`kSecAttrSynchronizable`)

Keep secrets in Keychain. Do **not** add password fields to CloudStore or CloudKit.

Required to make B work at all:

1. iOS and macOS entitlements both include the **same** access group, recommended `$(AppIdentifierPrefix)com.vanmo.app`. macOS may keep `com.vanmo.app.mac` as a read-fallback during migration.
2. `KeychainManager` (and any OAuth write that should sync) sets `kSecAttrAccessGroup` to that shared group.
3. Drop `ThisDeviceOnly`. Use `kSecAttrAccessibleAfterFirstUnlock`.
4. Set `kSecAttrSynchronizable = true` on items that should sync. Queries must pass `true` or `kSecAttrSynchronizableAny`; a query that omits the key will not see synced items.
5. Rewrite existing items once. Old `ThisDeviceOnly` / non-synchronizable rows do not migrate themselves.
6. The user must enable iCloud Keychain and use the same Apple ID. Vanmo cannot sync Keychain if that system setting is off.
7. Entitlement and Keychain changes require the security review in `SECURITY.md`.

Apple rules that block a naive toggle: synchronizable items cannot use any `ThisDeviceOnly` accessibility; they cannot use `kSecAttrAccess` ACLs; iOS 14 / macOS 11 and later can sync passwords (Vanmo's minimums are iOS 17 / macOS 14).

**Pros**

- Passwords stay in Keychain, end-to-end encrypted by Apple, not visible in CloudKit Dashboard.
- Independent of CloudKit quota and of `NSPersistentCloudKitContainer` export.
- After sync delay, the existing activate / `connectAndScan` path can succeed without the edit sheet.
- One shared group also lets iOS and macOS read the same item on one machine.

**Cons**

- User must turn on iCloud Keychain. There is no Vanmo-only transport if they refuse.
- Sync is eventually consistent. CloudKit configuration can arrive first; missing-password UX must stay.
- Existing `conn_<id>` rows stay local until rewritten.
- Every device on that Apple ID that can run Vanmo can use the password. A shared or compromised Apple ID is a credential leak.
- Accessibility becomes weaker than `ThisDeviceOnly` (item can be restored onto another device of the same account).
- Access-group and Keychain Sharing changes are easy to get wrong (Team ID prefix, query flags, macOS Data Protection Keychain). Silent miss looks like “still no password.”
- Settings copy, privacy wording, and `SECURITY.md` must change. This is not a CloudKit collected type, but it is no longer “credentials never leave the device.”

### C. Passwords in CloudKit / SwiftData

Add a password field on `SavedConnection`.

**Not allowed.** Conflicts with `SECURITY.md`, `ARCHITECTURE.md`, and the iCloud plan out-of-scope rule. CloudKit Dashboard would be able to show the secret. Do not implement.

## Scope If B Is Chosen

B is not one switch. Decide which keys move:

| Key | Sync in a first B slice? | Why |
| --- | --- | --- |
| `conn_<id>` connection passwords | Yes, if B is accepted | Unblocks Emby / SMB / SFTP / WebDAV after CloudKit import |
| `conn_<id>_oauth` | Separate decision | Refresh tokens equal cloud-drive account takeover; same mechanism, higher impact |
| `emby.accessToken`, `plex.token` | No, not as they are | Global, not per connection; syncing would overwrite the other device's session |
| OpenSubtitles API key / password / token | No, unless asked | Unrelated to connection sync |
| Local-folder security-scoped bookmarks | Never via Keychain or CloudKit as a credential | Bookmark data is device-specific; keep restore-access / re-pick |

Recommended first slice if the operator wants B: **only `conn_<id>` passwords**. Keep the missing-password sheet for OAuth and for the case where iCloud Keychain is off or late.

## Feasibility

B is feasible on the current stack. It is a Keychain and entitlements change, not a CloudKit schema change. It needs a paid Team, signed iOS and macOS builds, the same Apple ID, and iCloud Keychain enabled. Simulator Debug is not evidence.

Rough work if accepted: `project.yml` + entitlements, `KeychainManager` write/query/migration, optional OAuth follow-up, Settings / L10n / privacy copy, security review, then a two-device run that proves `conn_<id>` appears on the second device without typing it.

## Operator Decision (2026-09-03)

The operator chose **A**. Option B remains feasible and is not scheduled. Option C stays forbidden.

A later change to B still needs a shared access group, a rewrite of existing `ThisDeviceOnly` items, iCloud Keychain enabled on the Apple ID, and the security review in `SECURITY.md`.
