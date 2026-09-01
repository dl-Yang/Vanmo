# App Language

**Product area:** Vanmo and VanmoMac Settings → Appearance  
**Source scope:** Shared `VanmoCore` language preference, string catalog, and formatters; iOS and macOS appearance settings.

## User-Visible Behavior

The Appearance settings page offers three interface-language options: Chinese, English, and Follow System. The default preference is Chinese. Follow System uses Chinese when the system language is Chinese, and English for English or any other system language.

Changing the language does not update the current session. The app shows a restart reminder, and the new language applies on the next launch.

Chinese mode shows Chinese UI copy, duration units, and season/episode labels. English mode shows English equivalents. Brand and protocol names (Vanmo, iCloud, CloudKit, Google Drive, SMB, Emby, Plex, and similar) stay in their original form. Server-provided media titles and system `localizedDescription` errors are not translated.

**Current acceptance status:** Completed. `AppLanguageTests` and isolated `check-app-build.sh all` (`20260901-092901-5875`) passed. 2026-09-01 iOS Simulator and macOS operator walks each recorded 2–3 Appearance language changes: the current session stayed, the next-launch reminder appeared, and the new language applied after restart.

## Acceptance Criteria

1. A new install defaults to Chinese.
2. Appearance settings offer Chinese, English, and Follow System.
3. Changing the language keeps the current UI and reminds the user that the next launch applies it.
4. After restart, chrome, settings, empty states, alerts, duration, and season/episode labels match the selected language.
5. Follow System on a non-Chinese, non-English system resolves to English.
6. Reset all settings restores Chinese.

## Evidence Rules

- `VanmoCore` tests prove preference resolution and formatter output only.
- An app compile does not prove every page was inspected in both languages.
- An Xcode Incremental Build does not replace `check-app-build.sh`. The script records compile evidence in isolated DerivedData and SourcePackages.
- iOS evidence does not prove macOS, and macOS evidence does not prove iOS.

## Related Plan

- [`../exec-plans/completed/2026-08-31-app-language-switching.md`](../exec-plans/completed/2026-08-31-app-language-switching.md)
