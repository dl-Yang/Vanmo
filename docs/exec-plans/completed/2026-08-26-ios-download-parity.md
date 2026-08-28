# iOS Download Parity

**Status:** Completed  
**Created:** 2026-08-26  
**Completed:** 2026-08-27  
**Plan type:** Implementation plus success-flow acceptance  
**Related spec:** [`../../product-specs/downloads.md`](../../product-specs/downloads.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Bring the iOS download management page to visual parity with Figma Download Light/Dark and functional parity with the existing macOS download controls. The completion gate for this plan is one recorded real-source success flow: enqueue, visible progress, completion, and play.

## Scope

- Rebuild the iOS downloads screen from Figma `456:4` / `456:254`.
- Wire `DownloadManager` pause, resume, pause-all, resume-all, retry, and delete.
- Keep directory selection in Settings storage.
- Open the existing `MediaDetailView` from a download row.
- Show live download progress on the media-detail download button.
- Record one HTTP or otherwise available real-source success flow.

## Out of Scope

- Changing the VanmoCore download engine or adding protocols
- A fifth iOS tab or a macOS-style downloads window
- SMB recovery, app-restart `.part` continuation, or the full macOS pause matrix as acceptance
- CloudKit or unrelated player work

## Verification

1. `./init.sh` fast baseline passes.
2. `./scripts/check-app-build.sh ios-simulator` passes.
3. Figma Light/Dark five-state rows are inspected against the implemented screen.
4. One real-source success flow is recorded: enqueue from detail or the file browser, the downloads page shows the task and progress, completion allows play.

## Risks

- A short file may complete before progress is easy to observe.
- Source availability and Range behavior can fail without identifying an app defect.
- Figma has no empty or selection frames; those states use a minimal existing pattern.
- Success-flow evidence does not prove SMB or restart recovery.

## Progress

- **2026-08-26:** Implementation started. iOS download UI, queue controls, detail navigation, and media-detail progress wiring are in the working tree. Required verification has not yet run.
- **2026-08-26:** Fast `./init.sh` passed all four stages (36 `VanmoCore` tests, CloudKit/multiplatform static check, harness documentation check, iOS UI CLI static check). `xcodegen generate` included `DownloadManagementView.swift`. Focused `./scripts/check-app-build.sh ios-simulator` passed (`BUILD SUCCEEDED`; evidence `build/app-build-evidence/runs/20260826-173918-36436`). Simulator XCUITest `tap --label 下载管理` failed because each `ios-ui.sh` command relaunches the app and cannot continue from Settings. No real-source success flow has been recorded.
- **2026-08-26:** Follow-up `./scripts/check-app-build.sh ios-simulator` after identifier and unused-helper cleanup passed (`BUILD SUCCEEDED`; evidence `build/app-build-evidence/runs/20260826-174238-38317`). The booted iPhone 17 Pro simulator container has 0 `SavedConnection` rows and 0 `MediaItem` rows; the download manifest is empty. Physical-device launch is blocked because no Development Team is configured. The success-flow gate therefore remains open: implementation and compile evidence are recorded, but enqueue → progress → complete → play has not run against a readable HTTP/Emby source.
- **2026-08-27:** Device testing found two UI defects. The media-detail download button swapped chrome without showing live progress (static 20% ring, button disabled while queued/downloading). Selection-mode delete sat on the bottom bar and was covered by the tab bar. Fixes keep the download button bound to `DownloadManager.tasks`, show indeterminate spin or a live percent, and allow pause/resume/retry from the same control. Delete moves to the header action row using system glass buttons on iOS 26.
- **2026-08-27:** After disk cleanup, focused `./scripts/check-app-build.sh ios-simulator` passed (`aggregate=pass`; evidence `build/app-build-evidence/runs/20260827-102832-88374`). That build was installed and launched on the booted iPhone 17 Pro simulator. The simulator now has an Emby-backed local library (6 movies, 6 shows, 11 episodes). One earlier movie download failed with a local disk-full error and is not a success-flow pass. Smallest stored episode is about 0.5 GB; smallest stored movie is about 1.9 GB.
- **2026-08-27:** Operator recorded an HTTP-via-Emby success path for enqueue, live progress, downloads-page updates, and selection delete. Playing a completed episode from the downloads row first failed: the row tap swallowed the circular control, local `.mp4` remuxes were routed to AVPlayer, and after a rebuild `play skipped` because the task still stored a previous simulator container path. Fixes isolate the play control, present `PlayerView` from the downloads page, send local files through KSPlayer, and remap stale app-container download directories. `DownloadTests` (8) passed.
- **2026-08-27:** The same completed episode then played. Console showed `action status=completed`, `play completed ext=mp4`, and `present player mediaType=tvEpisode`. The required success-flow gate is now recorded.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-27 |
| Host | macOS 26.0, arm64 |
| Device | iPhone 17 Pro simulator |
| App | Vanmo iOS Debug |
| Source type | HTTP via an existing Emby connection |
| Library inventory | 6 movies, 6 shows, 11 episodes |
| Compile evidence | `build/app-build-evidence/runs/20260827-102832-88374` |
| Baseline | Fast `./init.sh` passed on 2026-08-26 |

Private hostnames, usernames, credentials, authenticated URLs, and media titles are omitted.

## Acceptance Record

HTTP-via-Emby simulator evidence recorded on 2026-08-27. Two episodes were queued from media detail. Play first failed on the completed episode, then succeeded on that same task after the play-path fixes. An earlier large movie failure from a full local disk is excluded.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Record environment and source type | Pass | HTTP via existing Emby connection; see Environment |
| 2. Enqueue from media detail | Pass | `enqueued source=detail-episodes count=2 connection=emby` |
| 3. Live progress on the detail button and downloads list | Pass | Rotating ring, then a rising percent |
| 4. Completion | Pass | One episode reached `status=completed` |
| 5. Play the completed local file | Pass | `play completed ext=mp4`; `present player mediaType=tvEpisode` |
| 6. Selection-mode delete remains usable | Pass | Header delete; not covered by the tab bar |

## Outcome

The selected HTTP-via-Emby source completed the required iOS download success flow: enqueue, visible progress, completion, and play. This record does not prove SMB recovery, app-restart `.part` continuation, physical-device signing, or the macOS recovery matrix.

## Open Decisions

None.
