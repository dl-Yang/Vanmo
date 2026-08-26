# Tech Debt Tracker

This tracker contains only debt confirmed by current repository sources or recorded verification. It is not a backlog for speculative improvements.

| Date recorded | Area | Confirmed debt | Current risk | Revisit trigger |
| --- | --- | --- | --- | --- |
| 2026-08-25 | Swift concurrency | `VanmoCore` emits pre-existing Swift 6 `Sendable` warnings | A future Swift language-mode upgrade may turn warnings into errors or expose unsafe cross-actor assumptions | Before enabling Swift 6 language mode, or when touching the warned types |
| 2026-08-25 | SwiftData | The repository has no `VersionedSchema` or `SchemaMigrationPlan` | Model evolution relies on lightweight migration and container creation has no explicit versioned recovery path | Before a non-additive model change or a release containing schema changes |
| 2026-08-25 | App verification | Simulator XCUITest now records a tab-navigation journey and iOS Debug compile is unblocked. A 2026-08-26 macOS HTTP-via-Emby download acceptance run is recorded. Physical-device signing, runner-argument delivery, SMB download recovery, and broader iOS/macOS player journeys remain unverified; accessibility identifiers still cover only the golden-journey controls | Agents can prove compile plus one Simulator navigation path and one macOS HTTP download run, but cannot treat those as device, Figma, SMB, or iOS product-journey evidence | Record a signed physical-device XCUITest when a trusted device is available; expand identifiers only for the next bounded journey |
| 2026-08-25 | CloudKit | Real Release-environment CloudKit behavior has no recorded evidence | Static checks and Debug fallback cannot prove account, transport, conflict, or multi-device behavior | Before claiming cloud sync production readiness or shipping a cloud-sync change |
| 2026-08-25 | Playback/build configuration | Legacy standalone FFmpeg configuration remains although current playback uses FFmpeg through KSPlayer and Swift source does not consume `FFMPEG_ENABLED` | Contributors may mistake the legacy script, bridging path, or flag for a current prerequisite | When changing player dependencies or simplifying build configuration |

## Rules

- Add an item only after evidence confirms the debt.
- Link remediation to a bounded execution plan rather than expanding unrelated work.
- Remove an item only when the fix and its required verification are recorded.
