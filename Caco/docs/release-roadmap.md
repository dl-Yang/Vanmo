# Release Roadmap

## Developer Preview 1

- Open Caco in DevEco Studio.
- App shell loads Library, Files, Search and Settings.
- Domain models, repositories and settings stores are available.
- UI pages render neutral migration scaffolds.

## Developer Preview 2

- Replace in-memory repositories with RelationalStore.
- Implement Preferences-backed settings.
- Wire HUKS-backed credential storage.
- Add seed data import for local testing.

## Media Source MVP

- Emby/Jellyfin connection and paged import.
- WebDAV PROPFIND parser and file browsing.
- Local folder URI picker and sandbox access validation.
- Metadata cache writes posters, backdrops, logos and cast profile assets.

## Playback MVP

- System AVPlayer plays direct HTTP MP4 and local MP4.
- Playback progress persists on pause, background and stop.
- Basic gestures: tap play/pause, drag seek, volume and brightness after device validation.
- Player error states are user-readable and searchable in console logs.

## UI Parity Release

- LibraryHome, MediaDetail, File and Favorites match their Figma nodes.
- Search, Settings, Player and connection forms have Figma designs and implementation.
- Empty, loading, error, disabled and selected states are covered.

## Protocol Expansion

- PrefetchProxy passes Range tests.
- SMB adapter streams through PrefetchProxy.
- Plex media import and XML mapping.
- ijkplayer or FFmpeg NDK supports MKV, AVI, audio tracks and embedded subtitles.

## Known Limitations

- Current player engines are PoC placeholders and do not yet call HarmonyOS media APIs.
- Current repositories use in-memory stores until RelationalStore is wired.
- WebDAV parser is intentionally stubbed until the XML library choice is locked.
- SMB list and download are blocked behind the SMB PoC.
- Search, Settings and Player require Figma designs before final styling.
