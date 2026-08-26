# Execution Planning

This document defines how Vanmo plans are created, maintained, verified, and archived.

## Documentation Boundary

- `docs/` is Vanmo's only Harness documentation root for product intent, design decisions, quality, reliability, security, frontend standards, execution plans, and progress.
- Active plans hold current execution state, verification evidence, risks, decisions, and the next step. Completed plans preserve outcomes; quality and confirmed debt remain in their dedicated documents.
- Current code and tests, `project.yml`, `Packages/VanmoCore/Package.swift`, and `ARCHITECTURE.md` remain authoritative for implementation and architecture. A plan must not contradict those sources or present intended behavior as implemented behavior.

## When a Plan Is Required

Create an execution plan when work:

- spans more than one session or subsystem
- changes persistence, navigation, player engines, remote protocols, synchronization, target configuration, or security boundaries
- has non-trivial manual acceptance, rollout, or recovery risk
- depends on an open product or technical decision
- validates an existing feature in a real environment before its evidence can be upgraded

Small, single-session changes may proceed without a dedicated plan when their scope and verification are obvious.

## Plan Locations

- `docs/exec-plans/active/`: work that is not complete, including not-started validation plans
- `docs/exec-plans/completed/`: finished plans with recorded evidence and outcomes
- `docs/exec-plans/tech-debt-tracker.md`: confirmed, intentionally deferred debt

## Required Plan Content

Each plan must include:

- objective and user-visible outcome
- scope and explicit out-of-scope boundaries
- verification steps and required evidence
- risks and blockers
- progress log with dated factual updates
- open decisions

## Operating Rules

- Work from one bounded current step at a time.
- Record status from evidence, not implementation confidence.
- Use `not started`, `in progress`, `blocked`, or `completed`; explain any blocker.
- Never weaken, replace, or silently skip an acceptance step to close a plan.
- Keep credentials, tokens, complete authenticated URLs, and private media details out of plans and evidence.
- A manual-acceptance plan does not authorize implementation expansion. If validation exposes a defect, record it and obtain a separately scoped fix.
- Move a plan to `completed/` only after every required verification step has passed or the plan explicitly records a superseding decision.

## Related Update Rules

When work changes:

- user-visible behavior or acceptance criteria: update the relevant file in `docs/product-specs/`
- a durable design decision or boundary: update `docs/design-docs/` and, when architectural, `ARCHITECTURE.md`
- verification commands, runtime evidence, or recovery expectations: update `docs/RELIABILITY.md`
- domain or layer confidence: update `docs/QUALITY_SCORE.md`
- confirmed deferred risk: update `docs/exec-plans/tech-debt-tracker.md`
- secrets, data handling, external actions, or dependency trust: update `docs/SECURITY.md`
- platform UI conventions or validation expectations: update `docs/FRONTEND.md`
- current execution progress, evidence, risks, or next action: update the governing active plan
