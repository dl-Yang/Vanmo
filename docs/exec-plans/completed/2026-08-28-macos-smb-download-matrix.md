# macOS SMB Download Matrix

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-08-28  
**Plan type:** Manual acceptance of existing behavior  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record whether the native macOS app can complete the downloads real-source matrix against a real SMB source: one movie and two or three episodes from the same series, no duplicates, individual and global pause/resume, restart from existing `.part` files, and main-window detail navigation without a second main window.

This is a factual acceptance record. It does not authorize download-engine changes.

## Scope

- Use `Vanmo-macOS` Debug and an existing SMB connection.
- Queue fresh SMB items. Do not treat leftover Emby or iOS tasks as evidence.
- Exercise pause, pause-all, resume, terminate without reinstalling, cold-launch, `.part` continue, and download-row detail navigation.
- Record sanitized `[Debug][Downloads]` lines.

## Out of Scope

- Changing the VanmoCore download engine or adding protocols
- The downloads-spec Related Plan or macOS HTTP `Current acceptance status`
- iOS device work
- `xcodegen` regeneration
- XCUITest or remote logging
- Figma or unrelated player work

If the flow exposes a defect, stop at a reproducible, sanitized record. A separately scoped fix plan is required before implementation.

A claimed one-item macOS SMB download without Console evidence is not recorded separately. This matrix run is the macOS SMB download evidence.

## Verification

1. Record macOS Debug and source type SMB, without hostnames or credentials.
2. Connect to the existing SMB source.
3. Queue one movie and two or three episodes from the same series. Prefer library detail so episode `mediaType` is preserved. If the show exists only in Files, queue one standalone video plus two or three files from the same show folder and record the actual `media=` values.
4. Confirm each intended item appears once and no duplicate SMB tasks are created.
5. Pause and resume one task.
6. Pause all, then resume all.
7. Quit the app while at least one SMB task is incomplete. Do not rebuild.
8. Cold-launch and confirm unfinished SMB tasks restore with non-zero `received` from `.part` files, then continue.
9. Select the movie task; the existing main window activates at the movie detail. No second main window.
10. Select each episode task; the existing main window activates at the show or episode. No second main window.
11. Copy sanitized `[Debug][Downloads]` lines.

The eleven-step matrix completes only when every step passes in one recorded run. Run 3 is that run. Runs 1 and 2 remain as earlier partial records.

## Risks

- Files-browser SMB enqueue currently records `media=movie` for remote files, so episode identity may be missing unless the items come from library detail.
- Rebuilding after pause can lose `.part` paths.
- Leftover Emby rows must not be counted as SMB matrix items.
- Short files may complete before pause and restart can be observed.
- A navigation result can look correct while opening a duplicate main window.

## Progress

- **2026-08-28:** Validation plan created. macOS `[Debug][Downloads]` restore, enqueue, list, pause-all, resume-all, and open-detail logs were added. No matrix run has been recorded.
- **2026-08-28:** Operator recorded one Vanmo-macOS SMB Files-browser run and reported that the main window was not duplicated. Console proved three fresh `type=smb` `media=movie` tasks, `pauseAll` / `resumeAll`, and one unfinished task continuing after restart. A second unfinished task restored as `failed` and later restarted at `received=0`. Individual pause and `open detail` lines were absent.
- **2026-08-28:** Operator attributed the Run 1 `failed` restore to local disk exhaustion. The downloads window showed the failure state. After freeing space, later `.part` continuations succeeded. That path is not engine debt and does not need a separately scoped fix.
- **2026-08-28:** Operator recorded a second Vanmo-macOS SMB run from library detail: three fresh `media=tvEpisode` tasks, `pauseAll` / `resumeAll`, clean `restore count=0` at enqueue, and one unfinished task restoring `queued received=872415232` then completing. No movie task, no individual pause/resume of those three ids, and no `open detail` line. A later `90437F32` paused line is a fourth id and is not matrix-task pause evidence.
- **2026-08-28:** Operator recorded a third Vanmo-macOS SMB library-detail run: one `media=movie` plus three `media=tvEpisode` tasks, `pauseAll`, inferred single-task resume then pause of `90337EE5`, `resumeAll`, restart `.part` continuation of that task, `open detail` for the movie and one episode, and no second main window. This run passes the eleven-step matrix.

## Environment

| Item | Run 1 | Run 2 | Run 3 |
| --- | --- | --- | --- |
| Date | 2026-08-28 | 2026-08-28 | 2026-08-28 |
| App | `Vanmo-macOS` Debug | `Vanmo-macOS` Debug | `Vanmo-macOS` Debug |
| Source type | SMB via Files browser | SMB via library detail | SMB via library detail |
| Fresh SMB tasks | 3, all `media=movie` | 3, all `media=tvEpisode` | 1 `media=movie` + 3 `media=tvEpisode` |
| Leftover rows | 3 completed Emby episodes, ignored | `restore count=0` at enqueue | `restore count=0` at enqueue |

Private hostnames, usernames, credentials, share paths, and media titles are omitted.

## Acceptance Record

### Run 1 — Files browser

One macOS SMB Files-browser run on 2026-08-28. The first `restore count=3` line is leftover completed Emby tasks. Fresh SMB task ids: `EF4B9101-...`, `89A848B4-...`, `91EC880A-...`.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Record environment and source type | Pass | macOS Debug; SMB |
| 2. Connect to SMB | Pass | `enqueued source=browser connection=smb` three times |
| 3. One movie and two or three episodes | Partial | Three Files-browser items; all `media=movie`; no `tvEpisode` |
| 4. No duplicate SMB tasks | Pass | Three distinct SMB ids; `appear count=6` includes leftover Emby |
| 5. Pause and resume one task | Fail | No single-task pause/resume line |
| 6. Pause all, then resume all | Pass | `action pauseAll` then `action resumeAll`; `89A848B4` continued from ~37% |
| 7. Quit while incomplete | Pass | Cold-launch restore followed |
| 8. Restore unfinished tasks from `.part` and continue | Partial | `91EC880A` restored `queued received=121634816` and completed. `89A848B4` restored `failed received=671088640`, then later `queued received=0` and completed from the start. Operator later attributed that failure to local disk exhaustion with a correct downloads-window failure state, not an engine defect |
| 9. Movie row opens existing main window | Operator | Operator reported no second main window; no `open detail` Console line |
| 10. Episode rows open existing main window | Partial | No episode-typed SMB tasks; operator reported no second main window; no `open detail` line |
| 11. Sanitized Console record | Pass | Excerpt above |

### Run 2 — Library detail

A second Vanmo-macOS SMB run on 2026-08-28. Fresh SMB task ids: `D5B8E1EA-...`, `F51E57CB-...`, `44BF57AA-...`. Enqueue started from `restore count=0`.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Record environment and source type | Pass | macOS Debug; SMB |
| 2. Connect to SMB | Pass | `enqueued source=detail mediaType=tvEpisode connection=smb` three times |
| 3. One movie and two or three episodes | Partial | Three detail items; all `media=tvEpisode`; no movie |
| 4. No duplicate SMB tasks | Pass | Three distinct SMB ids; `appear count=3` |
| 5. Pause and resume one task | Fail | No single-task pause/resume of the three ids. A later `90437F32` `paused` line is a fourth id with no enqueue or resume |
| 6. Pause all, then resume all | Pass | `action pauseAll` then `action resumeAll`; `F51E57CB` continued from ~21% |
| 7. Quit while incomplete | Pass | Cold-launch restore followed |
| 8. Restore unfinished tasks from `.part` and continue | Pass | `F51E57CB` restored `queued received=872415232` and then appeared completed. `D5B8E1EA` restored `queued received=0` because it never received bytes, then completed from the start |
| 9. Movie row opens existing main window | Partial | No movie task; operator reported no second main window; no `open detail` line |
| 10. Episode rows open existing main window | Operator | Operator reported no second main window; no `open detail` Console line |
| 11. Sanitized Console record | Pass | Excerpt above |

### Run 3 — Library detail mixed movie and episodes

A third Vanmo-macOS SMB run on 2026-08-28. Fresh SMB task ids: `E57B4B5A-...` (`movie`), `2210DC73-...`, `90337EE5-...`, `4ABD0C49-...` (`tvEpisode`). Enqueue started from `restore count=0`.

| Step | Result | Notes |
| --- | --- | --- |
| 1. Record environment and source type | Pass | macOS Debug; SMB |
| 2. Connect to SMB | Pass | One `enqueued source=detail mediaType=movie connection=smb` and three `mediaType=tvEpisode` |
| 3. One movie and two or three episodes | Pass | Four distinct tasks: one `media=movie`, three `media=tvEpisode`. Console does not name the series |
| 4. No duplicate SMB tasks | Pass | Four distinct SMB ids; `appear count=4` |
| 5. Pause and resume one task | Pass | After `pauseAll`, only `90337EE5` returned to `queued`/`downloading` while `2210DC73` stayed paused. `90337EE5` later reached `paused` at 44% without `pauseAll`. Row pause/resume buttons do not print an `action pause`/`action resume` line |
| 6. Pause all, then resume all | Pass | `action pauseAll`; later `action resumeAll` continued `90337EE5` from ~45% |
| 7. Quit while incomplete | Pass | Cold-launch restore followed |
| 8. Restore unfinished tasks from `.part` and continue | Pass | `90337EE5` restored `queued received=813694976` and continued to completed. `2210DC73` restored `queued received=0` because it never received bytes, then completed from the start |
| 9. Movie row opens existing main window | Pass | `open detail task=E57B4B5A-... mediaType=movie`; operator reported no second main window |
| 10. Episode rows open existing main window | Pass | `open detail task=2210DC73-... mediaType=tvEpisode`; operator reported no second main window. The other two episode rows were not logged |
| 11. Sanitized Console record | Pass | Excerpt above |

## Outcome

Three macOS SMB runs are recorded. Run 3 is the first run that passes the eleven-step matrix: library-detail enqueue of one movie and three episodes, no duplicates, inferred single-task pause/resume of `90337EE5`, global pause/resume, restart `.part` continuation of that task, and Console-backed movie plus episode `open detail` with no second main window.

Run 1 remains an earlier Files-browser partial. Its `failed` restore was local disk exhaustion with a correct failure UI, not an engine defect; after space was freed, later runs continued from `.part` files. Run 2 remains the earlier episode-only partial. This record does not change the macOS HTTP acceptance status or authorize an engine fix.

## Open Decisions

- Superseding decision: treat Run 3 as the passing matrix record; keep Runs 1 and 2 as earlier partial evidence.
- No separately scoped fix for the Run 1 `failed` restore. Operator attributed it to local disk exhaustion; the downloads window showed the failure state.
