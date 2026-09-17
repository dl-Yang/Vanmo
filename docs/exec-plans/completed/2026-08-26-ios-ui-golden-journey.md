---
title: iOS UI Golden Journey - Plan
type: chore
date: 2026-08-26
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-ready
product_contract_source: ce-plan-bootstrap
execution: code
---

# iOS UI Golden Journey - Plan

**Status:** Completed; first simulator journey recorded  
**Plan type:** Harness infrastructure  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

**Superseded 2026-09-17:** The UI-test target and CLI used to record this walk were removed. Current iOS UI evidence is physical-device screenshots plus a screen recording, and agent-operated Simulator walks.

## Objective

Unlock one repeatable iOS tab-navigation golden journey that an agent can run without a physical device or signing identity.

## Outcome

- Repaired the Settings `.paused` compile blocker.
- Added stable identifiers: `screen.library`, `screen.settings`, `tab.library`, and `tab.settings`.
- 2026-08-26: Focused `./scripts/check-app-build.sh ios-simulator` passed (`xcodebuild` 0, evidence `build/app-build-evidence/runs/20260826-145050-52563/ios-simulator`).
- 2026-08-26: iPhone 17 Pro Simulator (`0811807F-3DD6-4DF5-B5B3-C734ABC76F1F`) with Xcode 26.0.1 / Swift 6.2 recorded a tab-navigation walk: library screen present, Settings tap, settings screen present. Fast `./init.sh` then passed 4/4 stages. Historical attachments were retained under `build/ui-cli/runs/20260826-145830-63647`.

## Remaining

None. Later iOS UI evidence uses screenshots, recordings, or agent-operated Simulator walks.
