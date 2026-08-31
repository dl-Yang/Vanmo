# Active Execution Plans

Active plans include not-started, in-progress, or blocked work that still requires evidence.

This index also holds the shared dual-platform acceptance rules for the untested remote-connection validation set. Emby, Jellyfin, generic WebDAV, and SMB are excluded because the operator already treated those four as tested. Repository-recorded evidence exists for SMB (completed connect-and-play plans) and Emby (QUALITY HTTP-via-Emby catalog, play, and download runs). Jellyfin and generic WebDAV have no dedicated completed plan or product spec in this repository.

## Shared Dual-Platform Acceptance

These rules apply to every plan listed below. A validation-only plan does not authorize implementation expansion. If a run exposes a defect, record it and open a separately scoped fix.

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device, and VanmoMac with `./run_device.sh --macos`.
2. Open Files and add the named connection type. Implemented protocols save or complete OAuth login. Official-cloud placeholders (115, Quark, MEGA) stop at the disabled Save control and the official-access caption; do not require a saved connection or listing.
3. Confirm connect using that plan's log prefix. A compile, launch, or unit test is not a real connection.
4. Confirm the first listing shows readable directories, files, or media items. SFTP, NFS, and DLNA instead confirm the documented empty list or unsupported stream. Official-cloud placeholders do not reach listing.
5. For implemented protocols, play one listed video and record the engine path. iOS often uses a direct URL or KSPlayer. macOS remote HTTP should use the localhost prefetch proxy.
6. Copy sanitized Console lines. Do not record passwords, tokens, complete authenticated URLs, or private media titles.
7. iOS evidence does not prove macOS. Both platforms must pass before a plan can move to `../completed/`.

Out of default scope for this set: downloads, library scan persistence, playback-progress sync, CloudKit, physical-device XCUITest, and Figma changes.

Suggested run order for remaining implemented sources: Plex, fnOS, IPTV, local folder, Google Drive, Baidu Netdisk. Advance one plan at a time. AList connect, list, play, and Files-browser download are recorded under `docs/exec-plans/completed/`. FTP real-source connect, list, play, and download are recorded under `docs/exec-plans/completed/`. The FTP placeholder expected-failure record remains under `docs/exec-plans/completed/`.

## Current Plans

### Implemented, ready to run

- [`2026-08-28-plex-connection-validation.md`](2026-08-28-plex-connection-validation.md) — **Not started.** plex.tv sign-in, PMS listing, and play
- [`2026-08-28-fnos-connection-validation.md`](2026-08-28-fnos-connection-validation.md) — **Not started.** fnOS WebDAV connect, list, and play
- [`2026-08-28-iptv-connection-validation.md`](2026-08-28-iptv-connection-validation.md) — **Not started.** M3U/M3U8 channel list and live play
- [`2026-08-28-local-folder-connection-validation.md`](2026-08-28-local-folder-connection-validation.md) — **Not started.** Security-scoped folder bookmark, list, and play
- [`2026-08-28-google-drive-connection-validation.md`](2026-08-28-google-drive-connection-validation.md) — **Not started.** Configured OAuth login, browse, and Bearer play
- [`2026-08-28-baidu-netdisk-connection-validation.md`](2026-08-28-baidu-netdisk-connection-validation.md) — **Not started.** Implicit OAuth login, browse, and ephemeral dlink play

### Implemented, blocked on OAuth credentials

- [`2026-08-28-onedrive-connection-validation.md`](2026-08-28-onedrive-connection-validation.md) — **Blocked.** Client ID empty; login stays disabled
- [`2026-08-28-box-connection-validation.md`](2026-08-28-box-connection-validation.md) — **Blocked.** Client ID and secret empty; login stays disabled
- [`2026-08-28-pcloud-connection-validation.md`](2026-08-28-pcloud-connection-validation.md) — **Blocked.** Client ID and secret empty; login stays disabled
- [`2026-08-28-yandex-disk-connection-validation.md`](2026-08-28-yandex-disk-connection-validation.md) — **Blocked.** Client ID and secret empty; login stays disabled

### Placeholder or unsupported expected failure

- [`2026-08-28-sftp-connection-validation.md`](2026-08-28-sftp-connection-validation.md) — **Not started.** Logical connect, empty listing, unsupported stream
- [`2026-08-28-nfs-connection-validation.md`](2026-08-28-nfs-connection-validation.md) — **Not started.** Generic HTTP placeholder, empty listing
- [`2026-08-28-dlna-connection-validation.md`](2026-08-28-dlna-connection-validation.md) — **Not started.** Generic HTTP placeholder, no SSDP discovery
- [`2026-08-28-drive115-connection-validation.md`](2026-08-28-drive115-connection-validation.md) — **Not started.** Official-cloud placeholder; save disabled
- [`2026-08-28-quark-drive-connection-validation.md`](2026-08-28-quark-drive-connection-validation.md) — **Not started.** Official-cloud placeholder; save disabled
- [`2026-08-28-mega-connection-validation.md`](2026-08-28-mega-connection-validation.md) — **Not started.** Official-cloud placeholder; save disabled

## Rules

- Keep one file per bounded plan.
- Update status, progress, risks, and decisions from factual evidence.
- Do not expand implementation from a validation-only plan.
- Move a plan to `../completed/` only when its required evidence is recorded.
