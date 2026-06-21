# Parity Test Plan

## Functional Parity

- App opens to Library tab and can switch between Library, Files, Search and Settings.
- Library shows all media, favorites and recently played sections from repository data.
- File tab lists saved connections and can connect through `RemoteServiceFactory`.
- Emby/Jellyfin import creates `MediaItem` records with poster, backdrop, logo, overview and episode metadata.
- WebDAV browsing issues PROPFIND and returns normalized `RemoteFile` entries once XML parser is wired.
- Player loads a direct HTTP MP4 URI, supports play, pause, seek and persists playback progress.
- Settings read and write theme, metadata, subtitle and playback preferences.

## Visual Parity

- Compare LibraryHome against Figma node `295:6`.
- Compare MediaDetail against Figma node `203:2`.
- Compare File against Figma node `317:80`.
- Compare Favorites against Figma node `322:192`.
- Search, Settings, Player, connection forms and all empty/loading/error states require Figma nodes before final acceptance.
- Validate light/dark handling after design tokens are finalized.

## Performance

- Library cold load under 1 second for 1,000 local records.
- Media grid scroll remains smooth with remote images.
- Emby/Jellyfin import handles paged results without blocking ArkUI.
- Direct MP4 first frame under 2 seconds on local network.
- Seek within buffered MP4 under 500 ms.
- Metadata cache size calculation completes under 500 ms for 5,000 records.

## Security

- Passwords and tokens are never stored in RelationalStore tables.
- Player URIs never contain `user:password@host`.
- Logs never print credentials, cookies, tokens or full credential-bearing URLs.
- PrefetchProxy sessions are memory-scoped and expire on disconnect or app shutdown.
- Downloaded and cached files stay inside the app sandbox unless FileShare is explicitly implemented.

## Device Validation

- Run on at least one HarmonyOS phone and one tablet profile.
- Validate orientation behavior for Player.
- Validate foreground/background transitions during playback.
- Validate network loss and reconnect flows for each enabled protocol.
- Capture local console logs for failures using the `[Caco]` prefix.
