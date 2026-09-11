# Library Scan and File Covers

**Product area:** Vanmo and VanmoMac Home scanned libraries, Files browser  
**Source scope:** Shared `VanmoCore` scan, identification, clustering, and thumbnail cache; iOS and macOS connect and Files UI.

## User-Visible Behavior

Saving or activating a file-based connection (SMB, WebDAV, local folder, cloud drives, FTP/SFTP, and similar) automatically scans the outermost path the first time this device has no local rows: videos in the browser root and in each immediate subfolder. Deeper folders are not entered until the user syncs that directory. A later connect does not scan that tree again. If local rows exist but some still have no poster, only those covers are extracted. Emby, Jellyfin, and Plex keep their existing server metadata flows.

If that shallow scan finds no movies or clustered shows, the connection does not appear as a Home media-library row. Manual "sync this directory" still imports a deeper tree.

Filenames are parsed into a movie or series name. Videos in one folder that share the same series name and episode pattern (at least two distinct episode numbers) become one show. Episode titles drop the series name and show "第 N 集" / "Episode N". The first episode's poster is the show poster. Unrelated files in the same folder stay separate.

When a scanned item has no server poster, Vanmo extracts a nearby keyframe into a local JPEG at the source frame size and uses it as the poster. Files-browser video rows use the same cache; extraction failure keeps the current file icon. Google Drive covers use the same authenticated prefetch path as play (Bearer). Baidu Netdisk covers use the official `filemetas thumb=1` JPEG (`thumbs.url3` preferred) instead of opening the download `dlink` in KSPlayer; a missing official thumb leaves the file icon and does not wait for a 20s keyframe timeout.

**Current acceptance status:** In progress. Shared tests cover identification, clustering, shallow options, resume-cover trigger, path-key, thumbnail cache, Google/Baidu streaming-header routing, Baidu official `thumbs` parse order, and official-poster skip-keyframe. A 2026-09-09 iOS SMB walk recorded first-connect shallow scan, four KSPlayer covers, Files play after close-drain, reconnect `connectOnly`, and Home/scanned posters opening the tapped item. A 2026-09-11 iOS Simulator Baidu walk recorded official `filemetas` thumbs (`hasThumb=true`, `skipKeyframe`, no 20s prefetch timeout), one `dlink` play (`skip prefetch`, KSPlayer `readyToPlay`), reconnect `resumeCovers` only, cancelable deep directory sync, and LocalStore cleanup after delete. The same day, Vanmo-macOS re-authenticated an imported Baidu connection, listed 19 Files entries, inserted 4 local catalog rows, and played with `KS official download link, skip prefetch` plus `load complete`. Scanned `MediaItem` rows and JPEG covers stay on-device; CloudKit syncs the connection and later `CloudMediaState` only. Google Drive cover walks are not yet recorded. Other cover surfaces are out of scope and are not required to close this acceptance.

## Acceptance Criteria

1. A new local file-based connection with videos in the root or one folder down appears on Home as Movies and/or TV.
2. A new local file-based connection whose outermost path has no videos does not show a Home library row.
3. `咒术回战第01集.mp4` through `第05集` in one folder become one show titled 咒术回战, with episode titles "第 1 集" … "第 5 集" (or the English episode label).
4. A sidecar movie or extra in that folder is not forced into the show.
5. Two folders with the same show name stay two shows.
6. Scanned items without a server poster receive a local keyframe image when extraction succeeds.
7. Files video rows show that frame when available and the existing file icon when not.
8. Manual deep directory sync and media-server artwork are unchanged.
9. Reopening a connection that already has local rows does not scan the remote tree again.
10. Reopening a connection that has local rows with missing posters resumes cover extraction only.
11. Home and scanned-library detail navigation opens the item that matches the tapped poster.

## Evidence Rules

- Package tests prove parser, cluster, grouping, shallow options, and cache-key behavior.
- An app Debug compile proves the iOS and macOS UI wiring.
- A real NAS first-connect walk is optional for grade B and required before claiming production readiness for a specific protocol.
