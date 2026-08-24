# Evaluator Rubric

Use this rubric after substantive implementation and before final acceptance. Score each dimension from 0 to 2 and cite specific files, commands, or manual verification records.

| Dimension | 2 points | 1 point | 0 points | Score and evidence |
| --- | --- | --- | --- | --- |
| Correctness | Requested behavior is fully implemented with no known regression | Core behavior works with a documented edge-case gap | Target behavior is wrong, missing, or has an undisclosed regression |  |
| Verification | `./init.sh` and affected-platform verification actually passed, with manual steps recorded | Automated checks passed, but device, UI, or external-service paths are explicitly unverified | Required verification was not run, or completion was claimed after failure |  |
| Scope discipline | Every change traces directly to the current task | A necessary narrow supporting change is included and explained | Unrelated refactoring, features, or formatting are mixed in |  |
| Reliability | Restart, recovery, or repeated execution paths were verified | Only a single execution passed; recovery remains unverified but documented | The result depends on temporary state, manual repair, or non-repeatable steps |  |
| Maintainability | Module, concurrency, and persistence boundaries are respected; tests and documentation are clear | The result is readable and maintainable with explicit technical debt | Boundaries are broken, credentials are exposed, concurrency is unsafe, or continuity is poor |  |
| Handoff readiness | Progress, feature state, risks, and next step all match the repository | Work can continue, but one non-critical record is missing | A new session cannot determine the true state from repository artifacts alone |  |

## Mandatory Blocking Conditions

The verdict cannot be Accept if any condition below applies:

- A required test or build failed.
- A `passing` feature lacks evidence, or VanmoCore tests are presented as app UI/device verification.
- Build configuration changed without updating `project.yml` and regenerating the Xcode project.
- The change introduces credential exposure, cross-actor `ModelContext` use, or platform UI in `VanmoCore`.
- Unrelated user changes were overwritten, deleted, or committed.

## Verdict

- **Accept:** 11–12 total points and no mandatory blocking condition.
- **Revise:** 7–10 total points, or a verification/handoff gap that can be fixed within the current task.
- **Block:** 0–6 total points, or a mandatory blocking condition that cannot be resolved within the current task.

## Required Follow-Up

- Missing evidence:
- Required fixes:
- Unverified risks:
- Next review trigger: