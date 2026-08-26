# Harness Narrative Consistency

**Status:** Completed  
**Plan type:** Harness infrastructure  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Upgrade the Advanced Harness documentation check from “links exist” to “the live narrative agrees with the commands and plan indexes it describes.”

A later agent must not treat a green documentation stage as proof that `./init.sh` still has the documented stage count, that active/completed indexes match their files, or that QUALITY’s current baseline points at real entry commands.

## Scope

- Extend `scripts/check-harness-docs.sh` in place. Do not add an `./init.sh` stage.
- Check fast-baseline stage count, active/completed index coverage and Status, product-spec/plan Status, and QUALITY current-baseline command paths.
- Update reliability and routing copy so the documentation stage is described as a narrative check, not only a link check.

## Out of Scope

- A second documentation script or a fifth default `./init.sh` stage
- Asserting the `36` VanmoCore test count
- Scanning QUALITY Benchmark Snapshots historical rows
- Scanning `templates/`
- XcodeGen drift, SwiftSyntax, stale-plan gardening, or local log export
- Archiving the debug-build-evidence-layer plan or renaming `Implemented` to `completed`
- App code, XCUITest, or `./init.sh --full`

## Verification

1. `./scripts/check-harness-docs.sh` exits 0 on the current tree.
2. Changing RELIABILITY Bootstrap `four` to `five` makes the check fail with a stage-count mismatch.
3. Changing the active-index status of the macOS download plan to `Completed` makes the check fail with an index/plan Status mismatch.
4. Restoring both edits makes the check pass again.
5. Fast `./init.sh` still runs four stages and does not compile apps or run XCUITest.

## Risks

- Over-matching historical QUALITY rows or unrelated “stage” wording would create false failures. Limit live excerpts to RELIABILITY Bootstrap, QUALITY current baseline, and the ARCHITECTURE `./init.sh` baseline paragraph.
- Completed-index entries that omit a bold status would fail the new Status rule. Add `**Completed.**` where the file already records completion.

## Progress

- **2026-08-26:** Plan created. Implementation starts from the existing link checker.
- **2026-08-26:** Extended `scripts/check-harness-docs.sh` with live stage-count, plan-index Status, spec/plan Status, and QUALITY command-path checks. RELIABILITY, AGENTS, and ARCHITECTURE now describe the documentation stage as a narrative check. Current-tree `./scripts/check-harness-docs.sh` passed with 0 failures. Injecting `five baseline stages` into RELIABILITY Bootstrap failed with `stage-count mismatch: docs/RELIABILITY.md Bootstrap claims 5 (five baseline stages), init.sh fast baseline has 4`. Injecting `**Completed.**` for the macOS download plan in the active index failed with `index/plan Status mismatch`. Both edits were restored; the check passed again. Fast `./init.sh` completed all four stages with 0 failures and did not compile apps or run XCUITest.
- **2026-08-26:** Post-task review tightened Status matching to the phrase before `.` or `;`, so `Not started` no longer collapses to `not`. Bootstrap stage-count now stops before the `--full` continuation. Unparseable Status fails instead of matching `None == None`.

## Open Decisions

- None. Status vocabulary stays as written in each plan; only the first status word must match across index, plan, and linked spec.
