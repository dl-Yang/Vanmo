# Session Handoff

## Verified Now

- The current long-running work entry points are the root `AGENTS.md`, `./init.sh`, and the state documents under `doc/`.
- Commands actually run on 2026-08-24:
  - `swift test --package-path Packages/VanmoCore`: all 36 tests passed.
  - `./scripts/check-cloud-sync-multiplatform-scope.sh`: 0 failures.

## Changed This Session

- Product code or behavior: none.
- Agent workflow:
  - Added `init.sh` as the unified initialization and baseline verification script.
  - Made the feature list, quality snapshot, evaluator rubric, and clean-state checklist project-specific.
  - Reduced `.cursor/rules/agents.mdc` to a long-task continuity rule while keeping `AGENTS.md` as the authoritative guide.
  - Standardized workflow documentation in English and added a persistent English-documentation requirement.

## Broken Or Unverified

- Known defect: no new runtime defect was confirmed in this session.
- Unverified path: neither app was built in this session. Real SMB/HTTP download pause/resume and cross-window detail navigation still require manual acceptance.
- Risks:
  - VanmoCore still emits pre-existing Swift 6 `Sendable` and redundant access-control warnings.
  - The working tree contains many uncommitted changes that predate this task; subsequent work must remain isolated.

## Next Best Step

- Highest-priority unfinished feature: `mac-download-real-source-validation`.
- Why it is next: download core tests and a macOS build have evidence, but real-source checkpoint recovery and window navigation remain unverified.
- Passing criteria: complete the real SMB/HTTP flow for one movie and 2–3 episodes as specified in `doc/feature_list.json`, recording non-sensitive evidence.
- Scope guardrail: do not expand download implementation solely to complete acceptance, and do not overwrite other uncommitted working-tree changes.

## Commands

- Initialization and baseline: `./init.sh`
- macOS build and run: `./run_device.sh --macos`
- iOS Simulator: `./run_device.sh --simulator`
- Focused download tests: `swift test --package-path Packages/VanmoCore --filter DownloadTests`
- Device diagnostics: search for the existing `[Debug]` prefix in Xcode Console or Console.app, then manually copy non-sensitive logs.