# Downloads

**Product area:** Vanmo and VanmoMac Downloads  
**Source scope:** Shared `DownloadManager` behavior plus the recorded platform UI and acceptance evidence below.

## User-Visible Behavior

### macOS Download Progress, Controls, and Navigation

The media detail view shows live progress for an active download. The downloads view supports pause and resume for an individual task and for all tasks. Selecting a download task returns the user to the corresponding movie detail or episode.

The implemented behavior has the following evidence recorded on 2026-08-21:

- all 36 `VanmoCore` tests passed
- the macOS Debug app built and launched
- Light and Dark Figma download screens and five task states were inspected
- changes preventing duplicate main windows and standardizing the downloads/detail presentation were followed by passing macOS builds

Three 2026-08-28 Vanmo-macOS SMB runs are recorded. A Files-browser run queued three `media=movie` tasks; one sibling restored as `failed` because the Mac disk was full, and the downloads window showed that failure. After space was freed, later `.part` continuations succeeded. A later library-detail run queued three `media=tvEpisode` tasks. A third library-detail run queued one `media=movie` and three `media=tvEpisode` tasks from `restore count=0`, exercised `pauseAll` and `resumeAll`, inferred single-task pause/resume of an in-progress episode, restored that episode at `received=813694976` and continued to completion, and logged `open detail` for the movie and one episode. Operator reported no second main window.

This evidence records the SMB multi-item matrix for the 2026-08-28 plan. It does not change the HTTP real-source Current acceptance status below.

A separate 2026-08-30 Vanmo-macOS AList Files-browser run downloaded one remote video and played the completed local file. That run is recorded in [`../exec-plans/completed/2026-08-28-alist-connection-validation.md`](../exec-plans/completed/2026-08-28-alist-connection-validation.md). It does not replace the SMB mixed-run matrix or the HTTP-via-Emby recovery record.

A separate 2026-08-31 Vanmo-macOS FTP Files-browser run downloaded one remote video and played the completed local file. That run is recorded in [`../exec-plans/completed/2026-08-30-ftp-real-source.md`](../exec-plans/completed/2026-08-30-ftp-real-source.md). It does not replace the SMB mixed-run matrix or the HTTP-via-Emby recovery record.

### iOS Download Progress, Controls, and Navigation

The iOS downloads screen is reached from Settings → 下载管理. It follows iOS Figma Download Light `456:4` and Dark `456:254`: a large title, pause-all or resume-all, select mode, a task summary, and five row states with a 16:9 poster, status copy, and a circular action. Directory selection stays in Settings storage.

Selecting a row opens the existing media detail. The completed-row play control starts the local file. The media-detail download button shows related-task progress and blocks duplicate enqueue while a movie or episode is queued, downloading, or paused.

The implemented iOS success flow has the following evidence recorded on 2026-08-27 and 2026-08-28:

- enqueue from media detail over HTTP via Emby
- live progress on the detail button and the downloads list
- completion of an episode task
- completed-row play opened the local file
- selection-mode delete remained usable in the header
- pause, app terminate, cold-launch restore from the existing `.part` file, and resume at the restored offset
- physical-device Files-browser enqueue over SMB, same-session resume, terminate while downloading, cold-launch `.part` restore, and completion

This evidence does not establish the macOS HTTP recovery matrix or the separate Vanmo-macOS SMB mixed-run record above.

A separate 2026-08-30 AList Files-browser run on the iOS Simulator downloaded one remote video and played the completed local file. That run is recorded in [`../exec-plans/completed/2026-08-28-alist-connection-validation.md`](../exec-plans/completed/2026-08-28-alist-connection-validation.md). It does not change the HTTP-via-Emby or SMB recovery acceptance below.

A separate 2026-08-31 FTP Files-browser run on the iOS Simulator downloaded one remote video and played the completed local file. That run is recorded in [`../exec-plans/completed/2026-08-30-ftp-real-source.md`](../exec-plans/completed/2026-08-30-ftp-real-source.md). It does not change the HTTP-via-Emby or SMB recovery acceptance below.

### Real-Source Recovery and Detail Navigation

A user can download movies and episodes from a readable real SMB or HTTP source, pause and resume without duplicate queue entries, restart the app, continue from existing partial files, and return from the downloads window to the correct movie detail or episode.

**Current acceptance status:** Completed. One HTTP-via-Emby manual run on 2026-08-26 passed queue, pause, restart-from-part, and main-window movie/episode navigation. SMB was not exercised. That run covers macOS only.

## Real-Source Acceptance Criteria

All steps must pass in one recorded manual acceptance run:

1. Connect to a readable SMB or HTTP media source.
2. Queue one movie and two or three episodes from the same series.
3. Confirm that no duplicate tasks appear.
4. Pause and resume an individual task and all tasks.
5. Restart the app.
6. Resume and confirm that progress continues from the existing `.part` files.
7. Select the movie task and each episode task in the downloads window.
8. Confirm that the existing main window is activated without duplication and navigates to the correct movie detail or episode.
9. Record the source type, passing steps, and sanitized failure logs without credentials or complete authenticated URLs.

## Evidence Rules

- Shared tests establish download model and state-machine evidence only.
- A macOS or iOS build or launch does not establish real SMB/HTTP checkpoint recovery or cross-window navigation.
- Figma inspection establishes intended visual states, not runtime behavior.
- Mark real-source acceptance as passing only after the complete flow succeeds.
- The macOS acceptance record does not authorize expanded download implementation. A discovered defect requires a separately scoped change.
- iOS HTTP success-flow evidence does not prove the macOS recovery matrix or macOS SMB download.

## Related Plan

- [`../exec-plans/completed/2026-08-25-mac-download-real-source-validation.md`](../exec-plans/completed/2026-08-25-mac-download-real-source-validation.md)
