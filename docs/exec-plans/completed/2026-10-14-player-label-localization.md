# Player Label Localization

**Status:** Completed
**Related product spec:** [`../../product-specs/app-language.md`](../../product-specs/app-language.md)

## Objective

Give the remaining iOS player controls English labels. In English, VoiceOver still read Chinese for `快退`, `快进`, and `缩放`, and the context menu still showed `倍速`.

## Scope

- English entries in `L10nTable` and `Localizable.xcstrings`, and in `scripts/generate-l10n.py` so a later regeneration keeps them:
  - `快退` → Skip back
  - `快进` → Skip forward
  - `缩放` → Scale
  - `倍速` → Speed
- The rate-boost banner now uses the existing `%@x 倍速播放中` key (`Playing at %@x`) instead of a hardcoded Chinese string.

## Out of Scope

- macOS player chrome, which does not use these four keys
- Opening the context menu. The `倍速` item is the same `L10n.tr` lookup as the labels below, but this walk did not get the menu on screen

## Verification

- `swift test --package-path Packages/VanmoCore`: 273 tests, 0 failures. `AppLanguageTests` asserts the four English strings.
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261014-155935-37939`), then `macos` (`20261014-160012-38431`). After the rate-boost banner was switched to the existing format key, `./scripts/check-app-build.sh ios-simulator` passed again (`20261014-160941-40382`). That view is not in the macOS target.
- iOS Simulator, interface language set to English before launch, local Jellyfish clip. `idb ui describe-all` on the visible controls reported `Skip back`, `Skip forward`, and `Scale`, plus `Close`, `Quality`, `Subtitles`, `Audio tracks`, and `Original`. None of the four Chinese keys appeared. Screenshots are in `tem/l10n/` (not committed).

## Risks

- The context menu was not opened, so `Speed` was not read from the accessibility tree. It uses the same lookup as the three labels that were.

## Progress Log

- 2026-10-14: Added the four English strings, ran tests and both builds, and checked the English Simulator accessibility tree. The rate-boost banner was then switched to the existing format key and the iOS build was run again.

## Open Decisions

- None.
