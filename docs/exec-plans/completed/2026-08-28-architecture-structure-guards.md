# Architecture Structure Guards

**Status:** Completed
**Plan type:** Harness infrastructure
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Strengthen the existing CloudKit/multiplatform static stage so a later agent cannot treat a green baseline as proof that `project.yml` still matches the committed Xcode project, that macOS still compiles only the documented shared iOS files, or that `VanmoCore` still has no unconditional UI-framework imports.

## Scope

- Add independently callable `scripts/check-architecture-guards.sh`.
- Invoke it from `scripts/check-cloud-sync-multiplatform-scope.sh`. Keep the fast `./init.sh` baseline at four stages.
- Reject hand-edited `project.pbxproj` drift, illegal target sources/dependency direction, and unconditional `VanmoCore` UI imports.
- Replace the `rg` UI-import scan and the hardcoded `PlatformCompatibility` pbxproj UUID check.
- Document the new focused command without claiming compile, launch, or XCUITest evidence.

## Out of Scope

- A fifth default `./init.sh` stage
- SwiftSyntax, SwiftLint, or taste lint
- Rewriting CloudKit / Settings / sync-trigger `rg` presence checks
- In-place `xcodegen generate` or hand-editing `project.pbxproj`
- `./init.sh --full`, device runs, or UI journeys

## Verification

1. `bash -n` on the touched scripts.
2. Current-tree `./scripts/check-architecture-guards.sh` and `./scripts/check-cloud-sync-multiplatform-scope.sh` exit 0.
3. Injected pbxproj comment, extra macOS `Vanmo/` source, and unconditional `import SwiftUI` in `VanmoCore` each fail, then restore.
4. `./scripts/check-harness-docs.sh` still exits 0 with four stages.
5. Fast `./init.sh` still runs four stages and reaches the new guards; it does not compile apps or run XCUITest.

## Risks

- Fresh XcodeGen output differs in `objectVersion`, product file-type attributes, `OTHER_SWIFT_FLAGS` list shape, and local `DEVELOPMENT_TEAM` rewrites. Compare after that format normalization, not by ignoring file lists or build phases.
- Generating into a directory outside the repository rewrites source paths. Use a temporary symlink mirror of the repository root.
- `xcodegen generate` must not mutate the working tree. Fail if `git status --short` changes.

## Progress

- **2026-08-28:** Plan created. Implementation starts from the existing stage-2 static check.
- **2026-08-28:** Added `scripts/check-architecture-guards.sh` (XcodeGen 2.44.1). Current-tree guards and `./scripts/check-cloud-sync-multiplatform-scope.sh` exited 0. Injecting a `project.pbxproj` comment failed with pbxproj drift; adding `Vanmo/App/ContentView.swift` to `Vanmo-macOS` sources failed the whitelist; adding unconditional `import SwiftUI` to `NetworkError.swift` failed the import scan. All three injections were restored and the guards passed again. `./scripts/check-harness-docs.sh` passed with four stages. Fast `./init.sh` completed all four stages, reached the architecture guards, and did not compile apps or run XCUITest.
- **2026-08-28:** Post-task review made pbxproj failures print the normalized diff and kept the script Summary after a Python failure. Re-ran `bash -n` and the guards; a restored pbxproj-comment injection now shows only `/* architecture-guard injection */` in the normalized diff.

## Open Decisions

- None. SwiftSyntax remains deferred and is recorded in `docs/exec-plans/tech-debt-tracker.md`.
