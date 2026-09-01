# App Language Switching

**Status:** Completed
**Plan type:** Product feature
**Related product spec:** [`../../product-specs/app-language.md`](../../product-specs/app-language.md)

## Objective

Give Vanmo and VanmoMac a real Chinese / English / Follow System interface-language setting. Default to Chinese. Apply a change on the next launch. Remove mixed Chinese-English chrome, duration, and season/episode labels.

## Scope

- Shared `AppLanguagePreference`, process lock, `L10n`, and `Localizable.xcstrings` in `VanmoCore`.
- Appearance-page language pickers and a restart reminder on both apps.
- Localized duration, season/episode, relative date, and file-size formatters.
- User-visible copy sweep on iOS and macOS, except brand names, media titles, and system error descriptions.
- InfoPlist local-network usage strings.

## Out of Scope

- Live in-session UI refresh after a language change
- Translating server-provided titles or `error.localizedDescription`
- Forcing system file-picker buttons to the app language
- Figma redesign of the language picker

## Verification

1. `swift test --package-path Packages/VanmoCore` including `AppLanguageTests`.
2. `./scripts/check-architecture-guards.sh` and `./scripts/check-harness-docs.sh`.
3. `./scripts/check-app-build.sh` for Vanmo and Vanmo-macOS, run serially or via `all`. An Xcode Incremental Build does not replace this script.
4. Manual: default Chinese; switch to English, confirm current UI stays and the restart alert appears; after relaunch, chrome and dialogs are English. Follow System on a non-Chinese/non-English system is English.

## Risks

- Some interpolated connection or player messages may still be assembled in one language if a later string was missed.
- System permission dialogs follow the OS language unless AppleLanguages is also set.
- XCUITest golden journey prefers `tab.settings` and only falls back to the Chinese label.

## Progress

- **2026-08-31:** Plan created. Implementation added `VanmoCore` language lock, catalog, formatters, Appearance pickers, and a UI-copy sweep.
- **2026-08-31:** `AppLanguageTests` passed 10 cases (default Chinese; system zh/en/other; duration and season/episode formats). Broader `swift test --package-path Packages/VanmoCore`, architecture, and harness-docs checks passed. Manual language walks remain required before this plan can move to completed.
- **2026-08-31:** Parallel `check-app-build.sh ios-simulator` and `macos` hung on Resolve Package Graph / KSPlayer package update while sharing `build/app-build-evidence/SourcePackages`. Those processes were stopped. Isolated script compile remains required and must run serially; an Xcode Incremental Build does not replace it.
- **2026-08-31:** `./run_device.sh --simulator` on iPhone 17 Pro (`0811807F-3DD6-4DF5-B5B3-C734ABC76F1F`) failed first on missing `import VanmoCore` in `LoadingIndicatorView`, then `BUILD SUCCEEDED` and launched `com.vanmo.app`. Default install had no `app.interfaceLanguage` key and showed Chinese chrome, `分钟`/`小时`, and `第1季第1集`. Writing `english` and relaunching showed English chrome, `9m`/`1h 41m total`, and `S01E01`. Media titles and the Emby folder name `电视 - 韩国` stayed untranslated. Screenshots: `build/ui-cli/runs/20260831-language/vanmo-lang-zh.png` and `vanmo-lang-en.png`. Isolated `check-app-build.sh` and macOS walks remain.
- **2026-09-01:** Operator manual walk on the same iPhone 17 Pro Simulator passed. Language was changed 2–3 times in Settings → Appearance; each change kept the current session and showed the next-launch reminder. After each restart the chrome matched the selected language. This closes the iOS Appearance-picker and restart-alert gap from 2026-08-31. macOS manual walk and isolated `check-app-build.sh` remain.
- **2026-09-01:** `./run_device.sh --macos` failed first on missing `import VanmoCore` in `MacFormatters`, `MacHeaderToolbar`, and `MacLibraryEmptyStateView`, then `BUILD SUCCEEDED` and launched `com.vanmo.app.mac` (no `app.interfaceLanguage` key; default Chinese).
- **2026-09-01:** Operator macOS Appearance walk passed. Language was changed 2–3 times (including English and Follow System); each change kept the current session and showed the next-launch reminder. After each quit/relaunch the chrome matched the stored preference (`english`, then `system`). Isolated `check-app-build.sh` remains.
- **2026-09-01:** `./scripts/check-app-build.sh all` passed serially on a dirty tree at `0a0fe85`. iOS Simulator Debug `xcodebuild` 0 with `Vanmo.app` present; macOS Debug `xcodebuild` 0 with `Vanmo-macOS.app` present; `aggregate=pass`. Evidence: `build/app-build-evidence/runs/20260901-092901-5875`. Toolchain: Xcode 26.0.1 / Swift 6.2. This closes the isolated compile gate. Reset-all-settings restore to Chinese was not separately walked.

## Open Decisions

- None. Live refresh remains out of scope.
