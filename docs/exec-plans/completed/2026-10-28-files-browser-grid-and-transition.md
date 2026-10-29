# Files Browser Grid, Video Cards, and Folder-Open Transition

**Status:** Completed  
**Created:** 2026-10-28  
**Plan type:** Implementation with simulator and macOS walks  
**Product spec:** [`../../product-specs/files-browser.md`](../../product-specs/files-browser.md)  
**Related architecture authority:** [`../../../ARCHITECTURE.md`](../../../ARCHITECTURE.md) §6.1, §6.2

## Objective

Redesign the Files directory view on iOS and macOS:

- A 3-per-row grid by default, with a list toggle.
- A folder-open transition between directory levels.
- 16:9 rounded video cards with watch progress and the name below.
- Covers chosen in this order: poster, backdrop, extracted keyframe, default glyph.
- Emby episodes in Files show artwork.
- Files playback persists progress, so the cards can show it.

## Scope

1. Figma frames before code:
   - iOS `File` page `Files-Grid-Light` `630:2`, `Files-Grid-Dark` `630:56`, and `Files-Grid-States` `631:2`.
   - The iOS `Icons` page `FilesGlyphs` `632:243` (adds `FilesFolderOpen`).
   - A new macOS `Files` page: `116:407`, `116:493`, and `116:579`.
   - The user confirmed the frames on 2026-10-28.
2. `VanmoCore`:
   - New `RemoteFile` fields: `posterURL`, `backdropURL`, `playbackPosition`, `runtime`, and `isPlayed`.
   - `EmbyService.remoteFiles(fromListing:…)`: image and `UserData` mapping, plus the `EnableUserData` and `EnableImageTypes` listing parameters.
   - `FileCoverResolver`, `FileLibraryState`, and `FileBrowserLibrary` (library match, plus reuse-or-insert for playback).
3. View models (`ConnectionsViewModel`, `MacConnectionsViewModel`):
   - `libraryStates`, refreshed whenever `files` changes and when the player closes.
   - Files playback goes through `FileBrowserLibrary.persistentItem`.
4. UI:
   - iOS `BrowserView.swift`: grid, toggle, `FolderGridTile`, `FileGridCard`, `FilesCoverImage`, and `FolderOpenTransition`.
   - macOS `MacConnectionsBrowseView.swift`: the matching `Mac*` types, hover states, and breadcrumb direction.
   - New template assets: `FilesFolderOpen` (iOS), plus `MacFilesFolder` and `MacFilesFolderOpen` (macOS).
5. Narrow supporting fix: both player view models fill a missing `MediaItem.duration` when they save progress. Without it, Files-created items could not compute a fraction.

## Out of Scope

- Folder posters for Emby Series and Season tiles: folders keep the glyph.
- Episode sort order. Emby listings sort by name, as before.
- The browser title and macOS breadcrumb show Emby item ids instead of names. This is existing behavior and is not changed.
- An adaptive column count. It is a fixed `3` per platform, as requested.

## Verification

| Step | Command or walk | Result |
|---|---|---|
| Package tests | `swift test --package-path Packages/VanmoCore` | 2026-10-28: 300 XCTest tests, 0 failures; `FileBrowserLibraryTests` (13) cover cover order, progress, Emby mapping, library match, and insert |
| Architecture guards | `./scripts/check-architecture-guards.sh` | 2026-10-28: 0 failures |
| iOS compile | `./scripts/check-app-build.sh ios-simulator` | 2026-10-28: `BUILD SUCCEEDED` |
| macOS compile | `./scripts/check-app-build.sh macos` | 2026-10-28: `BUILD SUCCEEDED` |
| iOS Simulator walk (iPhone 17 Pro, iOS 26.0, operated with `idb`) | `./run_device.sh --simulator` | Recorded below |
| Vanmo-macOS walk (operated through accessibility `AXPress`) | `./run_device.sh --macos` | Recorded below |

Local evidence lives under `build/files-grid-evidence/` and is not committed: iOS screenshots and `folder-open-walk.mov` (187.8 s), plus macOS screenshots and `m-folder-open-walk.mov` (35 s).

## Progress Log

- **2026-10-28 Design:**
  - Ran the `ui-ux-pro-max` `--design-system` and `--stack swiftui` searches. Only the lazy-grid, loading, Reduce Motion, and one-or-two-motions guidance was used; the palette and fonts were ignored.
  - Built the Figma frames listed in Scope; the user confirmed them.
- **2026-10-28 iOS Simulator walk (Emby "Reno"):**
  - The connection root opened in the grid with 3 folders per row.
  - Tapping `电视 - 华语` showed the open glyph, the 1.08 scale, and the tile spinner on the old grid (`04a-opening.png`).
  - The series and season levels opened. The episode grid showed per-episode Emby artwork (`06-episodes-grid.png`).
  - The list toggle switched to rows with covers in the icon box (`08-episodes-list.png`).
  - Recording frames show the season content growing from the tapped tile. Back stepped up one level at a time (`25139` → `25108` → `16027`). SMB back stepped `Drop Box` → `银古` → the connection root → the connection list.
- **2026-10-28 iOS progress:**
  - Played episode 1 to 165 s of 2613 s and closed. The first build showed no bar because Files-created items had `duration = 0`. Fixed with the player duration fill and a resolver fallback to the server runtime.
  - After relaunch, the card shows the bar and the accessibility value `已观看 6%`, so the progress persisted.
  - Played episode 2 and closed. The card updated in the same session to `已观看 1%`.
  - Dark appearance screenshot: `16-episodes-dark.png`.
- **2026-10-28 Vanmo-macOS walk (Emby "Reno"):**
  - The grid matches the macOS frame (`m02-reno-grid.png`).
  - Opening `电视 - 华语`, a series, and its season reached the episode grid with Emby artwork (`m04-episodes.png`).
  - Hover shows the scrim and play glyph (`m05-episodes-hover.png`). The list toggle worked.
  - A breadcrumb jump back to `Reno` and the re-open are in `m-folder-open-walk.mov`. The open frames show the new grid scaling in from the tapped tile.

- **2026-10-28 Post-task review fixes:**
  - **Placeholder URLs:** the review found that Files playback persisted resolved stream URLs, which can embed SMB or WebDAV credentials or expire as signed cloud links.
    - File-type rows now store only the `vanmo://playback` placeholder, and reuse never overwrites a stored URL.
    - Media-server rows keep the server stream URL, as the scanner does.
  - **Scans:** no row is inserted while a scan is active.
  - **Covers:** the cover task re-runs extraction when the candidate list changes.
  - **macOS breadcrumbs:** the level count now comes from `pathStack`, so Emby item-id paths work.
  - **Tests:** package tests added for the placeholder insert, placeholder reuse, and the media-server opt-out.
  - Re-ran `swift test` (301 tests, 0 failures), `check-app-build.sh ios-simulator`, and `check-app-build.sh macos` (both `BUILD SUCCEEDED`).
- **2026-10-28 iOS Simulator re-walk after the fix (Yandex.Disk, signed-link file connection):**
  - First play of `J.mp4` from the grid, then close: the card read `已观看 11%` (`20-yandex-progress.png`).
  - Second play from Files: the player resolved the stored placeholder, `engine.load()` succeeded with `startPosition: 14.6s`, and playback started (`21-yandex-replay.png`).
  - After close, the card read `已观看 34%`.

- **2026-10-28 Operator manual walks (reported by the user, no recording):**
  - macOS: play from Files → close → the card shows progress. Passed.
  - SMB and local folder: after playback from Files, the card shows progress. Passed.
  - Physical iPhone: manual walk of the Files grid, transitions, and progress. Passed.

## Risks

- Videos played from Files are now inserted into LocalStore, so they appear in local library and history surfaces. Inserted media-server items opt out of CloudKit progress and favorite sync.
- An inserted row counts toward `ScanLibraryQueries.hasMediaItems`. If a connection's first-connect shallow scan never completed, a Files play stops the next connect from retrying it.
- After a Files play, file-type rows resolve their placeholder through the player's reconnect path, the same as library playback. Each Files play therefore reconnects once more. This was walked on iOS with Yandex.Disk; the operator then confirmed SMB and local folder.
- `refreshLibraryStates` fetches every `MediaItem` for the connection on each directory load. Large libraries could add main-thread work.
- A fixed 3 columns gives very large tiles in a wide macOS window.
- Emby image URLs carry `api_key` in memory, the same as the existing detail mapping. They are not logged.
- The `onGeometryChange` tile frames are taken in the content coordinate space. If a frame is missing, the transition anchors at the centre.

## Decisions

- **2026-10-28:** The user waived the physical-device screenshots and screen recording for this round. The physical-iPhone evidence is the operator's manual walk only. This supersedes the screenshot and recording step listed earlier as an open item.

## Follow-ups

None required. The risks above remain documented.
