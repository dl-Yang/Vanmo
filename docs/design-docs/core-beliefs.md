# Vanmo Core Beliefs

**Status:** Accepted  
**Last reviewed:** 2026-08-25  
**Update trigger:** A product, architecture, verification, or agent-workflow decision contradicts one of these beliefs.

## Product

- Vanmo exists to make personal video from local and remote sources feel dependable, understandable, and native on Apple platforms.
- Reliability and recovery are more valuable than a long list of nominal integrations.
- Source identity, playback progress, download progress, and navigation context are user trust.
- A visible feature is not accepted until its relevant platform and source journey has evidence.

## Architecture

- Current code and tests, `project.yml`, and `Packages/VanmoCore/Package.swift` outrank narrative documentation.
- `VanmoCore` owns shared domain and infrastructure behavior without platform UI frameworks.
- iOS and macOS share infrastructure, not forced presentation. Their navigation, player windows, lifecycle, and interaction models remain platform-specific.
- Credentials stay in Keychain or OAuth storage; SwiftData stores only data appropriate to its assigned local or optional cloud configuration.
- Expiring or credential-bearing playback URLs are resolved at use time rather than persisted as catalog truth.
- Main-actor UI state and actor-isolated background state should have explicit ownership.

## Design and Accessibility

- Figma is the visual source of truth for each platform.
- Missing UI states are designed before they are improvised in code.
- Empty, loading, success, error, and retry experiences are part of the feature.
- Accessibility, keyboard behavior, pointer behavior, and lifecycle cleanup are acceptance requirements, not optional polish.

## Evidence

- Verification evidence matters more than confidence.
- Tests prove only the behavior they execute; static checks prove only their encoded boundaries.
- Builds, launches, manual journeys, real-source checks, and real CloudKit validation are distinct evidence classes.
- Unrun evidence remains unverified and is labeled accordingly.
- Known failures are recorded rather than hidden by weaker checks.

## Agent Harness

- `docs/` is the sole Harness system of record, including current execution state and durable decisions.
- One bounded task with explicit scope is better than several partially completed changes.
- Plans remain live records of progress, risks, and decisions.
- Repeated review feedback should become a reusable rule, test, static check, or validation step.
- Simplification is measured by preserving the same verification outcome after removing complexity.
- A fresh session should be able to bootstrap from repository commands and discover the next safe action without relying on chat memory.
