# Quality Document

A conservative quality snapshot of Vanmo product domains and architectural layers. Grades reflect recorded evidence only; code existence is not treated as verified behavior.

**Last updated:** 2026-08-24  
**Current evidence:** `swift test --package-path Packages/VanmoCore` completed with all 36 tests passing; `./scripts/check-cloud-sync-multiplatform-scope.sh` completed with 0 failures. The most recent recorded macOS build is from 2026-08-21; this snapshot did not rebuild either app.

**Grading scale:**

- **A:** Automation, platform builds, and critical manual flows pass; boundaries are clear and no major known gap remains.
- **B:** Relevant verification passes and structure is mostly clear, but some integration or manual coverage is missing.
- **C:** Core paths have only partial evidence, with explicit unverified paths or implementation gaps.
- **D:** A critical path fails, or structural problems prevent safe evolution.

---

## Product Domains

| Product domain | Grade | Existing evidence | Key gaps |
| --- | --- | --- | --- |
| Media identification and scanning | B | Filename, directory semantics, NFO, incremental scan, and pruning tests pass | No real large-directory, failure-recovery, or app progress-UI integration tests |
| Downloads | B | Seven download model/queue tests pass; macOS build passed on 2026-08-21 | Real SMB/HTTP checkpoint recovery and cross-window navigation still require manual acceptance |
| Remote connections and search | C | Capability declarations and lazy playback URL tests pass | Several UI-visible protocols remain placeholders or incomplete; no real-service integration tests |
| Playback and prefetching | C | Catalog URL resolution tests pass; architecture and cleanup paths are documented | iOS/macOS implementations may drift; no automated app playback, gesture, window, or prefetch tests |
| Metadata and subtitles | C | NFO parsing and subtitle format detection tests pass | Network refresh, cache invalidation, online subtitles, and rendering lack end-to-end verification |
| Persistence and iCloud sync | C | Local/cloud store static boundary checks pass | No explicit SwiftData migration; Debug cannot prove real CloudKit behavior |
| iOS app experience | C | Current architecture and run commands are documented | This snapshot did not build iOS; no app/UI test target |
| macOS app experience | C | A Debug build was recorded as passing on 2026-08-21 | This snapshot did not rebuild macOS; window, navigation, and download interactions still rely on manual verification |

## Architectural Layers

| Architectural layer | Grade | Boundaries and legibility | Key gaps |
| --- | --- | --- | --- |
| VanmoCore | B | Package boundaries have static checks, core data flows are documented in `ARCHITECTURE.md`, and all 36 tests pass | Uneven network-service coverage; unresolved Swift 6 `Sendable` warnings |
| iOS platform layer | C | UI, navigation, and players remain in the iOS target | Large ViewModels; no app automation; not built in this snapshot |
| macOS platform layer | C | AppKit windows and players remain platform-isolated | Duplicated use-case orchestration with iOS; window behavior relies mainly on manual acceptance |
| SwiftData / CloudKit | C | Local and cloud model assignments are explicit, and credentials are excluded from sync models | No versioned schema/migration; Release CloudKit lacks real-environment evidence |
| Build and agent workflow | B | `project.yml` is the configuration source, `init.sh` provides a unified baseline, and state documents are project-specific | README still contains stale versions, architecture descriptions, and links to deleted documents |

## Change History

### 2026-08-24

- Replaced tutorial placeholders with real Vanmo product domains, verification evidence, and conservative grades.
- Added a unified `init.sh` that chains dependency resolution, VanmoCore tests, and cross-platform static checks.
- Removed chat-application placeholders from `feature_list.json` and recorded a real-source download acceptance item.
- Standardized workflow documentation in English and made English the default language for future repository documentation updates.
- New gap: SwiftPM currently emits Swift 6 `Sendable` warnings; this session did not expand scope to fix them.
- Closed gap: long-running workflow documents no longer depend on generic template fields or a missing startup script.