# AGENTS.md

> **Language Use:** All chat interactions for this repository default to Chinese. Repository documentation must be created and updated in English.

Vanmo is a video player with an iOS app (`Vanmo`), a native macOS app (`Vanmo-macOS`), and a shared local Swift package (`VanmoCore`). The project uses SwiftUI, MVVM/Store-style state management, Swift Concurrency, Combine, and SwiftData. Minimum versions are iOS 17 and macOS 14.

Prioritize verified completion, narrow scope, and repository continuity over raw output volume.

## Sources of Truth

Use these sources in descending order:

1. Current code and tests.
2. `project.yml` for Xcode targets, dependencies, resources, build flags, and entitlements.
3. `Packages/VanmoCore/Package.swift` for package platforms and dependencies.
4. [`ARCHITECTURE.md`](ARCHITECTURE.md) for system boundaries, runtime data flows, persistence, integration points, and known risks.
5. Durable product, design, quality, and operating records under [`docs/`](docs/PLANS.md).
6. [`README.md`](README.md) for repository orientation and standard entry commands.

Do not duplicate the complete architecture document in rules or implementation notes. Keep this file operational and concise, and link to `ARCHITECTURE.md` for architectural detail.

## Routing Map

Use progressive disclosure: start here, then open only the repository documents relevant to the task.

### Repository knowledge (`docs/`)

- [`docs/PRODUCT_SENSE.md`](docs/PRODUCT_SENSE.md): durable product priorities and evidence discipline.
- [`docs/DESIGN.md`](docs/DESIGN.md): design decisions and links to `docs/design-docs/`.
- [`docs/PLANS.md`](docs/PLANS.md): execution-plan policy and active/completed plan indexes.
- [`docs/QUALITY_SCORE.md`](docs/QUALITY_SCORE.md): the single current quality snapshot.
- [`docs/RELIABILITY.md`](docs/RELIABILITY.md): bootstrap, verification, runtime evidence, recovery, and local debugging.
- [`docs/SECURITY.md`](docs/SECURITY.md): credentials, data, external actions, dependency trust, and security review.
- [`docs/FRONTEND.md`](docs/FRONTEND.md): Figma authority, platform UI separation, five-state UI expectations, accessibility, and visual verification.
- [`docs/product-specs/index.md`](docs/product-specs/index.md): current user-visible behavior and acceptance targets.
- [`docs/exec-plans/active/index.md`](docs/exec-plans/active/index.md): work still requiring implementation or evidence.
- [`docs/exec-plans/tech-debt-tracker.md`](docs/exec-plans/tech-debt-tracker.md): confirmed deferred debt.

`docs/` is the only Harness documentation root. Active plans own in-progress state, completed plans preserve outcomes, `QUALITY_SCORE.md` owns evidence-based quality, and the tech-debt tracker owns confirmed deferred work.

## Architecture Red Lines

Read [`ARCHITECTURE.md`](ARCHITECTURE.md) before changing module boundaries, persistence, navigation, player engines, remote protocols, synchronization, or build configuration.

Core constraints:

- `Vanmo/` owns iOS UI and platform behavior; `VanmoMac/` owns macOS UI, AppKit integration, and window behavior.
- `Packages/VanmoCore/` owns shared models and infrastructure. It must not import SwiftUI, UIKit, or AppKit.
- Platform player implementations remain in the app targets. Shared playback types, URL resolution, prefetching, and format detection belong in `VanmoCore`.
- SwiftData is split into a local media store and an optional cloud-backed store. New models must be assigned deliberately and added to `ModelContainerFactory`.
- UI-observable coordinators should remain on `@MainActor`; shared mutable background state should prefer actors. Do not use `ModelContext` across unstructured concurrency boundaries.
- Credentials belong in Keychain/OAuth storage, never in SwiftData entities, logs, source files, or fixtures.
- iOS and macOS navigation and player presentation are intentionally platform-specific. Do not force UI sharing merely to remove duplication.

When a change alters any documented boundary, target, dependency, data flow, model/store assignment, protocol capability, or architectural risk, update `ARCHITECTURE.md` in the same task. Summarize the new decision; do not paste implementation files or duplicate large sections of the document.

## Startup Workflow

Before changing the repository:

1. Confirm the repository root with `pwd`.
2. Inspect `git status` and preserve unrelated user changes.
3. Read [`ARCHITECTURE.md`](ARCHITECTURE.md), [`docs/QUALITY_SCORE.md`](docs/QUALITY_SCORE.md), and [`docs/PLANS.md`](docs/PLANS.md).
4. Read the relevant entry in [`docs/exec-plans/active/index.md`](docs/exec-plans/active/index.md), any active plan governing the work, and the related product spec under [`docs/product-specs/`](docs/product-specs/index.md).
5. Review recent commits with `git log --oneline -5`.
6. Run the baseline and any affected-platform checks required by [`docs/RELIABILITY.md`](docs/RELIABILITY.md). Pure documentation work does not require an unrelated app build.

If the baseline is already failing, report the existing failure and avoid stacking unrelated changes on top of it.

## Working Rules

- Work on one user-visible feature or one infrastructure concern at a time.
- Keep edits within the requested scope unless a narrow supporting fix is required.
- Never discard, reset, or overwrite unrelated working-tree changes.
- Do not mark work complete because code was added; required verification must actually run.
- Do not weaken, replace, or silently skip verification to obtain a passing result.
- Prefer durable repository artifacts over chat-only state.
- Commit or push only when the user explicitly requests it.

## Build and Project Generation

- The committed Xcode project is generated by XcodeGen from `project.yml`.
- For target, dependency, source, resource, setting, or entitlement changes: edit `project.yml`, run `xcodegen generate`, and include the regenerated `Vanmo.xcodeproj/project.pbxproj`.
- Never hand-edit `project.pbxproj`.
- Standard commands, configuration differences, and evidence boundaries live in [`docs/RELIABILITY.md`](docs/RELIABILITY.md).
- `CLOUDKIT_SYNC_ENABLED` is Release-only. Debug builds cannot validate real CloudKit behavior.
- The macOS target directly reuses only the shared views listed in `project.yml`; do not assume arbitrary files under `Vanmo/` compile for macOS.

## Verification and Evidence

Choose verification proportional to the change:

- `VanmoCore` logic: run `swift test --package-path Packages/VanmoCore`.
- CloudKit, target-boundary, or cross-platform scope: run `./scripts/check-cloud-sync-multiplatform-scope.sh`.
- Harness documentation, plan-index Status, and live narrative consistency: run `./scripts/check-harness-docs.sh`.
- iOS UI target and interaction-CLI structure: run `./scripts/check-ios-ui-cli.sh`.
- App Debug compile evidence: run `./scripts/check-app-build.sh ios-simulator`, `./scripts/check-app-build.sh macos`, or `./init.sh --full` after the fast baseline.
- iOS app behavior: build/run with `./run_device.sh` or `--simulator`.
- iOS UI interaction and evidence capture: use `./scripts/ios-ui.sh device ...` or `./scripts/ios-ui.sh simulator ...` for XCUITest screenshot, tree, tap, type, swipe, wait, assert, and `journey --name tab-navigation`. `simulator launch|terminate` still use `simctl` only for simulator management.
- macOS app behavior: build/run with `./run_device.sh --macos`.
- Project configuration: regenerate with XcodeGen before building.
- UI and device-only behavior: perform the relevant manual flow and record what was actually verified.

The Xcode project has an iOS UI-test target, but its static checker does not prove a successful app build, signed device execution, or user journey. A package test, static check, build, launch, XCUITest command, and manual journey prove different things; never present one as evidence for another. Follow [`docs/RELIABILITY.md`](docs/RELIABILITY.md) for the complete evidence boundary.

Before handing off substantial work:

1. Update the governing active plan with completed behavior, verification evidence, unresolved risks, and the next step.
2. Move a finished plan to `docs/exec-plans/completed/`; do not mark it complete without its required evidence.
3. Update `docs/QUALITY_SCORE.md` or the tech-debt tracker only when new evidence supports the change.
4. Leave the repository runnable through the documented build and test commands.

## Definition of Done

A feature or infrastructure concern is complete only when:

- the requested behavior or repository artifact exists
- the required verification ran successfully
- evidence and unresolved risks are recorded in the governing plan or durable document
- unrelated working-tree changes remain untouched
- the next session can resume through `AGENTS.md`, the active-plan index, `./init.sh`, and the documented platform command

## Security, Frontend, and Device Debugging

- Follow [`docs/SECURITY.md`](docs/SECURITY.md) for credentials, sensitive URLs, external actions, dependencies, and review.
- Device debugging uses local console logs only. Never add remote logging, telemetry, upload pipelines, or external observation services unless explicitly requested. Keep logs non-sensitive and follow `.cursor/rules/ios-device-debug-logs.mdc`.
- Follow [`docs/FRONTEND.md`](docs/FRONTEND.md) for UI work. Figma is the visual source of truth, and iOS/macOS behavior remains platform-specific.
- Follow `.cursor/rules/swift-coding.mdc` for Swift style.
- Follow `.codex/skills/git-workflow/SKILL.md` for Git operations.

## Code Review

After resolving a task that changed repository files:

1. Produce a clear, complete change summary.
2. Run the `post-task-code-reviewer` subagent against the final change.
3. Apply justified findings and re-verify.

Exceptions:

- Plain-text plans do not require review.
- `git commit` and `git push` operations do not require review.
