# iOS Liquid Glass TabBar, Player UI, and App Icon Redesign

**Status:** Completed
**Plan type:** iOS Liquid Glass UI update and Figma fidelity verification
**Related product specs:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Upgrade the iOS `CatGlassTabBar`, full-screen `PlayerView` chrome, and iOS `AppIcon` to replicate the Liquid Glass components and screens in Figma `Vanmo-Ios` (`miM6YTQAnerz6SgkkYZMjo`, page `656:2`): `Liquid Glass TabBar Component` (`726:1455` / `726:1513`), `17 · Liquid Glass Player — Scrubbing Preview (852×393)` (`732:1536`), `18 · Liquid Glass Player — Popover & HUD (852×393)` (`732:1631`), `Liquid Glass Player Icons` (`732:1511`), and `Vanmo — iOS App Store Icon (1024×1024)` (`721:1457`), while keeping playback functionality and unrelated screens unchanged.

## Scope

- Replace `Vanmo/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png` with the `1024×1024` opaque 24-bit RGB PNG exported from Figma `721:1457`.
- Add `View.catLiquidGlass(...)` in `Vanmo/Shared/Components/CatUIComponents.swift` using iOS 26 `.glassEffect(...)` with `.ultraThinMaterial` fallback on iOS 17–25; update `CatGlassTabBar` (`68pt` height, sliding `matchedGeometryEffect` active pill, `10×9` `CatPawDot`, 4 clean `CatLGTab*` template SVGs across Night and Day modes) and `CatBottomBarScrim` (`114pt`, 0→0.55 gradient) plus `ContentView` bottom padding.
- Redesign `PlayerView.swift`, `PlayerProgressBar.swift`, `TrackSelectorView.swift`, and `AirPlayRouteButton.swift` with `.environment(\.colorScheme, .dark)` forced on cinema surfaces, `40pt` top capsules (including `45×40` icon-only `CatLGCatSliders` toggle and full `40×40` hit-target AirPlay), floating `PlayerProgressBar` (`5pt` glass track, `20×20` lens bead thumb, `144×82` scrub preview card), split `44pt` bottom transport/quick-action islands, `42pt` `VerticalGestureHUD` brightness/volume capsules, and `272pt` `ViewThatFits` `PlayerTracksPopover` (`字幕 / 音轨 / 画质 / 倍速`).

## Out of Scope

- Altering `PlayerViewModel` playback/prefetch/subtitle orchestration or non-TabBar/non-Player iOS screens.
- Altering macOS (`VanmoMac/`), `VanmoCore`, SwiftData schemas, or `project.yml` targets.

## Required Verification

- `./init.sh` (`VanmoCore` suite, CloudKit/multiplatform scope & architecture guards, Harness documentation checks)
- Agent-operated iOS Simulator walk (`./run_device.sh --simulator` + `simctl` screenshots + `idb` interactions) comparing Dark/Day TabBar, Home Screen AppIcon, and landscape Player (`17` scrub preview, `18` popover & vertical brightness HUD) against Figma
- Post-task code review (`post-task-code-reviewer` subagent) and re-verification

## Risks

- Isolated evidence compile `./scripts/check-app-build.sh ios-simulator` failed at the linker (`ld: write() failed, errno=28`, `No space left on device`) when local root disk free space hit `191 MiB`; clearing that partial `build/app-build-evidence/DerivedData/ios-simulator` artifact restored `2.2 GiB`, and `./run_device.sh --simulator` built, signed, installed, and ran Debug `Vanmo` on iPhone 17 Pro (`iOS 26.0`). On the combined working tree, isolated `./scripts/check-app-build.sh ios-simulator` and `macos` subsequently passed in [`2026-11-19-ios-media-detail-redesign.md`](2026-11-19-ios-media-detail-redesign.md).
- Physical-device `iOS 26` / `iOS 17–25` visual checks remain separate from iPhone 17 Pro Simulator evidence.

## Decisions

- Avoided nesting `.glassEffect` inside the selected `CatGlassTabBar` pill (which blurred the active icon/text during the first Simulator screenshot); kept `.glassEffect` on the outer bar capsule and rendered the sliding indicator with tinted translucent overlays + `1pt` specular stroke + glow shadow.
- Stripped alpha from `AppIcon.png` via `PIL` (`hasAlpha: no`) after code review flagged the Figma PNG export's 8-bit RGBA header (`ITMS-90717` risk).
- Preserved existing `CatTabSearchActive` and legacy icons for untouched screens (`SearchView`) and added dedicated `CatLG*` SVG imagesets for the updated TabBar and Player.

## Progress

- 2026-11-19: Inspected Figma `726:1455`, `726:1513`, `732:1511`, `732:1536`, `732:1631`, and `721:1457`; replaced `AppIcon.png` and added 10 `CatLG*` SVG imagesets.
- 2026-11-19: Implemented `catLiquidGlass`, `CatGlassTabBar`, and `CatBottomBarScrim`; verified Night Mode, Day Mode, tab switching, and Home Screen AppIcon on iPhone 17 Pro Simulator (`simctl` screenshots).
- 2026-11-19: Implemented Liquid Glass `PlayerView`, `PlayerProgressBar`, `PlayerTracksPopover`, and `AirPlayRouteButton`; walked live Emby playback (`三体` S01 E09 4K) on iPhone 17 Pro Simulator and captured controls, `ViewThatFits` compact Popover, slow-drag Scrubbing Preview, Vertical Brightness HUD, and close-to-Home transitions.
- 2026-11-19: Completed `post-task-code-reviewer` review and fixed all blocking/non-blocking items: stripped AppIcon alpha (`hasAlpha: no`), expanded `AirPlayRouteButton` to `40×40` hit target, added `.allowsHitTesting(false)` to `feedbackOverlays`/`rateBoostIndicator`, expanded bottom transport button hit targets, added `.layoutPriority(1)` to top-bar badges, rounded HUD percentages, increased `CatBottomBarScrim` to `114pt`, and added `#Preview` blocks.
- 2026-11-19: Re-verified final build on Simulator (`./run_device.sh --simulator` with `玩具总动员 5` playback screenshot) and passed `./init.sh` (361 `VanmoCore` tests at Liquid Glass closeout prior to the subsequent `MediaDetail` tests, static architecture guards, Harness docs check, Exit 0). After merging with `MediaDetail` doc sync on the combined tree, `./init.sh` passed all three stages (`364` `VanmoCore` tests with 1 Keychain test skipped in the unsigned process and 0 failures, static guards, Harness docs check, Exit 0).

## Next Step

None for this plan.
