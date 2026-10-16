# SwiftData Schema V1

**Status:** Completed

## Objective

Give the current SwiftData models an explicit version and migration plan before the next non-additive change.

## Scope

- Added `VanmoSchemaV1` (`Schema.Version(1, 0, 0)`) listing the seven current models in container order.
- Added `VanmoSchemaMigrationPlan` with that single schema and no stages.
- `ModelContainerFactory.makeContainerThrowing` now opens with that plan. Callers can pass `nil` to reproduce an unversioned open.

## Out of Scope

- A second schema version or a real migration stage
- Custom `MigrationStage` closures. CloudStore can attach CloudKit, which accepts lightweight stages only
- Removing the one-time unreadable-store delete or the second-failure `fatalError`

## Verification

- `swift test --package-path Packages/VanmoCore`: 279 tests, 0 failures
- `testStoreWrittenWithoutMigrationPlanReopensWithCurrentPlan` writes `MediaItem` and `SavedConnection` with `migrationPlan: nil`, then opens the same files with `VanmoSchemaMigrationPlan` and reads both rows back
- `testVersionedSchemaMatchesTheContainerModels` compares `VanmoSchemaV1` model names with `ModelContainerFactory.schema.entities`. Those entities are alphabetical, so the assertion sorts both sides
- In-memory CloudKit configuration still creates a container
- iOS Simulator Debug `20261016-095514-99931` and macOS Debug `20261016-095553-292`: pass

## Risks

- A future non-additive change still has to add a later version and a lightweight stage. Shipping that change without the stage can fail existing stores.
- This run did not reopen a user's existing CloudStore or LocalStore on a device.

## Progress Log

- 2026-10-16: Added version 1 and the empty plan, and confirmed an unversioned store reopens with both rows intact.

## Open Decisions

- None.
