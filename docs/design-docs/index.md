# Design Documents Index

This index is the discoverable map of durable Vanmo design decisions.

## Accepted

- [`core-beliefs.md`](core-beliefs.md): product, architecture, evidence, platform, data, and agent-harness beliefs
- [`ui-design-standards.md`](ui-design-standards.md): required `ui-ux-pro-max` workflow and general iOS/macOS UI quality rules; Figma and existing tokens stay above skill output
- [`icloud-keychain-password-sync.md`](icloud-keychain-password-sync.md): connection passwords stay on-device Keychain; iCloud Keychain sync rejected; CloudKit passwords forbidden
- [`../../ARCHITECTURE.md`](../../ARCHITECTURE.md): implemented system map and hard boundaries

## Proposed

No proposed design documents are currently recorded.

## Deprecated

- [`ui-desgin-style.md`](ui-desgin-style.md): superseded by [`ui-design-standards.md`](ui-design-standards.md); filename retained so the old path still resolves

## Maintenance Rules

- Give each new document a status, decision area, date, and update trigger.
- Keep proposals separate from accepted implementation.
- Deprecate superseded documents with a replacement link instead of leaving conflicting guidance.
- Link active execution plans and product specs to the design documents they depend on.
- Update `ARCHITECTURE.md` when a decision changes an implemented architectural boundary or risk.
