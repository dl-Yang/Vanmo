# Vanmo Standard Operating Procedures

These SOPs turn Vanmo's durable architecture, reliability, security, and
frontend rules into repeatable working loops. They supplement the linked source
documents; they do not replace current code, `project.yml`, or
`ARCHITECTURE.md`.

## Available SOPs

- [`layered-domain-architecture.md`](./layered-domain-architecture.md):
  place changes across `VanmoCore`, iOS, macOS, SwiftData, CloudKit, and
  generated Xcode configuration
- [`encode-knowledge-into-repo.md`](./encode-knowledge-into-repo.md):
  route durable decisions and session state into one discoverable source
- [`local-observability-feedback-loop.md`](./local-observability-feedback-loop.md):
  diagnose runtime behavior with local, non-sensitive console evidence
- [`apple-ui-validation-loop.md`](./apple-ui-validation-loop.md):
  validate Figma fidelity and Apple-platform journeys with BEFORE/AFTER
  evidence

## Use

1. Select the SOP matching the current boundary or evidence problem.
2. Read its linked authoritative documents before changing implementation.
3. Run one bounded loop and record only evidence actually observed.
4. Promote repeated failures into focused tests, static checks, or durable
   guidance without creating a duplicate source of truth.
