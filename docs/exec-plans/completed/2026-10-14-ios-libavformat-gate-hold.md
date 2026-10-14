# iOS libavformat Gate Hold Ownership

**Status:** Completed
**Related product spec:** [`../../product-specs/playback-performance.md`](../../product-specs/playback-performance.md)

## Objective

Make sure a superseded iOS KSPlayer load can release only the `LibavformatOpenGate` share it acquired. The 2026-10-14 review found that one instance-level flag could let a load whose main-actor step was delayed past the 400 ms protocol-close drain release the gate that a newer load already held. That opens the known libsmbclient `talloc` crash path.

## Scope

- `LibavformatGateHold` in `VanmoCore/Infrastructure`: each acquire gets a hold id; `consume()` releases the current holder, and `consume(id)` releases only that holder
- iOS `KSPlayerEngine`: stop, a new load, and deinit release the current holder after the protocol-close drain. A superseded load that never created its player releases only its own hold id, immediately, because it never opened a protocol context

## Out of Scope

- The macOS engine, which does not hold the gate across a session
- Waiting for the actual KSPlayer close (tracked separately with the SMB thumbnail concurrency work)

## Verification

- `swift test --package-path Packages/VanmoCore`, including `testLibavformatGateHoldReleasesOnlyMatchingHolder`
- Serial `./scripts/check-app-build.sh ios-simulator`, then `macos`
- `./scripts/check-architecture-guards.sh`

## Risks

- No device walk of rapid SMB episode switching: it needs an SMB series scanned into the iOS library. The race needs a main-thread stall longer than 400 ms, so a manual walk is unlikely to hit it either.

## Progress Log

- 2026-10-14: Added `LibavformatGateHold` and moved the iOS engine to it. VanmoCore passed 263 tests. iOS Simulator Debug passed `20261014-100550-1734`, then macOS Debug `20261014-100628-1994`. Architecture guards reported 0 failures.

## Open Decisions

- None.
