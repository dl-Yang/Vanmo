# VanmoLogger Migration

**Status:** Completed

## Objective

Move the remaining debug `print` calls onto `VanmoLogger`, so Console filters use one subsystem. The test report in `ModelContainerFactoryTests` stays a `print`.

## Scope

- Player, subtitle, library, metadata, download, and CloudKit debug lines in the iOS app, the macOS app, and VanmoCore.
- Categories: `player`, `subtitle`, `library`, `metadata`, and `storage`.
- Media titles use `privacy: .private`. Counts, statuses, and error text use `privacy: .public`.
- `DownloadHeroController` imports `VanmoCore` so it can log.

## Out of Scope

- `ModelContainerFactoryTests`, whose `print` is test output
- Changing log level. These lines stay `.info` under the existing `#if DEBUG` where they already had it. CloudKit mirroring that logged outside `#if DEBUG` still logs outside it

## Verification

- No `print(` remains in Swift sources outside `ModelContainerFactoryTests`
- `swift test --package-path Packages/VanmoCore`: 273 tests, 0 failures
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261015-110330-58516`), then `macos` (`20261015-110409-58722`)

## Risks

- `os.Logger` redacts values that lack a privacy annotation. Every interpolation in the converted lines has one.

## Progress Log

- 2026-10-15: Converted the remaining debug prints. A string concatenation inside an `os.Logger` call failed to compile and was rewritten as one message. Tests and both app builds then passed.

## Open Decisions

- None.
