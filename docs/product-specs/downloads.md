# macOS Downloads

**Product area:** VanmoMac Downloads  
**Source scope:** This specification is limited to the recorded download implementation evidence and the linked real-source acceptance plan.

## User-Visible Behavior

### Download Progress, Controls, and Navigation

The media detail view shows live progress for an active download. The downloads view supports pause and resume for an individual task and for all tasks. Selecting a download task returns the user to the corresponding movie detail or episode.

The implemented behavior has the following evidence recorded on 2026-08-21:

- all 36 `VanmoCore` tests passed
- the macOS Debug app built and launched
- Light and Dark Figma download screens and five task states were inspected
- changes preventing duplicate main windows and standardizing the downloads/detail presentation were followed by passing macOS builds

This evidence does not establish the real-source acceptance flow below.

### Real-Source Recovery and Detail Navigation

A user can download movies and episodes from a readable real SMB or HTTP source, pause and resume without duplicate queue entries, restart the app, continue from existing partial files, and return from the downloads window to the correct movie detail or episode.

**Current acceptance status:** Completed. One HTTP-via-Emby manual run on 2026-08-26 passed queue, pause, restart-from-part, and main-window movie/episode navigation. SMB was not exercised.

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
- A macOS build or launch does not establish real SMB/HTTP checkpoint recovery or cross-window navigation.
- Figma inspection establishes intended visual states, not runtime behavior.
- Mark real-source acceptance as passing only after the complete flow succeeds.
- This acceptance specification does not authorize expanded download implementation. A discovered defect requires a separately scoped change.

## Related Plan

- [`../exec-plans/completed/2026-08-25-mac-download-real-source-validation.md`](../exec-plans/completed/2026-08-25-mac-download-real-source-validation.md)
