# Generated Documentation Policy

`docs/generated/` is reserved for reproducible, mechanically derived artifacts
that help humans and agents inspect Vanmo without reverse-engineering source
files on every session.

Every generated artifact must identify:

- the authoritative source path or exact generation command
- the date it was last refreshed
- the tool or environment assumptions required to reproduce it
- a clear instruction not to hand-edit generated content

Refresh an artifact whenever its source changes. If generation cannot be
repeated reliably, the material does not belong in this directory; place a
maintained summary in [`../references/`](../references/) or a durable decision
in the appropriate design document instead.

## Current State

Vanmo does not currently have a reliable generator for a SwiftData schema
document. The live store assignments are defined in
`Packages/VanmoCore/Sources/VanmoCore/Storage/ModelContainerFactory.swift`, and
the repository has no explicit `VersionedSchema` or `SchemaMigrationPlan`.
Therefore this directory intentionally contains no synthetic database-schema
artifact. Do not create or label a manually assembled schema as generated.
