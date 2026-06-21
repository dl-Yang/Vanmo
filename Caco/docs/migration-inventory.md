# Vanmo iOS to HarmonyOS Migration Inventory

This document freezes the migration scope for the HarmonyOS NEXT port. It maps the current iOS codebase into HarmonyOS workstreams so implementation can proceed without repeatedly rediscovering the same dependencies.

## Source Modules

| iOS area | Representative files | HarmonyOS target | Risk |
| --- | --- | --- | --- |
| App shell | `Vanmo/App/VanmoApp.swift`, `Vanmo/App/ContentView.swift`, `Vanmo/App/AppState.swift` | ArkUI app shell, tab navigation, global app state | Medium |
| Library | `Vanmo/Features/Library/Models/MediaItem.swift`, `Vanmo/Features/Library/ViewModels/LibraryViewModel.swift` | `domain`, `repositories`, `pages/library` | Medium |
| Browser and connections | `Vanmo/Features/Browser/Models/ConnectionModels.swift`, `Vanmo/Features/Browser/ViewModels/BrowserViewModel.swift` | `domain`, `services/remote`, `pages/files` | High |
| Playback | `Vanmo/Core/Player/PlayerEngine.swift`, `Vanmo/Core/Player/KSPlayerEngine.swift`, `Vanmo/Features/Player/Views/PlayerView.swift` | `player`, `pages/player`, `XComponent` integration | Critical |
| Prefetch proxy | `Vanmo/Core/Player/Prefetch/*` | Local HTTP Range proxy backed by ArkTS services | Critical |
| Remote protocols | `Vanmo/Core/Network/EmbyService.swift`, `Vanmo/Core/Network/PlexService.swift`, `Vanmo/Core/Network/WebDAVService.swift`, `Vanmo/Core/Network/SMBService.swift` | ArkTS HTTP clients, XML parser, SMB adapter | High |
| Metadata | `Vanmo/Core/Metadata/*` | Metadata cache repository and media-server refresh coordinator | Medium |
| Subtitle | `Vanmo/Core/Subtitle/*` | Pure ArkTS parser and overlay state | Low |
| Search | `Vanmo/Features/Search/*` | Repository query plus in-memory filter, later FTS | Low |
| Settings | `Vanmo/Features/Settings/*` | Preferences-backed settings pages | Low |
| Shared UI | `Vanmo/Shared/Components/*`, `Vanmo/Shared/Extensions/Color+Vanmo.swift` | ArkUI components and design tokens from Figma | Medium |

## SDK Replacement Matrix

| iOS dependency | Current role | HarmonyOS choice | Notes |
| --- | --- | --- | --- |
| SwiftUI + UIKit | Main UI and video layer bridge | ArkUI + `XComponent` | UI is rebuilt from Figma rather than translated mechanically. |
| SwiftData | `MediaItem`, `SavedConnection`, `PlaybackRecord` persistence | `@kit.ArkData` RelationalStore | Use explicit schemas and repositories. |
| UserDefaults / `@AppStorage` | Settings and theme | Preferences | Keep setting keys stable and documented. |
| Keychain | Connection passwords and tokens | HUKS-backed encrypted preferences | Never store credentials inside stream URLs. |
| AVFoundation | System player and media probing | HarmonyOS AVPlayer / media kit | First milestone supports common MP4/MOV streams. |
| KSPlayer + FFmpeg | Complex formats, MKV, advanced tracks | HarmonyOS ijkplayer or FFmpeg NDK | Requires PoC before full feature commitment. |
| Network.framework | Local prefetch HTTP listener | ArkTS socket / HTTP server capability | Must verify Range, concurrent reads, lifecycle behavior. |
| SMBClient | NAS listing and stream URLs | ArkTS SMB adapter plus PrefetchProxy | NDK `libsmbclient` remains fallback. |
| SWXMLHash | WebDAV PROPFIND parsing | `xml.ConvertXML` or `fast-xml-parser` | Use safe optional access in ArkTS. |
| Kingfisher | Remote images and cache | ArkUI `Image`, optionally ImageKnife | Native Image is the default for MVP. |
| lottie-ios | Loading animation | HarmonyOS Lottie option or static fallback | Not blocking for playback MVP. |

## Migration Gates

1. The app shell builds and opens the four primary tabs.
2. RelationalStore schema can create, insert, update and query media records.
3. At least one media-server or WebDAV source can browse files and create media records.
4. The player can open a direct HTTP MP4 URL and persist playback progress.
5. PrefetchProxy passes Range request tests before SMB playback is enabled.
6. Every visible UI screen has a Figma node or an explicit placeholder pending design.
