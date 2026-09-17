# Downloads

**Product area:** Vanmo and VanmoMac Downloads  
**Source scope:** Shared `DownloadManager` behavior plus the recorded platform UI and acceptance evidence below.

## User-Visible Behavior

### macOS Download Progress, Controls, and Navigation

The media detail view shows live progress for an active download. Enqueueing from that view plays a hero capsule from the download button into the sidebar download icon (`arrow.down.circle`), which scales as if it swallowed the capsule. The downloads window does not open automatically. The downloads view supports pause and resume for an individual task and for all tasks. Selecting a download task returns the user to the corresponding movie detail or episode.

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

Enqueueing from the media detail view plays a short hero capsule (poster plus title) from the download button. On a Dynamic Island device, the capsule flies to the hardware island, aligns top-flush, then grows to in-app Compact matching LibraryHome `569:38` (262×41 artwork, title, `下载中`, trailing ring with percent) with a critically damped appear so the last frame does not bounce. Compact tap expands to `570:259` (poster, title, status • percent, bar, byte line, pause pill) with a system-island spring on one pure-black blob. Expanded→Compact is critically damped so the blob cannot dip below the hardware island. A press anywhere outside Expanded collapses to Compact without requiring a click. Compact has no pause button: downloading shows a non-interactive ring; a Downloads-page pause swaps the ring for a pause icon (`572:14`) that resumes. Expanded pause/resume and that Compact icon call the same `DownloadManager.pause` / `resume` as Live Activity intents and read `task.status` only. Compact tap does not open Downloads. Appear runs only on `hidden → compact`; Compact↔Expanded is one size/content transition; pause never replays appear. Island phones do not show the status-bar fallback bar. The iOS app hides the system status bar while active. Cold-launch `restoreAndResume` and Reduce Motion skip the flight and still show the correct mode whenever a presentable task exists. This is app chrome over the hardware island, and ActivityKit is also requested in the foreground. A 2026-09-17 iOS Simulator operator walk confirmed Compact tap and Expanded pause still reach the fake island, the scene absorbs into the hardware island on background, and the system Live Activity remains. Resign-active hides the overlay immediately and unhides the status bar. Foreground return keeps the activity and restores Compact with `playAppear`. Expanded content sits below the hardware island. `.background` retries after suspend. The system compact uses leading artwork plus trailing ring or pause-icon replicas of `569:38`; Expanded and lock screen follow `570:259`. The lock-screen / banner card opens Downloads via `vanmo://downloads`. When the displayed task finishes or is deleted, the overlay collapses to the hardware island and fades out without overshoot (Reduce Motion hides it immediately). A 2026-09-16 iPhone 17 Pro Simulator operator walk confirmed that delete-from-Downloads no longer bounces or flashes Compact content. A completion alert fires once when the displayed task finishes. On a notch iPhone without a Dynamic Island, the app hides the system status bar. The hero capsule shrinks to the leading status-bar slot while it flies. After it lands, a solid-blue capsule with a white icon and a white progress border appears in the key-window overlay. That capsule shows no video title or poster and has no Expanded mode. Tapping it while downloading opens Downloads; tapping it while paused resumes. Pause, resume, completion pulse, and delete collapse follow the same Compact selection rules as the fake island. Third-party apps cannot draw into the system location/microphone/hotspot privacy indicator, so downloads cannot use that system chrome. Notch phones do request ActivityKit for the lock-screen / banner Live Activity; island phones already requested it and still do. A 2026-09-17 operator recording `tem/cmp.mp4` on iPhone 13 mini passed the shrinking flight, the landed blue capsule, lock-screen Live Activity, and pause-control sync. The walk is recorded in [`../exec-plans/completed/2026-09-17-notch-download-status-bar.md`](../exec-plans/completed/2026-09-17-notch-download-status-bar.md). On iPhone SE or iPad, the capsule lands at the status-bar slot, plays a short spring, then the tappable fallback bar fades in (iOS 26+ liquid glass, earlier `ultraThinMaterial`); completion or delete fades the bar out. Pause, resume, and retry do not replay the flight.

Progress chrome uses `DownloadActivityPresentation`: a movie or single episode shows the latest downloading task, otherwise the latest queued or paused task; a multi-episode series shows the current downloading episode and advances to the next unfinished episode after a completion pulse. When no presentable task remains, the island and fallback bar dismiss.

A 2026-09-13 / 2026-09-14 hero walk used Debug local fixtures on that same detail enqueue path. iPhone 17 Pro recorded the movie capsule in flight and a series island title; iPhone SE recorded the fallback-bar swallow; a signed Vanmo-macOS launch recorded movie and series capsules flying toward the sidebar download icon. Screenshots are under `build/hero-walk/`. The walk is recorded in [`../exec-plans/completed/2026-09-11-download-hero-animation.md`](../exec-plans/completed/2026-09-11-download-hero-animation.md).

A 2026-09-16 iPhone 17 Pro Simulator fixture walk recorded in-app Compact `569:38` at 13%, Expanded `570:259` downloading then paused, Compact-Paused `572:14`, Downloads with Compact still visible, foreground Compact once after Home, and delete clearing the overlay. The same-day iPhone SE walk recorded the landing capsule and the status-bar fallback bar. Screenshots are under `build/island-polish-walk/20260916-full/`. The walk did not capture a system Live Activity after backgrounding.

A 2026-09-17 iOS Simulator operator re-walk confirmed the post-flight Compact appear settles without a last-frame bounce or position snap, and Expanded→Compact never exposes the hardware island. The same-day walk confirmed that requesting Live Activity in the foreground does not steal fake-island hits and that backgrounding absorbs the scene into the hardware island with the system Live Activity still present.

The iOS downloads screen is reached from Settings → 下载管理, by tapping the notch status-bar capsule, or by tapping the fallback bar. It follows iOS Figma Download Light `456:4` and Dark `456:254`: a large title, pause-all or resume-all, select mode, a task summary, and five row states with a 16:9 poster, status copy, and a circular action. Directory selection stays in Settings storage.

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
