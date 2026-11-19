# iOS Subtitles and Appearance

**Product area:** Vanmo iOS player and Settings

## Subtitle Appearance

Settings and the in-player subtitle sheet show the same live preview while the user changes subtitle size, text color, background opacity/color, outline weight (`SubtitleOutlineWeight`: `None / Light / Medium / Heavy`), or position (`Top / Bottom`). The player persists those values as the global subtitle style (`SubtitleStylePreferences`).

Plain text subtitles and attributed text subtitles, including ASS/SSA text, apply the selected size, text color, outline shadow, and background color immediately. Basic attributed font traits should remain when the size is replaced. Attributed subtitles containing real text take precedence over an accompanying image. An attributed attachment containing only the object-replacement placeholder does not outrank the bitmap path. PGS, VobSub, and other bitmap subtitles apply the size control as image scaling; text and background color controls do not recolor bitmap pixels.

Bitmap subtitles first fit proportionally within the available subtitle area and then apply the user's size scale. The 12-, 18-, and 36-point settings must produce visibly different sizes without changing the image aspect ratio or exceeding the safe display width.

The default subtitle size is 18 points everywhere. Settings, the in-player sheet, persisted preferences, and rendered output must not expose different defaults.

## Media Detail Presentation

iOS Media Detail follows Figma `19 · Movie Detail — Above the Fold` (`745:1621`) and `20 · Movie Detail — Full Parallax Scroll` (`745:1783`) using a continuous parallax scroll layout with a `486pt` hero artwork header, multi-stop obsidian/cream melt scrim, and floating `40×40` Liquid Glass back and `More` (`...`) controls (`20pt` horizontal margins, iOS 26 `.glassEffect()` with material fallback on iOS 17–25; a subtle top scrim fades in while scrolling). The hero prioritizes server backdrop imagery with automatic 5-second cross-fade carousel (respecting Reduce Motion and prefetching adjacent frames) when multiple backdrops exist and falls back to poster artwork. Below the hero title, metadata, and capability badges (`4K`, `Dolby Vision`, `HDR10`, `Dolby Audio`, content rating), the primary action row pairs the amber `Play Now` capsule (with `CatPerchingPlayTopRight`) and `48×48` circular Liquid Glass favorite and download controls (preserving TV-show episode picker access even after partial episode downloads complete, and high-contrast download iconography in Day Mode), followed by the synopsis card, horizontal 16:9 episodes with watched (`CatSleepingPillBadge`) and in-progress (`CatPawProgressBar`) states synced from server and local SwiftData, cast & crew with roles, collections, and `MEDIA SPECIFICATIONS`. The `...` More menu provides watched/unwatched toggling (updating series episodes in view), metadata refresh, and system sharing.

## Player Orientation and Picture in Picture

The in-player subtitle-format action appears only when the media exposes at least one embedded subtitle track. Media without embedded subtitles does not show that action; external subtitle appearance remains configurable through global Settings.

On iPhone, playback is presented by a dedicated full-screen UIKit hosting controller that requests a real landscape scene without a UIKit rotation animation. Closing playback places the outgoing player snapshot inside a black window-sized transition cover and restores portrait without a rotation animation. The snapshot remains centered at its original landscape dimensions, so it may crop or letterbox but must never stretch. The player then dismisses and the cover fades away. The underlying detail or tab must not participate in rotation, skew, black flash, or intermediate geometry. iPad keeps its existing orientation and multi-orientation behavior.

For KSPlayer content, returning Home while video is playing automatically starts Picture in Picture when the system reports it as possible. The direct `KSMEPlayer` adapter owns the PiP delegate and preserves playback during inactive/background transitions. Returning to the app restores the player without destroying or pausing its engine. Memory pressure must be diagnosed from a recorded memory warning or termination reason rather than inferred from a disappearing PiP window.

## Appearance

iOS offers exactly three appearance choices:

- Follow System
- Day (`#FAF7F2` warm cream surface with `#B86A08` deep amber accents)
- Night (`#0B0C0E` obsidian surface with `#FFB547` amber glow accents)

Removed light-only custom themes migrate to Day. The migration writes a valid stored value so Settings and the app root share one source of truth. The floating `CatGlassTabBar` renders Night and Day Liquid Glass appearances across all root tabs (`726:1455` / `726:1513`, using iOS 26 `.glassEffect(...)` with iOS 17–25 `.ultraThinMaterial` fallback and `114pt` bottom scrim), while the full-screen video player forces `.environment(\.colorScheme, .dark)` over cinema surfaces. Settings main (`13`) routes into dedicated obsidian/cream glass subpages for iCloud Sync, Playback, Audio, Subtitles (including OpenSubtitles), Library & Scan, Metadata Cache, Appearance & Subtitles (`14`), and Storage & Downloads. macOS appearance behavior is documented in [`../FRONTEND.md`](../FRONTEND.md).

## Acceptance

- Changing text subtitle size or colors in either preview updates the sample immediately.
- The active player reflects in-player changes without reopening playback.
- SRT/VTT and ASS/SSA text follow the selected style; bitmap subtitles change scale only.
- MediaDetail uses Liquid Glass on iOS 26 and the material fallback on older supported systems.
- MediaDetail actions remain tappable during parallax scrolling, and hero artwork prioritizes backdrops with poster fallback.
- iPhone playback enters landscape and returns to portrait; automatic PiP remains visible and playing across one Home/foreground round trip.
- Settings displays only the three supported appearance options and applies each option correctly.

## Evidence Boundary

A Simulator recording proves only the captured UI and subtitle cases. It does not prove physical-device AVAudioSession behavior or every subtitle codec.
