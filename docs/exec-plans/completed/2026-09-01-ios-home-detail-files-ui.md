# iOS Home, Detail, and Files UI Polish

**Status:** Completed
**Plan type:** Product UI
**Related product spec:** none (iOS-only chrome polish)

## Objective

Fix five iOS-only visual and interaction issues: home sync loading overlapping the title, empty favorite placeholders, missing hero backdrop, fake media-detail tags, and an unblocked Files save sheet.

## Scope

- Home header loading placement and hiding the synced pill while `librarySyncMessage` is set
- Favorites glass card variants for 1 and 2 posters
- Default hero backdrop asset when no URL exists
- Media detail refresh button, real rating/resolution/Dolby-detection tags, removal of fake reviews
- Persist optional `contentRating` and server video dimensions through `ServerMediaItem` / `MediaItem`
- Files root list without connection status or refresh; blocking save overlay on Add Connection

## Out of Scope

- macOS UI
- Dolby playback or a new 4K player path
- Making the Files browser static after a connection is opened
- Stopping app-launch auto-reconnect / library scan

## Verification

1. `swift test --package-path Packages/VanmoCore` including `MediaCapabilityTagsTests`.
2. `./scripts/check-harness-docs.sh` after the plan is indexed.
3. `./scripts/check-app-build.sh ios-simulator` (not in parallel with macos).
4. Manual iOS: home loading under the title; favorites 1 / 2 / 3+; default hero; detail tags and refresh; Files list without status; save overlay blocks repeat taps.

## Risks

- Series items still have no series-level probe; resolution tags come from the first episode with width or a filename token.
- Movies without server dimensions stay tag-less until probe or a filename token succeeds.
- 4K playback remains the existing KSPlayer path; a playback defect is a separate fix.

## Progress

- **2026-09-01:** Implementation added.
- **2026-09-01:** `swift test --package-path Packages/VanmoCore` passed, including `MediaCapabilityTagsTests`. `./scripts/check-harness-docs.sh` passed with 0 failures. `./scripts/check-app-build.sh ios-simulator` passed (Debug compile).
- **2026-09-01:** Post-task review follow-up: `shouldProbe` now re-probes successful items missing dimensions; only explicit Dolby Vision ranges persist to `dynamicRange`; single favorite poster height fits the card. `MediaCapabilityTagsTests` 7/7 passed.
- **2026-09-01:** Manual iOS feedback: detail rating and tags share one row; resolution tags also use filename tokens and published probe size; new connections are verified before insert, with a cancellable overlay and an in-sheet error if access fails. Review follow-up: save overlay stays on the form so the toolbar Cancel stays tappable; probe no longer blocks episode loading; a successful insert dismisses the sheet even if the later scan fails.
- **2026-09-01:** Simulator walk: TV detail crash avoided by skipping series-level probe and keeping ModelContext serial; TV resolution tags now come from episode width/filename; Add Connection uses the Figma Connecting / Failed dialogs (no gray 0.42 dim).
- **2026-09-01:** Operator iOS Simulator confirmation: TV detail no longer crashes; TV and movie detail both show resolution tags; Add Connection Connecting / Failed dialogs match the Figma File frames.
- **2026-09-01:** Operator iOS Simulator confirmation of the remaining original walk: home loading sits under the title without overlap; favorites 1 / 2 / 3+ layouts are correct; default hero backdrop shows when no URL exists; Files root has no connection status. All required verification steps passed.

## Open Decisions

- None.
