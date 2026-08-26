# Design

This is the entry point for durable Vanmo product and system design decisions. Detailed decisions live under `docs/design-docs/`; the current implementation map and hard dependency boundaries remain in `ARCHITECTURE.md`.

## Read This When

- introducing a new architectural or interaction pattern
- changing persistence, synchronization, playback, navigation, remote-service, or platform boundaries
- deciding whether behavior belongs in `VanmoCore`, the iOS app, or the macOS app
- checking whether a design decision is accepted, proposed, or deprecated

## Current Design Shape

- `VanmoCore` owns cross-platform models and infrastructure and must not import SwiftUI, UIKit, or AppKit.
- iOS and macOS own separate navigation, presentation, player adapters, and platform lifecycle behavior.
- Shared UI is intentional and narrow; only platform-neutral components needed by both targets should be shared.
- SwiftData separates local media data from optional cloud-backed connection, bookmark, and minimal media-state data.
- Credentials remain outside SwiftData in Keychain or OAuth storage.
- Figma is the visual source of truth for UI changes, with platform-specific designs and runtime validation.

## Canonical Design Documents

- `docs/design-docs/index.md`: status and discovery index
- `docs/design-docs/core-beliefs.md`: durable Vanmo design and agent-harness beliefs
- `ARCHITECTURE.md`: implemented boundaries, targets, data flows, and known risks

## Maintenance Rules

- Prefer one focused design document per decision area.
- Link plans and product specs to the decisions they depend on.
- Separate accepted implementation from proposals and unverified assumptions.
- Update `ARCHITECTURE.md` in the same change when a decision alters a documented boundary, target, dependency, store assignment, data flow, protocol capability, or architectural risk.
- Promote repeatedly violated critical rules into static checks or tests where practical.
