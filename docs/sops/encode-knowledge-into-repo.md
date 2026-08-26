# SOP: Encode Knowledge Into the Repository

Use this SOP when a decision, acceptance rule, operational constraint, or
session discovery exists only in chat, an external document, or memory.

## Goal

Make the fact discoverable to a fresh contributor without creating competing
sources of truth.

## Routing Map

- Implemented architecture, targets, data flows, persistence assignments, and
  known structural risks: [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md)
- Durable design rationale and accepted/proposed decisions:
  [`../DESIGN.md`](../DESIGN.md) and `docs/design-docs/`
- Product judgment that code cannot express safely:
  [`../PRODUCT_SENSE.md`](../PRODUCT_SENSE.md)
- User-visible behavior and acceptance criteria: `docs/product-specs/`
- Plan lifecycle policy and active/completed execution state:
  [`../PLANS.md`](../PLANS.md) and `docs/exec-plans/`
- Evidence-based domain and layer health:
  [`../QUALITY_SCORE.md`](../QUALITY_SCORE.md)
- Build, restart, diagnostics, golden journeys, and evidence boundaries:
  [`../RELIABILITY.md`](../RELIABILITY.md)
- Credentials, private data, URLs, external actions, and dependency trust:
  [`../SECURITY.md`](../SECURITY.md)
- Figma, platform UI, accessibility, and visual validation:
  [`../FRONTEND.md`](../FRONTEND.md)
- Compact model-readable extracts of verified upstream facts:
  [`../references/`](../references/)
- Reproducible derived artifacts: [`../generated/`](../generated/)
- Current execution progress, evidence, risks, decisions, and next action:
  the governing plan under `docs/exec-plans/active/`

`docs/` is the sole Harness system of record. Route each fact to one owning
artifact instead of creating a parallel session-document layer.

## Execution SOP

1. Reduce the source material to one operational fact, decision, rule, or
   evidence claim. Do not copy a meeting transcript.
2. Classify it using the routing map.
3. Check the destination and neighboring documents for an existing statement.
4. Update the existing authoritative statement when possible. Create a new
   focused document only when the destination has no suitable home.
5. Link dependent plans, specs, SOPs, or references to the authority instead of
   duplicating its full wording.
6. Label proposed, implemented, and unverified information distinctly. Do not
   convert intention or code inspection into runtime evidence.
7. Remove or deprecate a stale duplicate only when it is within the current
   task's scope; otherwise record the conflict for the owner.
8. Keep secrets, complete authenticated URLs, private media details, and
   credentials out of every repository document.

## Conflict Rule

When documents disagree, verify against current code and tests, `project.yml`,
`Packages/VanmoCore/Package.swift`, and `ARCHITECTURE.md` in that order of
applicability. Correct the routed durable document and replace repeated copies
with links.

## Definition of Done

- A fresh session can find the fact from an index or routing document.
- One artifact owns the statement; other artifacts link to it.
- Status and evidence wording match what was actually observed.
- Current work state is recoverable from the active-plan index and governing plan.
