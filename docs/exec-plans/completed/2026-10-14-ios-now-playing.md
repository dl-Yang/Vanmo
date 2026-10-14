# iOS Now Playing

**Status:** Completed
**Related product spec:** [`../../product-specs/ios-player-controls.md`](../../product-specs/ios-player-controls.md)

## Objective

Show the playing video on the iOS lock screen and in Control Center, and let those system controls drive playback. Before this change the system card stayed on "Nothing playing" during playback.

## Scope

- iOS `NowPlayingController` publishes the title, poster when it loads, elapsed time, duration, and playback rate to `MPNowPlayingInfoCenter`.
- Remote commands: play, pause, toggle, 10-second skip forward and back, and a position scrub. Live streams disable skip and scrub.
- `PlayerViewModel` starts the card when playback starts, refreshes it on time, state, duration, rate, and seek, and clears it when playback resources stop.
- Closing the player removes only this session's command targets.

## Out of Scope

- macOS Now Playing
- Next and previous track
- Artwork for a poster URL that fails to load. The title still appears

## Verification

- Serial `./scripts/check-app-build.sh ios-simulator` (`20261014-161739-41567`), then `macos` (`20261014-161811-41702`). After the seek-hold fix, `ios-simulator` passed again (`20261014-162623-43202`)
- `./scripts/check-architecture-guards.sh` and `./scripts/check-harness-docs.sh`: 0 failures
- iPhone walk, filtered `idevicesyslog`:
  - `now playing started live=false`
  - remote `pause`, `play`, and `skipForward` (twice)
  - `now playing stopped` after the player closed
  - The operator confirmed the Control Center card showed the title, play/pause and skip worked, the lock screen showed the same card and could play and pause, and closing the player cleared the card

## Risks

- A position scrub was not used on the walked build. A follow-up keeps the target time on the card until playback catches up, so an in-flight seek is not overwritten by the previous time. That build (`20261014-162623-43202`) was not installed: the iPhone was no longer an Xcode destination (`Unable to find a destination`).
- Whether the poster appeared on the card was not recorded. The title was.

## Progress Log

- 2026-10-14: Added the iOS Now Playing session, regenerated the Xcode project, built both apps, and walked Control Center and the lock screen on iPhone.
- 2026-10-14: The review found that a remote seek could publish the old time. The card now holds the target time until playback reaches it. The iOS build passed. The phone was gone from Xcode's destinations, so this fix was not installed.

## Open Decisions

- None.
