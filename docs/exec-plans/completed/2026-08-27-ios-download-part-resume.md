# iOS Download Part Resume

**Status:** Completed  
**Created:** 2026-08-27  
**Completed:** 2026-08-27  
**Plan type:** Manual acceptance of existing behavior  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record whether an iOS HTTP-via-Emby download can pause, survive an app terminate, restore the same task, and continue from the existing `.part` file without a duplicate queue entry.

This is a factual acceptance record. It does not authorize download-engine changes.

## Scope

- Use the already-installed iOS Simulator app and the existing Emby HTTP source.
- Queue a fresh episode large enough to observe pause and restart.
- Pause after observable progress, terminate the app without reinstalling, cold-launch, and resume.
- Confirm `receivedBytes` is restored from the `.part` file and then increases from that offset.
- Record sanitized Console evidence.

## Out of Scope

- Changing the VanmoCore download engine or adding protocols
- SMB recovery
- Physical-device signing or XCUITest
- The macOS recovery matrix or downloads-spec Related Plan
- Using leftover completed or paused tasks as the recorded run
- `xcodegen` regeneration
- Figma or unrelated player work

If the flow exposes a defect, stop at a reproducible, sanitized record. A separately scoped fix plan is required before implementation.

## Verification

1. Record the simulator, app configuration, and source type without credentials or private media details.
2. Queue one fresh episode from media detail over HTTP via Emby.
3. Confirm a single task appears and progress increases.
4. Pause after `received > 0` and record that value.
5. Terminate the app without Xcode Run or `./run_device.sh`.
6. Cold-launch from the icon or `simctl launch`.
7. Confirm the same task id is restored as `paused`, with `received` in the same range as step 4.
8. Resume and confirm `received` increases from that offset rather than restarting at 0, and that no duplicate task appears.
9. Record sanitized `[Debug][Downloads]` lines for enqueue, pause, restore, and resume.

The plan completes only when every step passes in one recorded run.

## Risks

- Xcode Run after pause can change the simulator container UUID and lose the `.part` path.
- Emby may answer HTTP 200 instead of 206, forcing a restart from offset 0.
- A leftover paused task must not be treated as restart evidence.
- Disk pressure can fail a large file; pause after observable progress instead of waiting for completion.
- Success does not prove SMB or physical-device download.

## Progress

- **2026-08-27:** Validation plan created. Restore Debug logging now prints each incomplete task's `received` and `total` after `restoreAndResume()`. No part-resume run has been recorded.
- **2026-08-27:** Operator recorded a fresh HTTP-via-Emby episode enqueue, pause, terminate, cold-launch restore, and resume. The same task id stayed `paused` after restore with a non-zero `received` from the `.part` file, then returned to `queued` at that offset. The operator confirmed the download continued. Count remained 1.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-27 |
| Device | iPhone 17 Pro simulator |
| App | Vanmo iOS Debug |
| Source type | HTTP via an existing Emby connection |
| Task | Fresh episode enqueue; leftover tasks were not used |

Private hostnames, usernames, credentials, authenticated URLs, and media titles are omitted.

## Acceptance Record

One HTTP-via-Emby simulator run on 2026-08-27. The first `restore count=0` line is the process start before enqueue. The later `restore count=1` line is the cold launch after pause.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Record environment and source type | Pass | HTTP via existing Emby connection |
| 2. Queue one fresh episode | Pass | `enqueued source=detail-episodes count=1 connection=emby` |
| 3. Single task, progress increases | Pass | `appear count=1`; `status=downloading` `received=71303168` |
| 4. Pause after `received > 0` | Pass | `status=paused` `received=83886080` |
| 5–6. Terminate and cold-launch | Pass | Operator terminated without Xcode Run |
| 7. Same task restored as `paused` | Pass | `restore count=1 statuses=paused`; `received=138412032` from the `.part` file, not 0 |
| 8. Resume from the restored offset | Pass | `action status=paused` then `status=queued` `received=138412032`; count stayed 1; operator confirmed the download continued |
| 9. Sanitized Console record | Pass | `[Debug][Downloads]` excerpt above; no credentials or titles |

The restore `received` is larger than the last pause UI snapshot because `reconcilePartSizes` reads the on-disk `.part` length. That value did not reset to 0.

## Outcome

iOS HTTP-via-Emby pause, terminate, and `.part` resume is recorded on the simulator. This record does not prove SMB recovery, physical-device signing, or an expansion of the macOS recovery matrix.

## Open Decisions

None.
