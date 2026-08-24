# Progress Log

<!--
 Read it at session startup and update it before handoff through the
repository's agent instructions; no agent updates it automatically.
-->

Any coding agent can use it when the repository's
instructions tell it to read the file at startup and update it before handoff;
agents do not update it automatically.

## Current Verified State

- Repository root: `/Users/yingu/Vanmo`
- Standard initialization path: `./init.sh`
- Standard startup path: `./run_device.sh --macos`
- Standard baseline verification path: `./init.sh`
- Platform verification path: use `./run_device.sh` or `--simulator` for iOS; use `./run_device.sh --macos` for macOS
- Current highest-priority unfinished feature: `mac-download-real-source-validation`
- Current blocker: None

## Session Log

### Session 001

- Date: 2026-08-21
- Goal: Improve VanmoMac download progress, duplicate-click prevention, detail navigation, and pause/resume behavior
- Completed:
  - Persisted stable media and series identifiers in DownloadRequest while preserving compatibility with legacy manifests
  - Added batch FIFO processing, per-item and global pause/resume, and two-layer deduplication to DownloadManager
  - Added live circular progress to the media detail download button, switching progress to the active episode
  - Added per-item and global pause/resume controls to the downloads view and cross-window detail navigation
  - Made episode download tasks open the parent series detail and target episode
  - Added Light/Dark Figma download screens and five-state components
- Verification run:
  - `swift test --package-path Packages/VanmoCore`
  - `./run_device.sh --macos`
  - Figma component metadata + Light/Dark screenshots
- Evidence captured:
  - All 36 VanmoCore tests passed, including 7 DownloadTests
  - Vanmo-macOS Debug reported `BUILD SUCCEEDED` and launched successfully
  - Figma contains 5 `Download Progress Button` variants and 5 `Download Task Row` variants
- Commits: None; the user did not request a commit
- Files or artifacts updated: Download Core, VanmoMac detail/download/window navigation, tests, Figma, and feature/progress documents
- Known risk or unresolved issue: Pause checkpoints for long SMB/HTTP downloads and downloads-to-main-window interaction still require manual verification against a real media source
- Next best step: Download one movie and 2–3 episodes from the same series to verify episode progress switching, pause checkpoints, and detail navigation

### Session 002

- Date: 2026-08-21
- Goal: Prevent download task clicks from creating duplicate main windows
- Completed: Removed `openWindow(id: "main")`; registered the existing `NSWindow` when the main window mounted, then activated that window and navigated through the shared detail target
- Verification run: `./run_device.sh --macos`
- Evidence captured: Vanmo-macOS Debug reported `BUILD SUCCEEDED` and launched successfully
- Commits: None; the user did not request a commit
- Files or artifacts updated: `MacAppState.swift`, `VanmoMacApp.swift`, `VanmoMacRootView.swift`, and `MacDownloadManagementView.swift`
- Known risk or unresolved issue: The user still needs to confirm that clicking a download task brings the existing main window forward without increasing the window count
- Next best step: Click a download task manually and observe navigation in the existing main window

### Session 003

- Date: 2026-08-21
- Goal: Fix the detail download button size and duplicate download windows
- Completed:
  - Standardized the macOS 26 download button label to 16×16 to match the favorite and watched buttons
  - Replaced the downloads `WindowGroup` with a single-instance `Window` so repeated opens only bring the existing window forward
- Verification run: `./run_device.sh --macos`
- Evidence captured: Vanmo-macOS Debug reported `BUILD SUCCEEDED` and launched successfully
- Commits: None; the user did not request a commit
- Files or artifacts updated: `MacMediaDetailView.swift` and `VanmoMacApp.swift`
- Known risk or unresolved issue: The user still needs to visually confirm that the three circular Glass buttons have matching dimensions
- Next best step: Click the sidebar download button repeatedly and confirm that only one downloads window exists

### Session 004

- Date: 2026-08-24
- Goal: Apply the long-running agent workflow from `templates/index.md` to Vanmo while preserving existing project-specific guidance
- Completed:
  - Added `init.sh` to unify dependency resolution, VanmoCore tests, cross-platform static checks, and the default macOS startup hint
  - Reduced `.cursor/rules/agents.mdc` to a long-task continuity rule that does not duplicate `AGENTS.md`
  - Removed chat-application examples from the feature list and added a real-source download acceptance item
  - Made the clean-state checklist, evaluator rubric, quality snapshot, and session handoff project-specific
  - Updated startup, definition-of-done, and session-artifact constraints in `AGENTS.md`
- Verification run:
  - `swift test --package-path Packages/VanmoCore`
  - `./scripts/check-cloud-sync-multiplatform-scope.sh`
- Evidence captured:
  - All 36 VanmoCore tests passed
  - CloudKit and multiplatform static checks completed with 0 failures
- Commits: None; the user did not request a commit
- Files or artifacts updated: `init.sh`, `AGENTS.md`, `.cursor/rules/agents.mdc`, `ARCHITECTURE.md`, `doc/agent-progress.md`, `doc/feature_list.json`, `doc/session-handoff.md`, `doc/clean-state-checklist.md`, `doc/evaluator-rubric.md`, and `doc/quality-document.md`
- Known risk or unresolved issue: The apps were not built in this session; VanmoCore still emits pre-existing Swift 6 `Sendable` and redundant access-control warnings
- Next best step: Complete manual acceptance for `mac-download-real-source-validation` against a real SMB/HTTP media source

### Session 005

- Date: 2026-08-24
- Goal: Standardize repository workflow documentation in English
- Completed:
  - Translated the agent progress log, feature list, handoff, clean-state checklist, evaluator rubric, quality document, and long-task Cursor rule into English
  - Added a persistent English-documentation requirement to `AGENTS.md` and `.cursor/rules/agents.mdc`
  - Preserved Chinese as the default chat language while separating it from repository documentation language
- Verification run:
  - Parsed `doc/feature_list.json` with `python3 -m json.tool`
  - Searched the translated workflow documents and rules for remaining Han characters
  - Ran `git diff --check` and repository lint diagnostics on the affected files
- Evidence captured: JSON parsing, language scan, diff check, and lint diagnostics all passed
- Commits: None; the user did not request a commit
- Files or artifacts updated: `AGENTS.md`, `.cursor/rules/agents.mdc`, `doc/agent-progress.md`, `doc/feature_list.json`, `doc/session-handoff.md`, `doc/clean-state-checklist.md`, `doc/evaluator-rubric.md`, and `doc/quality-document.md`
- Known risk or unresolved issue: None specific to the documentation-language change
- Next best step: Complete manual acceptance for `mac-download-real-source-validation` against a real SMB/HTTP media source