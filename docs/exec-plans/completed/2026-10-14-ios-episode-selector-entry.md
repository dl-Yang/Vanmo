# iOS Player Episode Selector Entry

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Make episode switching discoverable in the iOS full-screen player. Before this change,「选集」was reachable only from the long-press menu on the top-left button group, and an operator could not find it during the 2026-10-12 item-switch walk.

## Scope

- Figma state `iOS Video Player UI / Episodes` (`619:2`) in the Vanmo iOS file, page `Player`
- The bottom-right media controls in `Vanmo/Features/Player/Views/PlayerView.swift` become the Figma glass capsule, with an episode button at the left when `canSelectEpisode` is true

## Out of Scope

- Episode data loading (`PlayerViewModel.loadEpisodesIfNeeded`) and the episode sheet
- Series metadata for Files-tab items, which stay without the button
- The Figma speed icon in that capsule: the code keeps its scale button, and speed stays in the top-bar long-press menu
- macOS player chrome

## Verification

- `./scripts/check-app-build.sh ios-simulator`
- Physical-device recording: a library episode shows the button, tapping it opens the episode sheet, and choosing another episode plays it
- Agent-operated Simulator screenshot: a local movie shows the three-button capsule without the episode button
- Evidence files stay local under the untracked `tem/episode-entry/` and are not committed

## Risks

- The capsule has a fixed 48 pt height and is 192 pt wide with four buttons. The iPhone player is landscape-only, so it fits beside Skip Intro; a narrow iPad Slide Over width has little spare room.

## Progress Log

- 2026-10-14: Ran the `ui-ux-pro-max` design-system search (it only reinforced dark, high-contrast, uncluttered chrome). Added Figma frame `619:2`, a clone of `606:6` with a 20 pt stacked-card icon at the left of the bottom-right capsule (capsule width 150 to 194). The operator approved it and chose to convert the code's separate glass circles to the Figma capsule. Implemented `mediaActionCapsule` with 44 pt-wide buttons inside an 8 pt-padded `playerGlassCapsule`, plus accessibility label 选集 and identifier `player.episodes`.

- 2026-10-14: `./scripts/check-app-build.sh ios-simulator` passed (`20261014-094535-98228`). `./run_device.sh --install-only` installed the build on the iPhone 17 Pro. Operator recording `tem/episode-entry/ScreenRecording_10-14-2026 09-52-52_1.mov` (62 s) shows, on an Emby series episode opened from the library, the four-button capsule (stacked-card 选集, subtitles, audio, scale); tapping 选集 opens the episode sheet with two episodes; choosing the other episode loads and plays it. The operator supplied no still screenshots, so `tem/episode-entry/capsule.jpg` is a frame cropped from that recording. Agent-operated Simulator capture `tem/episode-entry/sim-movie.png` (iPhone 17 Pro Simulator, local file through `VANMO_DEBUG_PLAY_FILE`) shows the three-button capsule without the episode button.

- 2026-10-14: Post-task review: the plan Status must match the index, and the `ViewThatFits` 48/44 pair never narrowed the capsule because both variants have the same width. The capsule now has one fixed 48 pt height, matching Figma; the device recording already showed the 48 pt variant. `./scripts/check-app-build.sh ios-simulator` passed again (`20261014-100222-988`).

## Decisions

- The code keeps its scale button where the Figma capsule shows a speed gauge; speed remains in the top-bar long-press menu. This pre-existing difference is left unchanged.

## Open Decisions

- None.
