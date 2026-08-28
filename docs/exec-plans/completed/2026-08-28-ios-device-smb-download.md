# iOS Device SMB Download Recovery

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-08-28  
**Plan type:** Manual acceptance of existing behavior  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record whether a physical-device iOS build can enqueue a real SMB video, pause after observable progress, survive an app terminate, restore the same task from the existing `.part` file, and resume without a duplicate queue entry.

This is a factual acceptance record. It does not authorize download-engine changes.

## Scope

- Use the operator's already-signed iOS Debug build on a trusted physical device.
- Use the SMB connection the operator already added on that device.
- Queue one fresh SMB video from the Files browser, not a leftover HTTP or simulator task.
- Pause after `received > 0`, terminate without reinstalling, cold-launch from the icon, and resume.
- Confirm `[Debug][Downloads]` shows `connection=smb` or `type=smb`, the same task id, and a non-zero restored `received`.

## Out of Scope

- Changing the VanmoCore download engine or adding protocols
- The macOS recovery matrix or downloads-spec Related Plan
- SMB connect/browse/play (already recorded on simulator and Mac)
- Using leftover Emby or simulator tasks as the recorded run
- `xcodegen` regeneration
- XCUITest or remote logging
- Figma or unrelated player work

If the flow exposes a defect, stop at a reproducible, sanitized record. A separately scoped fix plan is required before implementation.

## Verification

1. Record that the run is a physical-device iOS Debug session and the source type is SMB, without hostnames or credentials.
2. Open Files, enter the existing SMB connection, and queue one fresh video.
3. Confirm a single SMB task appears with `type=smb` and `received` increases.
4. Pause after `received > 0` and record that value.
5. Terminate the app without Xcode Run or `./run_device.sh`.
6. Cold-launch from the home-screen icon.
7. Confirm the same task id is restored with `received` not reset to 0.
8. Confirm the download continues from that offset and no second SMB task appears.
9. Copy sanitized `[Debug][Downloads]` lines only.

The plan completes only when every step passes in one recorded run.

## Risks

- Xcode Run after pause can change the device container and lose the `.part` path.
- SMB reconnect after cold-launch can fail independently of the queue.
- A leftover Emby task must not be treated as SMB evidence.
- Disk pressure can fail a large file; pause after observable progress instead of waiting for completion.
- SMB connect/play evidence does not prove download recovery.

## Progress

- **2026-08-28:** Validation plan created. Existing `[Debug][Downloads]` enqueue, task, restore, and action logs are sufficient. No device SMB download run has been recorded.
- **2026-08-28:** Operator recorded a physical-device SMB run. A fresh browser enqueue created one `type=smb` movie task. The task paused at `received=20971520`, was resumed in the same session, then the app was terminated while `received=25165824`. Cold-launch restored that same task at `received=25165824` (not 0). The download then continued to `completed` at `50593792`. Pre-existing Emby rows were ignored.

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-08-28 |
| Device | Physical iOS Debug |
| App | Vanmo iOS Debug, already signed |
| Source type | SMB via an existing device connection |
| Task | Fresh Files-browser movie enqueue |

Private hostnames, usernames, credentials, share paths, and media titles are omitted.

## Acceptance Record

One physical-device SMB run on 2026-08-28. The first `restore count=5` block lists leftover Emby tasks and is not SMB evidence. The recorded SMB task id is `84165775-BF88-4BB9-AF6B-D0E5CF1B9531`.

The operator paused, then resumed in the same session, then terminated while the task was active. Cold-launch therefore restored `downloading` rather than `paused`. Recovery is still proven: the `.part` offset survived terminate.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Physical device, source type SMB | Pass | Operator device Debug session |
| 2. Fresh Files-browser enqueue | Pass | `enqueued source=browser connection=smb` |
| 3. `type=smb` and progress increases | Pass | `received` rose through 8388608, 12582912, 16777216, 20971520 |
| 4. Pause after `received > 0` | Pass | `status=paused` `received=20971520` |
| 5–6. Terminate and cold-launch | Pass | Same-session resume first; terminate while `received=25165824` |
| 7. Same task restored, `received` not 0 | Pass | `restore task=84165775-... status=downloading received=25165824` |
| 8. Continue from the restored offset | Pass | After launch, `received=33554432` then `completed` `50593792`; still one SMB task |
| 9. Sanitized Console record | Pass | `[Debug][Downloads]` excerpt; no credentials or titles |

## Outcome

Physical-device iOS SMB enqueue, same-session resume, terminate while downloading, `.part` restore, and completion are recorded. This record does not prove a paused-across-kill path, macOS SMB download, XCUITest, or an expansion of the macOS HTTP recovery matrix.

## Open Decisions

None.
