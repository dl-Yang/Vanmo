# Tech Debt Tracker

This tracker contains only debt confirmed by current repository sources or recorded verification. It is not a backlog for speculative improvements.

| Date recorded | Area | Confirmed debt | Current risk | Revisit trigger |
| --- | --- | --- | --- | --- |
| 2026-08-25 | Swift concurrency | `VanmoCore` emits pre-existing Swift 6 `Sendable` warnings | A future Swift language-mode upgrade may turn warnings into errors or expose unsafe cross-actor assumptions | Before enabling Swift 6 language mode, or when touching the warned types |
| 2026-08-25 | SwiftData | The repository has no `VersionedSchema` or `SchemaMigrationPlan` | Model evolution relies on lightweight migration and container creation has no explicit versioned recovery path | Before a non-additive model change or a release containing schema changes |
| 2026-08-25 | App verification | The iOS `VanmoUITests` target and interaction CLI now exist, but ordinary iOS Debug compile and `build-for-testing` are blocked by the missing `.paused` case in the Settings `DownloadStatus` switch; physical-device signing, runner arguments, and artifact export are unverified, and critical controls have limited stable accessibility-identifier coverage | The new compile evidence layer can detect the iOS source failure, but cannot prove signed device interaction; broader iOS and macOS UI journeys still rely on manual evidence | First add and approve the missing Settings Figma design, fix the app build blocker without guessing the UI, then run and record a physical-device golden journey while expanding identifiers only for its critical controls |
| 2026-08-25 | CloudKit | Real Release-environment CloudKit behavior has no recorded evidence | Static checks and Debug fallback cannot prove account, transport, conflict, or multi-device behavior | Before claiming cloud sync production readiness or shipping a cloud-sync change |
| 2026-08-25 | Playback/build configuration | Legacy standalone FFmpeg configuration remains although current playback uses FFmpeg through KSPlayer and Swift source does not consume `FFMPEG_ENABLED` | Contributors may mistake the legacy script, bridging path, or flag for a current prerequisite | When changing player dependencies or simplifying build configuration |

## Rules

- Add an item only after evidence confirms the debt.
- Link remediation to a bounded execution plan rather than expanding unrelated work.
- Remove an item only when the fix and its required verification are recorded.
