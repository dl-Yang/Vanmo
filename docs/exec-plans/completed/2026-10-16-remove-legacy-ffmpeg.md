# Remove Legacy FFmpeg Configuration

**Status:** Completed

## Objective

Remove the unused standalone FFmpeg build setup so it is not mistaken for a current playback prerequisite. Decoding stays in the KSPlayer package.

## Scope

- Removed `FFMPEG_ENABLED` from both app targets in `project.yml`, then regenerated `Vanmo.xcodeproj`.
- Removed the empty `Vanmo/Vanmo-Bridging-Header.h` and the iOS `SWIFT_OBJC_BRIDGING_HEADER` setting.
- Removed `scripts/build-ffmpeg-ios.sh`.
- Left `-lz`, `-lbz2`, and `-liconv` on the iOS link line.

## Out of Scope

- KSPlayer's own FFmpeg
- Deleting a local `Vanmo/Frameworks/FFmpeg/` directory. It stays gitignored

## Verification

- `rg` finds no `FFMPEG_ENABLED` or bridging-header setting in `project.yml` or `project.pbxproj`
- iOS Simulator Debug `20261016-094750-97043` and macOS Debug `20261016-094849-97838`: pass
- `./scripts/check-architecture-guards.sh` and `./scripts/check-harness-docs.sh`: pass

## Risks

- None recorded. No Swift source referenced the removed flag.

## Progress Log

- 2026-10-16: Removed the flag, header, and script, and regenerated the Xcode project.

## Open Decisions

- None.
