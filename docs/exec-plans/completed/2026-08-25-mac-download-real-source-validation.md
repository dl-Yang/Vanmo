# macOS Download Real-Source Validation

**Status:** Completed  
**Created:** 2026-08-25  
**Completed:** 2026-08-26  
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
- This host has no saved SMB connection. The selected HTTP path is an existing Emby connection, so this run cannot prove SMB recovery.
- A previous completed episode task and one orphan `.part` file already exist. A new acceptance run must queue fresh items and must not treat leftover files as restart evidence.
- Fast baseline success and an existing Debug app do not prove queue, pause, restart, or navigation behavior.

## Progress

- **2026-08-25:** Plan created from the not-started `mac-download-real-source-validation` feature record. No manual acceptance steps have been run.
- **2026-08-26:** Fast `./init.sh` baseline passed: 36 `VanmoCore` tests, CloudKit/multiplatform static check, Harness documentation check, and iOS UI CLI static check. Environment recorded below. Source type selected as HTTP via the one active Emby connection. `./run_device.sh --macos` then built and launched `Vanmo-macOS` Debug (`BUILD SUCCEEDED`; process `Vanmo-macOS` running).
- **2026-08-26:** The operator reported that the nine-step launch checklist passed in one continuous run. That checklist maps to verification steps 2–10. Step 11 records those passes; no failure logs were required.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-26 |
| macOS | 26.0 (25A354), arm64 |
| Xcode | 26.0.1 (17A400) |
| App | `Vanmo-macOS` Debug (`com.vanmo.app.mac`), launched from `build/DerivedData` after `./run_device.sh --macos` |
| Source type | HTTP via one active Emby connection |
| Library inventory | 10 movies, 23 shows, 15 episodes; several movie and episode files are large enough to observe pause and restart |
| Existing download state before the run | 1 completed episode task; 1 orphan `.part` file not listed in the current manifest |
| Baseline | `./init.sh` passed on 2026-08-26 |

Private hostnames, usernames, credentials, authenticated URLs, and media titles are omitted.

## Acceptance Record

One continuous manual run on 2026-08-26. The operator confirmed the nine-step checklist that covers steps 2–10.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Record environment and source type | Pass | HTTP via existing Emby connection; see Environment |
| 2. Connect to the selected source | Pass | Existing Emby connection |
| 3. Queue one movie and two or three episodes from the same series | Pass | Titles omitted |
| 4. Confirm each item appears once | Pass | |
| 5. Pause and resume one task | Pass | |
| 6. Pause and resume all tasks | Pass | |
| 7. Close and restart while work is incomplete | Pass | |
| 8. Confirm restore from existing `.part` files, no duplicates | Pass | |
| 9. Select the movie task; existing main window activates at movie detail | Pass | |
| 10. Select each episode task; existing main window activates at show/episode | Pass | Covered by operator checklist item 9 |
| 11. Record sanitized failure logs if any step fails | Pass | No failure; no Console excerpt required |

## Outcome

The selected HTTP-via-Emby source completed the required macOS download acceptance flow. This record does not prove SMB recovery, iOS downloads, or other connection types.

## Open Decisions

- Source type for this run: HTTP via the one active Emby connection. No SMB connection is present.
- Movie and series titles stay out of the record. Existing library items large enough to observe pause, restart, and resume were used.
- The sanitized acceptance record lives in this plan's Environment and Acceptance Record sections.

These choices selected the test environment only; they did not authorize implementation changes.
