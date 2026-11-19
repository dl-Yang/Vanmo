# macOS Black Cat UI Redesign (Figma 144:2 & Immersive 5-Tab Preferences)

**Status:** Completed  
**Platforms:** macOS (`Vanmo-macOS`), with shared `L10nTable` localization keys in `VanmoCore`  
**Design source:** Figma `Vanmo-MacOS` (`fileKey: O75W1XT1Q0btSrepDwEx39`, page `Black Cat Redesign`, `node-id: 144:2`), `1024×1024` Mac App Icon (`174:1101`), and the five `720×540` Preferences tabs:
- Appearance (`173:1151`)
- General & Sync (`182:1121`)
- Playback (`185:1143`)
- Cache (`186:1177`)
- Subtitles (`189:1196`)

## Goal

Replicate the Figma `Black Cat Redesign` visual language across all `VanmoMac/` surfaces and the `1024×1024` Mac App Icon while preserving existing library, connection, playback, download, and settings behaviors and honoring confirmed platform scope boundaries.

## Implemented Scope

1. **Assets, Icons, & Dual-Theme Design System**
   - Regenerated all 10 PNG sizes in `VanmoMac/Resources/Assets.xcassets/AppIcon.appiconset/` from Figma `174:1101`.
   - Imported 47 new `Mac*.imageset` SVG vector assets (30 core UI/cat illustrations plus 17 `MacPref*` Preferences icons/illustrations; 50 `Mac*.imageset` SVGs total in `Assets.xcassets`, alongside 23 `MacConn*` PNGs and `MacSubtitlePreviewScene.imageset`).
   - Built `MacDesignTokens` / `MacThemeColors` (`VanmoMac/UI/DesignSystem/MacDesignTokens.swift`) for **Night Mode** (`#121316` / `#0B0C0E` + `#FFB547`), **Day Mode** (`#FAF7F2` / `#E5DEC9` + `#18181B` + `#B86A08`), **Follow System** (`preferredColorScheme` + `NSWindow.appearance`), and constant-dark `MacDesignTokens.Cinema` player surfaces.
   - Added reusable Black Cat surfaces, badges, and button styles in `VanmoMac/UI/Components/MacCatUIComponents.swift`, `MacFormatters.playbackRate` in `MacFormatters.swift`, and theme-aware placeholders in `MacRemoteImage.swift`.

2. **Sidebar, Home, Library Views, & Detail**
   - `MacSidebarView` / `MacHeaderToolbar` / `VanmoMacRootView` / `MacAppState`: `⌘F` cat-ear search bar, reordered `LIBRARY` (`Home`, `Continue Watching`, `Favorites`), protocol-badge `CONNECTIONS` rows with `MacCatEyeStatus` / standby dots and `+ ▾` menu, and `Settings ⌘,`.
   - `MacLibraryHomeView`: `21:9` Featured Hero Banner, `Continue Watching`, and `Recently Added` above preserved folder bookmarks and grouped library previews (omitting design-board annotation bubbles).
   - `MacMediaDetailView`: `420px` split-hero backdrop, 4-action bar with perching cat, mark-watched and metadata-refresh inside the `...` More menu, 16:9 `Episodes` cards, preserved `Collections`, and `Cast & Crew`.

3. **Files Browser, Connection Modal, & Direct Links**
   - `MacConnectionsBrowseView` & `MacScanSyncBanner`: 4-column 16:9 grid, inline `Filter in ...` search field, and slim top scan-progress pill with pause/resume/cancel.
   - `MacAddConnectionView`, `MacPlexSignInView`, & `MacDirectLinkView`: `540×600` centered Black Cat glass modal preserving all 22 protocols (dynamic standard form, Plex PIN, OAuth, local folder picker) plus a Direct URL quick jump.

4. **Cinema Player & Three-in-One Track Drawer**
   - `MacPlayerView`, `MacPlayerControlsOverlay`, `MacTrackSelectorView` (`MacPlayerTrackDrawer`), `MacEpisodeSelectorView`, & `MacPlayerViewModel`: cinema-dark HUD with top title/spec pill, `980×92` floating bottom control deck (`15s` skip, `164×92` hover-scrub preview card with leaning cat and `clearScrubPreview()`), and a single `300px` right-side glass drawer (`Audio | Subtitles | Episodes`) consolidating the previous three `.sheet` modals.
   - Per confirmed scope, unimplemented `PiP`, `AirPlay`, `Skip Intro`, and `Prev/Next Episode` buttons remain hidden.

5. **Standalone Downloads & Immersive 5-Tab Preferences**
   - `MacDownloadManagementView` & `MacDownloadHeroOverlay`: preserved standalone `downloads` window styled with Black Cat glass cards, a header task-status summary pill, a local disk-capacity storage bar, grouped task sections, and multi-select/detail-jump actions (`MacDownloadsTray` toolbar target). Note: computing the local disk-capacity bar uses `.volumeTotalCapacityKey` / `.volumeAvailableCapacityForImportantUsageKey` / `.volumeAvailableCapacityKey`, which is recorded in `docs/exec-plans/tech-debt-tracker.md` for `PrivacyInfo.xcprivacy` Disk Space review.
   - `VanmoMacApp` (`Settings` scene) & `MacSettingsWindowView` / `MacSettingsViewModel`: locked `720×540` immersive window using `.windowStyle(.hiddenTitleBar)` and `MacSettingsWindowAccessor` (`.fullSizeContentView`, transparent hidden titlebar, `toolbar = nil`, `.ignoresSafeArea(.all, edges: .top)`, Coordinator-cached `NSWindow.appearance` resetting to `nil` on Follow System) to eliminate the white top bar across all 5 tabs (`General & Sync`, `Playback`, `Subtitles`, `Appearance`, `Cache`), paired with `MacCatAmberToggleStyle`, `22pt` slider hit targets, `16:9` live subtitle preview (`subtitleBackgroundOpacity`), and accessibility labels/traits.

6. **Localization & Project Generation**
   - Added all new macOS redesign English localization mappings in `Packages/VanmoCore/Sources/VanmoCore/Localization/L10nTable.swift` (`0` missing keys).
   - Regenerated `Vanmo.xcodeproj/project.pbxproj` via `xcodegen generate`.

## Visual Audit & Review Hardening

- Audited offscreen `NSHostingView` and real-titlebar `NSWindow` PNG renders across all 7 main modules and all 5 Preferences tabs against Figma frames, resolving layout spacing, top titlebar bleed, Day/Night contrast, and asset-state parity.
- Resolved all post-task code review findings: `ButtonStyle` internal `BodyView` reading `@Environment(\.macTheme)`, `Menu` glass background placement, player drawer empty-area hit-testing, `NSWindow.appearance` Follow System deadlock, slider snapping/hit target sizing, SwiftUI accessibility representations/labels, and removing all temporary `#if DEBUG` screenshot scaffolding before closeout.

## Verification Evidence & Boundaries

- `xcodegen generate`: succeeded (`Vanmo.xcodeproj/project.pbxproj` up to date).
- `./init.sh`: passed all 3 stages after the final edits (`VanmoCore` 364 tests with 1 Keychain test skipped in unsigned CLI and 0 failures; CloudKit/multiplatform and architecture guards 0 failures; Harness docs check 0 failures). Note: `BoxOAuthTests.testConcurrentRefreshIsCoalescedIntoOneOperation` intermittently failed once under timing contention and passed on re-run.
- `./scripts/check-app-build.sh macos`: passed (`20261118-165506-65222`).
- `./run_device.sh --macos`: compiled, signed, registered, and launched `Vanmo-macOS` with `AppIcon.icns`.
- **Scope & environment limits:** `./scripts/check-app-build.sh ios-simulator` previously failed at `lipo` (`No space left on device`) due to local disk exhaustion (`3.0 GiB` remaining after clearing simulator DerivedData) and was not separately re-run during the macOS Preferences closeout because no `Vanmo/` source files changed (`L10nTable.swift` additions only; the combined working tree later passed `ios-simulator` as recorded in `docs/QUALITY_SCORE.md`). Visual checks come from offscreen PNG renders and local macOS launch; an interactive desktop walk across every live data source remains an operator check.
