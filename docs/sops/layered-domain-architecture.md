# SOP: Layered Domain Architecture

Use this SOP when adding or moving behavior across Vanmo's shared package,
platform applications, persistence, synchronization, or Xcode targets.

## Read First

- [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md)
- [`../DESIGN.md`](../DESIGN.md)
- [`../SECURITY.md`](../SECURITY.md)
- [`../QUALITY_SCORE.md`](../QUALITY_SCORE.md)
- [`../references/xcodegen-build-reference-llms.txt`](../references/xcodegen-build-reference-llms.txt)

## Ownership Map

- `Packages/VanmoCore/`: cross-platform models, protocols, remote services,
  scanning, downloads, subtitles, metadata, playback URL resolution,
  prefetching, and shared persistence infrastructure. It must not import
  SwiftUI, UIKit, or AppKit.
- `Vanmo/`: iOS SwiftUI, UIKit bridges, tab and navigation behavior,
  full-screen player presentation, iOS player adapters, and device lifecycle.
- `VanmoMac/`: macOS SwiftUI and AppKit, sidebar routing, windows, menus,
  keyboard and pointer behavior, desktop player adapters, and window cleanup.
- SwiftData `LocalStore`: `MediaItem`, `PlaybackRecord`, and `ScanJobRecord`;
  never CloudKit-enabled.
- SwiftData `CloudStore`: `SavedConnection`, `FolderBookmark`, and
  `CloudMediaState`; CloudKit is optional and Release-only.
- Keychain/OAuth storage: credentials and tokens. They do not belong in either
  SwiftData store.

## Execution Loop

1. Name the user-visible behavior and the state owner before selecting a file.
2. Place reusable domain and infrastructure behavior in `VanmoCore`; keep
   platform presentation, navigation, player adapters, and lifecycle in the
   owning app target.
3. For a new SwiftData model, assign it deliberately to `LocalStore` or
   `CloudStore`, update `ModelContainerFactory`, and consider tests and
   migration impact. Do not cross `ModelContext` or model objects through
   unstructured concurrency unsafely.
4. Keep UI-observable coordinators on `@MainActor`; prefer actors for shared
   mutable background state.
5. If targets, packages, sources, resources, settings, compilation conditions,
   or entitlements change, edit `project.yml` first, run `xcodegen generate`,
   and review the generated project diff. Never hand-edit
   `Vanmo.xcodeproj/project.pbxproj`.
6. Run the smallest focused tests while iterating, then run:

   ```bash
   swift test --package-path Packages/VanmoCore
   ./scripts/check-cloud-sync-multiplatform-scope.sh
   ```

7. Build or run each affected platform through `./run_device.sh`,
   `--simulator`, or `--macos`. A static check does not prove app compilation
   or runtime behavior.
8. Update `ARCHITECTURE.md` only when an implemented boundary, target,
   dependency, data flow, store assignment, protocol capability, or risk
   changes. Update `docs/QUALITY_SCORE.md` only from new evidence.

## Stop Conditions

Stop and resolve the design before continuing if:

- platform UI is being moved into `VanmoCore`
- credentials or the full media catalog would enter `CloudStore`
- a Debug run is being used to claim real CloudKit behavior
- a target change exists only in `project.pbxproj`
- iOS and macOS presentation are being forced together solely to remove
  superficial duplication

## Definition of Done

- Every changed type has one clear owner.
- Dependency direction matches the ownership map.
- Relevant tests and the static boundary check actually ran, or the failure is
  recorded.
- Each affected app platform has proportionate build/runtime evidence.
- Durable architecture and quality documents reflect only verified changes.
