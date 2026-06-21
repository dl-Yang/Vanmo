# Caco

Caco is the HarmonyOS NEXT migration workspace for Vanmo. All HarmonyOS project files for the port live under this directory.

## Scope

- Runtime: HarmonyOS NEXT
- Language: ArkTS
- UI: ArkUI
- Data: RelationalStore, Preferences and encrypted credential storage
- Playback: system AVPlayer first, ijkplayer or FFmpeg NDK after PoC
- Design source: Figma `Vanmo-Ios`

## Directory Layout

```text
Caco/
├── AppScope/                 # App-level HarmonyOS metadata
├── docs/                     # Migration docs, test plans and release notes
├── entry/                    # Main HarmonyOS entry module
│   └── src/main/
│       ├── ets/
│       │   ├── common/       # App state, routing, theme, logging
│       │   ├── components/   # Reusable ArkUI components
│       │   ├── data/         # RelationalStore schemas and repositories
│       │   ├── domain/       # Cross-platform domain models
│       │   ├── pages/        # ArkUI pages
│       │   ├── player/       # Player engines and proxy interfaces
│       │   ├── services/     # Remote services and metadata services
│       │   └── viewmodels/   # Page state and orchestration
│       └── module.json5      # Module permissions and routing
└── oh-package.json5
```

## Migration Milestones

1. App shell opens Library, Files, Search and Settings tabs.
2. RelationalStore schemas can persist media, connections and playback records.
3. One HTTP-based remote source can browse and import playable media.
4. Player MVP can open a direct HTTP MP4 stream and persist progress.
5. Figma-backed LibraryHome, MediaDetail, File and Favorites screens reach visual parity.
6. SMB and complex containers are enabled only after PrefetchProxy and player PoCs pass.
