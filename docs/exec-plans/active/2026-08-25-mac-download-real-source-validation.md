# macOS Download Real-Source Validation

**Status:** Not started  
**Created:** 2026-08-25  
**Plan type:** Manual acceptance of existing behavior  
**Related spec:** [`../../product-specs/downloads.md`](../../product-specs/downloads.md)

## Objective

Determine whether the existing macOS download experience completes its real-source acceptance criteria: one movie and two or three episodes can be queued from a readable SMB or HTTP source without duplicates, paused, resumed after restart from existing partial files, and selected to activate the existing main window at the correct detail or episode.

The result is a factual acceptance record, not an implementation change.

## Scope

- Use the native macOS app.
- Use one readable real SMB or HTTP media source.
- Queue one movie and two or three episodes from the same series.
- Exercise per-item and global pause/resume.
- Restart the app while unfinished work and `.part` files exist.
- Verify recovery, queue uniqueness, main-window activation, and movie/episode navigation.
- Record source type, step outcomes, and sanitized console evidence for failures.

## Out of Scope

- Adding, refactoring, or optimizing download behavior
- Changing queue, persistence, networking, window, or navigation implementation
- Testing source types other than the selected SMB or HTTP source
- Expanding acceptance to iOS
- Changing Figma designs
- Debugging with remote telemetry or log upload
- Marking Release CloudKit, unrelated playback, or other product domains as verified

If the flow exposes a defect, stop at a reproducible, sanitized record and create a separately authorized fix plan.

## Verification

Perform the following manual flow in order:

1. Record the macOS version, app configuration, and source type without credentials or private media details.
2. Connect to a readable SMB or HTTP media source.
3. Queue one movie and two or three episodes from the same series.
4. Confirm that each intended item appears once and no duplicate tasks are created.
5. Pause and resume one task.
6. Pause and resume all tasks.
7. Allow observable progress, then close and restart the app while work remains incomplete.
8. Confirm that each unfinished task is restored and continues from its existing `.part` file rather than starting as a duplicate.
9. Select the movie task and confirm that the existing main window activates and shows the correct movie detail.
10. Select each episode task and confirm that the existing main window activates and shows the correct show detail or episode.
11. Record every step as pass or fail. For a failure, copy only relevant local Console output with credentials, tokens, complete authenticated URLs, and private paths redacted.

The plan completes only when every step passes in one recorded run. A build, shared-package test, Figma inspection, or partial manual flow is insufficient.

## Risks

- Source availability, bandwidth, server Range behavior, and file size can affect timing without identifying an app defect.
- Short downloads may complete before pause and restart behavior can be observed.
- SMB and HTTP may exercise different recovery paths; this plan proves only the selected source type.
- Evidence may accidentally expose credentials, signed URLs, hostnames, usernames, or media filenames unless sanitized.
- A navigation result can look correct while opening a duplicate main window; window count must be observed explicitly.

## Progress

- **2026-08-25:** Plan created from the not-started `mac-download-real-source-validation` feature record. No manual acceptance steps have been run.

## Open Decisions

- Which available source type will be used for this run: SMB or HTTP?
- Which movie and series provide files large enough to observe pause, restart, and resume safely?
- Where will the sanitized acceptance record be stored after the run?

These choices select the test environment only; they do not authorize implementation changes.
