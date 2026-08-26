# Quality Score

A conservative snapshot of Vanmo product domains and architectural layers. Grades reflect recorded evidence only; code existence is not treated as verified behavior.

**Last updated:** 2026-08-26  
**Current baseline evidence:** The current recorded `./init.sh` baseline completed all four stages with 0 failures: 36 `VanmoCore` tests, the CloudKit/multiplatform static check, the Advanced Harness documentation and live narrative-consistency check, and the iOS UI interaction CLI static check. The documentation stage now also checks init stage count, plan-index Status, spec/plan Status, and QUALITY current-baseline command paths. The UI CLI check remains structural. Focused `./scripts/check-app-build.sh ios-simulator` then passed, and `./init.sh --full` recorded a green iOS Simulator plus macOS Debug compile matrix on clean `34bf345`. Simulator XCUITest on iPhone 17 Pro recorded tree, default-screen assert, and `journey --name tab-navigation` with retained `xcresult` artifacts. No physical-device XCUITest ran for this snapshot.

## Grading Scale

- **A:** Automation, relevant platform builds, and critical manual flows pass; boundaries are clear and no major known gap remains.
- **B:** Relevant verification passes and structure is mostly clear, but some integration or manual coverage is missing.
- **C:** Core paths have partial evidence, with explicit unverified paths or implementation gaps.
- **D:** A critical path fails, or structural problems prevent safe evolution.

## Product Domains

| Product domain | Grade | Existing evidence | Key gaps |
| --- | --- | --- | --- |
| Media identification and scanning | B | Filename, directory semantics, NFO, incremental scan, and pruning coverage is included in the passing 36-test baseline | No real large-directory, failure-recovery, or app progress-UI integration evidence |
| Downloads | B | Download model, persistence, directory resolution, and queue logic are covered by the passing baseline | Real SMB/HTTP checkpoint recovery and cross-window navigation remain manually unverified |
| Remote connections and search | C | Capability declarations and catalog playback URL behavior are covered by shared tests | Several UI-visible protocols are placeholders or incomplete; no real-service integration suite |
| Playback and prefetching | C | Catalog URL resolution is covered and cleanup paths are documented | No automated app playback, gesture, player-window, or prefetch journey; iOS/macOS paths may drift |
| Metadata and subtitles | C | NFO parsing and subtitle-related shared logic have test coverage | Network refresh, cache invalidation, online subtitle, and rendering paths lack end-to-end evidence |
| Persistence and iCloud sync | C | Local/cloud store boundaries pass the static check | No versioned SwiftData migration; Debug cannot prove CloudKit; no real Release CloudKit evidence |
| iOS app experience | B | The unified XCUITest CLI, iOS Simulator Debug compile, and simulator tab-navigation journey passed on 2026-08-26 with retained `xcresult` attachments | No signed physical-device XCUITest; connect, play, and download journeys remain unverified |
| macOS app experience | C | Platform boundaries are documented; a Debug compile of `Vanmo-macOS` passed on 2026-08-26 | Launch, windows, navigation, and download interactions still rely on manual evidence |

## Architectural Layers

| Architectural layer | Grade | Boundary and legibility evidence | Key gaps |
| --- | --- | --- | --- |
| `VanmoCore` | B | Package boundaries are explicit; 36 tests pass | Uneven service integration coverage; Swift 6 `Sendable` warnings remain |
| iOS platform layer | C | UI, navigation, and player adapters are isolated to the iOS target; Simulator XCUITest now proves tab navigation for four stable identifiers | Large orchestration surfaces remain; physical-device execution is unverified; identifier coverage is still limited to the golden journey |
| macOS platform layer | C | AppKit windows and desktop player behavior remain platform-isolated | Duplicated orchestration and manual-only window acceptance |
| SwiftData / CloudKit | C | Local/cloud model assignments and credential exclusions are documented and statically checked | No versioned schema or migration plan; Release CloudKit lacks real-environment proof |
| Build and agent workflow | B | `project.yml` is the configuration source; `./init.sh` provides four passing shared, boundary, documentation, and iOS UI CLI static stages; the documentation stage now rejects init stage-count and plan-index Status conflicts; `./init.sh --full` now records a green iOS Simulator plus macOS Debug compile matrix; simulator XCUITest is a separate evidence command | Default baseline still does not compile apps or run XCUITest; physical-device UI evidence is still missing |

## Benchmark Snapshots

These snapshots measure only the stated harness path. They are not product-performance benchmarks.

| Date | Harness variant | Completion | Retries | Defects before review | Notes |
| --- | --- | --- | --- | --- | --- |
| 2026-08-25 | Advanced Harness baseline | 3/3 automated stages passed: 36 tests, static check with 0 failures, Harness documentation check with 0 failures | Not recorded | Not measured | `./init.sh`; no app build, launch, real-source flow, or CloudKit environment validation |
| 2026-08-26 | Single-root Harness | 3/3 automated stages passed: 36 tests, static check with 0 failures, Harness documentation check with 0 failures | 0 project-level retries | Not measured | Removed the parallel session-artifact layer; no app build, launch, real-source flow, or CloudKit environment validation |
| 2026-08-26 | iOS UI CLI integration | 4/4 `./init.sh` stages passed; XcodeGen generation and target discovery succeeded; simulator `simctl` screenshot succeeded | Not recorded | Existing app compile blocker recorded | `build-for-testing` stopped at the pre-existing missing `.paused` case in `SettingsView.swift:489`; no physical-device XCUITest, signing, runner-argument, attachment-export, or golden-journey evidence |
| 2026-08-26 | Debug compile evidence layer | Fast `./init.sh` 4/4 passed with no app-build evidence directory; focused macOS Debug compile passed; `./init.sh --full` recorded iOS fail + macOS pass and aggregate exit 1 | 0 | Existing iOS `.paused` compile blocker recorded | Xcode 26.0.1 / Swift 6.2; evidence under `build/app-build-evidence/runs/20260826-141002-10994`; no launch, XCUITest, or CloudKit claim |
| 2026-08-26 | iOS UI golden journey | Fast `./init.sh` 4/4 passed; focused iOS Simulator Debug compile passed; simulator `tree`, `assert`, and `journey --name tab-navigation` passed | 1 attachment-name suffix mismatch, then fixed | No new product defect | Xcode 26.0.1 / Swift 6.2; iPhone 17 Pro simulator; journey artifacts at `build/ui-cli/runs/20260826-145830-63647`; no physical-device or real-source claim |
| 2026-08-26 | Harness narrative consistency | Fast `./init.sh` 4/4 passed; `./scripts/check-harness-docs.sh` passed after link plus narrative checks | 2 checker bugs fixed before the first green run (init stage parse and word-number eval) | No new product defect | Injected RELIABILITY `five baseline stages` and active-index `Completed` for the macOS download plan; both failed as required and were restored; no app compile or XCUITest claim |
| 2026-08-26 | Debug compile evidence closeout | Fast `./init.sh` 4/4 passed with no new evidence run; focused iOS Simulator Debug compile passed; `./init.sh --full` recorded iOS pass + macOS pass and aggregate exit 0 | 0 | No new product defect | Xcode 26.0.1 / Swift 6.2; clean `34bf345`; evidence under `build/app-build-evidence/runs/20260826-153856-830`; no launch, XCUITest, or CloudKit claim |

Future entries should keep the command, environment, stage count, retries, and escaped defects comparable. Do not convert manual observations into a completion percentage.

## Simplification Log

Use this log for deliberate removal experiments. A result is valid only when the same verification path is run before and after the removal.

| Date | Component removed | Outcome | Decision |
| --- | --- | --- | --- |
| 2026-08-25 | None; initial log established | No simplification experiment was performed in this documentation-only unit | Preserve runtime behavior and record the first measured removal when one is attempted |
| 2026-08-26 | Parallel session-artifact documentation layer | The same `./init.sh` baseline passed after execution state and evidence ownership were consolidated under `docs/` | Keep the layer removed |

## Update Triggers

Update this score when a relevant app build, manual golden journey, real-source acceptance flow, Release CloudKit check, migration strategy, automation target, or meaningful boundary change produces new evidence.
