# iOS Home Server Count and Connection Logos

**Status:** In progress
**Plan type:** Product UI
**Related product spec:** none (iOS-only chrome polish)

## Objective

Home sync pill counts successfully shown servers, not movie/TV libraries. Home section headers and Add Connection protocol picker use the same brand logos as macOS.

## Scope

- `syncPillText` counts unique home connections with visible folders and no error
- Copy `MacConn*` imagesets into the iOS asset catalog
- Show provider logos on home server headers and Add Connection picker / selected type

## Out of Scope

- macOS UI
- Files root `ConnectionCard` generic icons
- Changing which folders appear on home

## Verification

1. `./run_device.sh --simulator` (Debug build and launch).
2. Home pill shows `已同步 · N 个服务器` for successful home connections, not library count.
3. Home headers and Add Connection picker/selected type show matching brand logos.
4. Open one TV show and one movie detail with no crash.
5. `./scripts/check-harness-docs.sh` after this plan is indexed.

## Risks

- iOS `UIImage(named:)` must find the copied `MacConn*` names; missing assets fall back to SF Symbols.
- A connection that has libraries but still reports an error is excluded from the pill count.
- iOS `.pickerStyle(.menu)` may flatten custom `Label` icons in the closed row; menu rows still use `ConnectionProviderIcon`.
- A new Swift file requires `xcodegen generate` so `ConnectionProviderIcon.swift` is in the iOS target. Assets did not need a `project.yml` edit.

## Progress

- **2026-09-01:** Implementation added. `xcodegen generate` registered `ConnectionProviderIcon.swift` in the iOS target only.
- **2026-09-01:** `./scripts/check-architecture-guards.sh` passed. `./scripts/check-harness-docs.sh` passed after indexing this plan.
- **2026-09-01:** `./run_device.sh --simulator` Debug build and launch succeeded on iPhone 17 Pro (`0811807F-3DD6-4DF5-B5B3-C734ABC76F1F`).
- **2026-09-01:** Home evidence on one Emby connection named Reno with 16 movie/TV libraries: pill `已同步 · 1 个服务器` (not `16 个库`); header shows `MacConnEmby` and subtitle `16 个媒体库`. XCUITest accessibility dump and a simctl screenshot both recorded this.
- **2026-09-01:** Files root still uses generic server-rack card icons, as specified.

## Remaining

- Operator: open Files → Add Connection and confirm the protocol picker / selected type shows brand logos.
- Operator: open one TV show detail and one movie detail; confirm no crash. `MediaDetailView` was not changed in this task.

## Open Decisions

- None.
