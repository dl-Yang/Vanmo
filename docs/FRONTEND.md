# Frontend

This document defines stable UI expectations for Vanmo's SwiftUI applications.

## Source of Truth

- Figma is the visual source of truth for UI work. Select the correct iOS or macOS design before implementation.
- If a required screen or state is absent, design it in Figma before coding it.
- Match the repository's existing components, assets, typography, spacing, color tokens, and motion before introducing a new pattern.
- Record visual verification against the relevant Figma frame; code existence is not design-fidelity evidence.

## Platform Separation

- iOS UI, navigation, full-screen player presentation, UIKit bridges, and device lifecycle behavior belong in `Vanmo/`.
- macOS UI, sidebar routing, AppKit windows, native settings, menu commands, keyboard behavior, and player-window lifecycle belong in `VanmoMac/`.
- `VanmoCore` must not import SwiftUI, UIKit, or AppKit.
- Share a SwiftUI component only when both apps need the same platform-neutral behavior. Do not force shared navigation or player presentation to remove superficial duplication.
- Only the shared views explicitly listed in `project.yml` are compiled directly into the macOS target.

## Localization

- User-visible chrome, buttons, empty states, alerts, and section titles go through `L10n.tr` in `VanmoCore`.
- Chinese is the source language. English lives in the shared catalog and table.
- Keep brand and protocol names (Vanmo, iCloud, CloudKit, Google Drive, SMB, Emby, Plex, and similar) in their original form.
- Do not translate server-provided media titles, cast names, or `error.localizedDescription`.
- Duration and season/episode labels use `LocalizedFormat`, not mixed `h`/`m` or `S01E01` chrome in Chinese.
- Changing the Appearance language setting does not require a live UI refresh; the next launch applies it.

## SwiftUI Expectations

- Keep View bodies small and move orchestration into the existing ViewModel or Store boundary.
- UI-observable coordinators remain on `@MainActor`.
- Use the narrowest appropriate state ownership and avoid parallel sources of truth for visible state.
- Provide previews for reusable and screen-level views, including representative states when practical.
- Use SF Symbols or approved project/Figma assets consistently; do not invent substitute iconography.
- Preserve cancellation, stale-result rejection, and cleanup behavior across navigation and lifecycle changes.

## Required Five-State Model

Every network-backed, persisted, or long-running screen must deliberately handle these five user-facing states:

1. **Empty:** No content exists or the user has not configured a source; explain the next useful action.
2. **Loading:** Work is active; preserve layout where practical and avoid indefinite unexplained spinners.
3. **Success:** Content or completion is visible and reflects the authoritative state owner.
4. **Error:** Explain the failure without exposing secrets and preserve recoverable user context.
5. **Retry:** Offer an explicit, idempotent recovery action when retry is safe; prevent duplicate requests or queue entries.

Features with richer state machines, such as downloads and playback, may add domain states but must still cover the equivalent empty, loading, success, error, and recovery experiences.

## Interaction and Accessibility

- Support Dynamic Type without clipping essential labels or controls.
- Provide meaningful accessibility labels, values, hints, and traits for icon-only controls, progress, toggles, and custom rows.
- Keep touch targets appropriate on iOS and pointer/keyboard focus behavior appropriate on macOS.
- Preserve visible focus, logical reading order, sufficient contrast, and Reduce Motion behavior for non-essential animation.
- Do not encode status by color alone.
- Use concise, actionable error and retry copy.
- On macOS, verify expected keyboard shortcuts, window activation, and single-window behavior where specified.

## Automation Selectors

- Give critical iOS controls stable, semantic accessibility identifiers when they are part of a repeatable interaction or golden journey. Prefer identifiers for automation because visible labels can change with copy or localization.
- Use an exact accessibility label only as a fallback when no stable identifier exists. Labels must remain meaningful to users and assistive technologies; do not distort user-facing accessibility text solely to make automation convenient.
- Keep identifiers unique within the active screen and tied to the control's purpose rather than its position or visual implementation.
- Inspect available identifiers and labels with `./scripts/ios-ui.sh simulator tree` or `./scripts/ios-ui.sh device tree`, then use `--identifier` preferentially or `--label` for the exact-label fallback.
- `./scripts/ios-ui.sh device ...` and `./scripts/ios-ui.sh simulator ...` use XCUITest for screenshot, tree, tap, type, swipe, wait, assert, and `journey --name tab-navigation`. `simulator launch|terminate` still use `simctl` only for Simulator management and cannot validate selectors.

## Verification Expectations

### iOS

- Build or run with `./run_device.sh` or `./run_device.sh --simulator` as required by the behavior.
- Verify compact and relevant regular-width layouts, navigation stacks, full-screen player presentation, lifecycle transitions, and accessibility behavior.
- Device-only behavior must be verified on a device; collect diagnostics from local console logs.

### macOS

- Build or run with `./run_device.sh --macos`.
- Verify sidebar routing, detail overlays, independent player and downloads windows, window activation, keyboard commands, pointer interactions, and cleanup on close.

### Evidence Boundary

`VanmoCore` tests do not verify UI. A successful build does not verify the five states, Figma fidelity, accessibility, window behavior, or a golden journey. Record what was actually inspected and on which platform.
