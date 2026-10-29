# Files Browser Grid, Video Cards, and Folder-Open Transition

**Status:** Completed  
**Platforms:** iOS (`Vanmo`) and macOS (`Vanmo-macOS`)  
**Design source:** iOS Figma `File` page frames `Files-Grid-Light` (`630:2`), `Files-Grid-Dark` (`630:56`), and `Files-Grid-States` (`631:2`); macOS Figma `Files` page frames `Files-Grid-Light` (`116:407`), `Files-Grid-Dark` (`116:493`), and `Files-Grid-States` (`116:579`)  
**Execution plan:** [`../exec-plans/completed/2026-10-28-files-browser-grid-and-transition.md`](../exec-plans/completed/2026-10-28-files-browser-grid-and-transition.md)

## Behavior

### Layout

- A connection's directory view defaults to a grid with three items per row. A header button switches between grid and list. The button shows the layout it switches to: `list.bullet` in grid mode and `square.grid.2x2` in list mode. The choice persists per device under `files.browserLayout`.
- The grid has two sections: Folders (`文件夹`), then files. The files section is titled `视频` when every item is a video, otherwise `文件`.
- IPTV channel lists always stay a list.
- List mode keeps the existing row design. The video icon box uses the same cover order as the grid.

### Folder tiles

- A folder tile is a rounded accent-tint box with the Files folder glyph and a name of up to two lines.
- iOS pressed state: a darker tint. macOS hover state: a darker tint.
- Tapping a folder swaps the glyph to `FilesFolderOpen` / `MacFilesFolderOpen` and springs the box to 1.08 (iOS) or 1.06 (macOS). The current directory stays visible, with a small spinner on that tile while the folder loads.

### Folder-open transition

- When the child directory arrives, its content scales from 0.2 to 1 at the tapped tile's position while the previous content fades and scales slightly up.
- Back reverses this: the content shrinks into the anchor saved when that level was entered.
- On macOS, breadcrumb jumps pick their direction from path depth.
- Reduce Motion replaces scale with a crossfade.
- A failed load shows the existing error state.

### Video cards

- A video card is a 16:9 rounded cover with the file name below it, on up to two lines.
- Cover order:
  1. Poster: the local library poster, then the media-server poster.
  2. Backdrop: the local library backdrop, then the media-server backdrop.
  3. Extracted keyframe from `VideoThumbnailQueue`. Never used for Emby or Jellyfin.
  4. The default glyph.
- An image that fails to load advances to the next source.
- Emby and Jellyfin episodes use their own Primary image, then the series poster, then the item backdrop, then the parent backdrop.
- An in-progress video shows a bottom progress bar (position ÷ duration). A watched video shows a check badge and no bar.
- The accessibility value reads `已观看 N%` or `已看完`.
- On macOS, hovering a card shows a dim scrim and a play glyph.

### Watch progress

- Local `MediaItem` progress wins. Without local progress, Emby and Jellyfin `UserData` is used.
- Playing a video from Files reuses the matching library item, keyed by connection and server path, or adds one. Progress therefore persists, and cards refresh when the player closes.
- Videos played from Files appear in the local library and history.

## Acceptance

| Behavior | Evidence required | Recorded |
|---|---|---|
| Cover order, progress rules, Emby listing image and progress mapping, library match and insert | `swift test --package-path Packages/VanmoCore` | 2026-10-28 passing (`FileBrowserLibraryTests`) |
| Compile on both platforms | `./scripts/check-app-build.sh ios-simulator` and `macos` | 2026-10-28 both `BUILD SUCCEEDED` |
| iOS grid, list toggle, folder-open and back transition, Emby episode covers | Agent-operated Simulator screenshots and recording | 2026-10-28 recorded (see plan) |
| iOS progress after Files playback, persisted across relaunch, refreshed after close | Simulator walk | 2026-10-28 recorded (see plan) |
| macOS grid, list toggle, hover, folder-open transition, breadcrumb back, Emby episode covers | Agent-operated `Vanmo-macOS` screenshots and recording | 2026-10-28 recorded (see plan) |
| macOS progress after Files playback | Operator or agent walk | 2026-10-28 operator manual walk passed |
| SMB and local folder progress after Files playback | Operator walk | 2026-10-28 operator manual walk passed |
| Physical iPhone walk | Device screenshots and screen recording | 2026-10-28 operator manual walk passed; recording waived by the user for this round |
