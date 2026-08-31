# AList Connection Validation

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-08-30  
**Plan type:** Implementation plus real-source acceptance  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that an AList instance can be added as the AList connection type, browsed over WebDAV, played, and downloaded on both Vanmo iOS and VanmoMac.

## Scope

- Manual Files add-connect-list-play using `WebDAVService(type: .alist)`.
- Dual-platform evidence under the shared rules in [`../active/index.md`](../active/index.md).
- Product-specific defaults: port `5244`, path `/dav`, AList account credentials.
- Files-browser download of one listed video, plus local play of the completed file.
- Narrow fixes required by the real-source run: browse at the configured WebDAV mount, and send remote HTTP `.mp4`/`.mov`/`.m4v` through KSPlayer.

## Out of Scope

- Treating a generic WebDAV pass as AList evidence
- Aggregated third-party drive rate limits beyond noting a play failure
- Library-scan persistence, playback-progress sync, CloudKit, or Figma
- Changing AList form defaults (HTTPS remains on unless the operator pastes `http://` or turns it off)

## Prerequisites

- A reachable AList instance with WebDAV enabled
- An AList username and password
- Path `/dav` unless the operator records a different mount

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and add AList.
2. Confirm `[WebDAV] PROPFIND probe` returns 207 or 200, then `[WebDAV] Connected`.
3. Confirm `[WebDAV] Found N entries` and a visible directory listing.
4. Play one listed video. Record the engine path.
5. Download one listed video and play the completed local file.
6. Repeat add, connect, list, play, and download on VanmoMac with `./run_device.sh --macos`.
7. Paste sanitized `[WebDAV]` lines. A 404 should mention `/dav`.

The plan completes only when both platform runs pass.

## Log prefix

`[WebDAV]`

## Risks

- AList WebDAV may be disabled even when the HTTP UI works.
- HTTPS scheme and port can disagree with the instance.
- Some aggregated sources return a listing but fail direct streaming.
- macOS Local Network TCC can block LAN HTTP even when `NSLocalNetworkUsageDescription` is present.
- AList site root `/` rejects PROPFIND with 405; the WebDAV mount is `/dav`.

## Progress

- **2026-08-28:** Validation plan created. No real AList connect, list, or play run is recorded.
- **2026-08-29:** Operator provided LAN AList `http://192.168.31.59:5244`. Unauthenticated GET `/` returned 200 and PROPFIND `/dav` returned 401, so WebDAV is enabled. Credentials stay operator-entered.
- **2026-08-29:** iOS add-and-save produced `传输失败：PROPFIND 405`. Unauthenticated PROPFIND `/` is 405 (AList web UI); PROPFIND `/dav` is 401. Connect probed `/dav` then the file browser listed `/`. Browsing now starts at the configured mount (`/dav`) and `WebDAVService` remaps listing `/` to that mount.
- **2026-08-29:** After the path fix, iOS listed `/dav` (PROPFIND 207). Remote `.mp4` play failed with AVPlayer `Cannot Open`; the same file played after download. Prefetch HEAD probe succeeded. Engine selection now sends remote HTTP `.mp4`/`.mov`/`.m4v` through KSPlayer, matching local downloads.
- **2026-08-30:** iOS Simulator replay passed: PROPFIND 207, listing, KSPlayer + prefetch `source=http`, `readyToPlay` duration 147s, `playing`. Operator confirmed Files-browser download and local play of the downloaded file.
- **2026-08-30:** First VanmoMac select failed with Network path `unsatisfied (Local network prohibited)` and a later ATS secure-connection error. After Local Network permission, the second VanmoMac run passed connect, list, KSPlayer prefetch play, download, and local play.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-29 / 2026-08-30 |
| iOS | iPhone 17 Pro simulator, Vanmo Debug |
| macOS | Vanmo-macOS Debug |
| Source | LAN AList at `http://192.168.31.59:5244`, WebDAV path `/dav` |

Credentials, complete authenticated URLs, and private media titles are omitted.

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Add AList and save | Pass | Pass (after Local Network grant) |
| 2. Connect | Pass (`Probe status: 207`, `Connected … at /dav`) | Pass (`Probe status: 207`, `Connected`) |
| 3. First listing | Pass (`Found 1` under `/dav`, then `Found 23` under a media folder) | Pass (`Found 1`, then `Found 23`) |
| 4. Play listed video | Pass (KSPlayer, prefetch `source=http`, duration 147s, `playing`) | Pass (`MacKSPlayerEngine`, `[MacPlayerVM] KS using prefetch proxy`, `load complete`) |
| 5. Download and local play | Pass (operator; same file that failed remote AVPlayer) | Pass (operator) |
| 6. Sanitized logs | Pass | Pass (os.Logger redacted hosts as `<private>`) |

## Sanitized logs

iOS Simulator:

```
[WebDAV] PROPFIND probe: http://192.168.31.59:5244/dav
[WebDAV] Probe status: 207
[WebDAV] Connected to http://192.168.31.59:5244 at /dav
[WebDAV] Found 1 entries under /dav
[EngineFactory] 选择 KSPlayerEngine (KSPlayer/FFmpeg)
[Prefetch] registered session token=01F8F4FC… port=54387 source=http
[PlayerVM] using prefetch proxy for remote URL
[KSEngine] readyToPlay, duration: 147.000000s
[PlayerVM] state changed: playing
```

VanmoMac (second run; first run was Local Network / ATS):

```
[WebDAV] Probe status: 207
[WebDAV] Connected to <private> at <private>
[WebDAV] Found 1 entries under <private>
[WebDAV] Found 23 entries under <private>
[MacEngineFactory] 选择 MacKSPlayerEngine (KSPlayer/FFmpeg)
[Prefetch] listener ready on port 57325
[MacPlayerVM] KS using prefetch proxy for remote URL
[MacKSEngine] load complete
```

## Open Decisions

None.

## Follow-ups

- macOS Local Network TCC remains an operator step; the app already declares `NSLocalNetworkUsageDescription`.
- AList form still defaults HTTPS on. Pasting `http://host:5244` or turning HTTPS off is required for a typical LAN instance.
