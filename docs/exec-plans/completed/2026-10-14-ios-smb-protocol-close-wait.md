# iOS SMB Protocol Close Wait

**Status:** Completed
**Related product spec:** [`../../product-specs/playback-performance.md`](../../product-specs/playback-performance.md)

## Objective

Stop the iOS libsmbclient crashes that happen when a new SMB open overlaps the teardown of the previous KSPlayer instance. Files thumbnails, media probes, and playback already share `LibavformatOpenGate`. The gap was the release point: KSPlayer `shutdown()` only queues `avformat_close_input` behind the read thread, and the gate reopened after a fixed 400 ms drain.

## Evidence Before the Change

On 2026-10-14 the operator opened an SMB folder in Files on the iPhone and let thumbnails load. The app crashed twice; neither crash involved playback:

- `Vanmo-2026-10-14-102355.ips`, SIGABRT `talloc_abort_access_after_free`: one thumbnail's read thread was still in `smbc_read` while the next thumbnail's open thread was in `smbc_open` → `smbc_fstat`.
- `Vanmo-2026-10-14-102432.ips`, SIGSEGV `tevent_trace_point_callback`: one thumbnail's open thread was in `smbc_open` session setup while the previous close thread was still in `smbc_free_context`.

## Scope

- VanmoCore `LibavformatProtocolClose` hands a "close finished" probe from the platform code that shut down KSPlayer to the gate
- `LibavformatOpenGate`:
  - `exclusive(awaitingClose:)` and `releaseAfterProtocolClose(_:)` poll that probe every 50 ms, up to 120 s, then run the existing drain. A stalled read and each teardown request (close, tree disconnect, logoff) can each hit libsmbclient's 20 s timeout, and reopening mid-teardown crashes, so SMB opens queue behind a slow close instead
  - The close wait and the drain now run in their own tasks, so a cancelled thumbnail task can no longer skip them
- iOS `KSMEPlayer.shutdownObservingProtocolClose()` finds the private serial `playerItem.operationQueue` by reflection. The close counts as finished when that queue is empty, because the close runs after the read or open and cancels anything queued later. Reading only that immutable property avoids racing the open and close threads on mutable fields. It holds the queue weakly. If the property is missing it logs an error on every call and falls back to the drain
- iOS `KSPlayerEngine` (stop, new load, deinit), `KSPlayerVideoThumbnailExtractor`, and `KSPlayerMediaProbeProvider` use it

## Out of Scope

- The KSPlayer/FFmpeg root cause (libsmbclient is not safe across concurrent contexts)
- macOS extractors, which keep the fixed drain; macOS playback does not open SMB directly

## Verification

- `swift test --package-path Packages/VanmoCore`: 268 tests, including:
  - `testLibavformatGateExclusiveWaitsForCloseTrackedByWork`
  - `testLibavformatGateWaitsForProtocolCloseBeforeRelease`
  - `testLibavformatProtocolCloseWaitTimesOut`
  - `testLibavformatProtocolCloseTrackerHandsOffOnce`
  - `testLibavformatProtocolCloseDrainIgnoresCallerCancellation`
- Serial `./scripts/check-app-build.sh ios-simulator`, then `macos`
- `./scripts/check-architecture-guards.sh` and `./scripts/check-harness-docs.sh`
- iPhone device walks (Debug, installed with `./run_device.sh --install-only`), with USB `idevicesyslog` capture. Each time, the operator repeated the Files SMB thumbnail journey, then played and stopped SMB videos:
  - First build, which tracked `closeOperation`:
    - 8 thumbnail extractions
    - the gate waited 50–450 ms for 6 closes
    - one KSPlayer SMB load and stop
  - Final build, which tracks the queue:
    - 39 thumbnail extractions
    - the gate waited 50–1,450 ms for 9 closes
    - three KSPlayer SMB loads and stops
    - no `operation queue not found` or timeout log
  - Neither build produced a crash report after install.
  - `waitedMs` counts 50 ms polls from when the gate started waiting, not from when `shutdown()` returned.
  - Logs and crash reports stayed local and are not committed.

## Risks

- Reflection depends on KSPlayer private field names; tracked in the tech-debt tracker.
- Normal-Wi-Fi walks do not prove the degraded-Wi-Fi case. Closes of up to 1,450 ms show the old 400 ms drain was already too short on a normal network.
- A close that stalls for a long time now delays the next SMB thumbnail or playback open by up to 120 s, instead of letting it overlap and crash.

## Progress Log

- 2026-10-14: Reproduced two thumbnail-only libsmbclient crashes on device, implemented the close wait, and walked the same journey on device with no crash. After review, switched the probe to the immutable serial queue and raised the cap to 120 s, then walked the device again with no crash. VanmoCore passed 268 tests. iOS Simulator Debug passed `20261014-104612-8732`, then macOS Debug `20261014-104644-9057`. Architecture guards and harness docs checks reported 0 failures.

## Open Decisions

- None.
