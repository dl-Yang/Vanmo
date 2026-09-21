# iOS Stability and Experience Fixes

**Status:** Completed
**Plan type:** Defect fixes and UI correction
**Related product specs:** [`../../product-specs/ios-subtitles-and-appearance.md`](../../product-specs/ios-subtitles-and-appearance.md), [`../../product-specs/downloads.md`](../../product-specs/downloads.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Close the reported TestFlight audio-output crash path and correct iOS subtitle styling, detail interaction and artwork, download-detail artwork, appearance choices, orientation transitions, and automatic Picture in Picture.

## Final Scope

- Configured every iOS `KSMEPlayer` path to select `AudioRendererPlayer` before player, probe, or thumbnail instances are created.
- Applied persisted size and colors live to plain and rich text while preserving rich-text precedence; bitmap subtitles fit proportionally and then apply the user size scale.
- Hid the in-player format action when no embedded subtitle track exists.
- Restored reliable detail action hit testing, bounded panel gestures, progressive low-resolution-to-high-resolution artwork, and iOS 26 Liquid Glass actions.
- Separated episode backdrops from series posters in download requests and detail navigation.
- Reduced iOS appearance to Follow System, Day, and Night with migration from retired light-only themes.
- Replaced SwiftUI scene/content rotation with a dedicated UIKit landscape hosting controller. Entry and exit orientation updates are nonanimated and generation-guarded; the exit snapshot preserves its landscape aspect ratio while portrait geometry is restored.
- Configured and observed direct KSPlayer Picture in Picture lifecycle without remote diagnostics.

## Out of Scope

- Recoloring PGS, VobSub, or other bitmap subtitles.
- macOS UI or appearance changes.
- A general KSPlayer fork or replacement.
- The Simulator-only `MTLSimDriver -> MetalRender.textures` assertion for 10-bit HEVC; no matching physical-device stack was observed.
- Claiming that a finite device journey proves the app can never crash.

## Verification

- `swift test --package-path Packages/VanmoCore --filter DownloadTests` passed 10 tests.
- The final `./init.sh` baseline passed 209 tests plus architecture and documentation guards.
- `./scripts/check-app-build.sh ios-simulator` passed after the final orientation changes.
- Simulator and physical-device builds installed and launched during development.
- The required post-task reviews reported no blocking findings after their fixes were applied.
- **2026-09-21 operator acceptance passed:** real landscape player return to portrait without detail skew, shake, black flash, or intermediate landscape UI; all tabs remained portrait.
- **2026-09-21 operator acceptance passed:** ASS/rich text displayed with precedence, PGS changed size live at 12/18/36 points, and media without embedded subtitles hid the format action.
- **2026-09-21 operator acceptance passed:** automatic PiP remained healthy.
- **2026-09-21 operator acceptance passed:** detail back/favorite actions, bounded panel gestures, and blurred-thumbnail-to-high-resolution artwork transition worked without a white frame.
- **2026-09-21 operator acceptance passed:** episode-download navigation used the series poster, and Appearance exposed only Follow System, Day, and Night.

## Key Decisions

- Credentials, authenticated URLs, and remote diagnostics remain outside logs.
- iPhone playback uses a real landscape UIKit hosting controller; iPad keeps its existing orientation.
- Orientation updates temporarily disable UIKit animation and ignore stale request callbacks by generation.
- A window-sized black transition cover owns a fixed-size centered player snapshot so scene geometry changes can crop or letterbox it but never stretch it.
- The generated Xcode project remains sourced from `project.yml`; Xcode formatting drift is repaired with `xcodegen generate`.

## Remaining

- None for this plan.
