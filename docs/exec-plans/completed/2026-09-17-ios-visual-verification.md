# iOS Visual Verification

**Status:** Completed  
**Created:** 2026-09-17  
**Plan type:** Harness infrastructure  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Replace the iOS UI-test target and CLI with visual evidence: physical-device screenshots plus a screen recording, and agent-operated Simulator walks.

## Scope

- Remove the iOS UI-test target, the UI CLI, and its static checker
- Reduce the fast `./init.sh` baseline from four stages to three
- Document device screenshot/recording evidence and agent-operated Simulator captures
- Update current architecture, reliability, frontend, quality, SOP, and remaining-work language

## Out of Scope

- Changing app accessibility identifiers
- Capturing a new product journey in this change
- Raising QUALITY_SCORE domain grades

## Verification

1. `xcodegen generate`
2. `./scripts/check-architecture-guards.sh`
3. `./scripts/check-harness-docs.sh`
4. Fast `./init.sh` runs three stages and does not invoke a UI-test target

## Progress

- 2026-09-17: Removed the UI-test target, UI CLI, and its static checker. Regenerated the Xcode project. `./scripts/check-architecture-guards.sh` passed. `./scripts/check-harness-docs.sh` passed. Fast `./init.sh` completed three stages with 208 `VanmoCore` tests, 0 failures.

## Outcome

The repository no longer has a UI-test target or UI CLI. iOS physical-device UI evidence is screenshots plus a screen recording after `./run_device.sh`. Simulator UI evidence is an agent-operated `./run_device.sh --simulator` walk with `simctl` captures. Fast `./init.sh` is three stages.

## Remaining

None. Broader product journeys still use the same visual evidence rules.
