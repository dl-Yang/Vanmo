# SMB Bonjour Connect

**Status:** Completed
**Related product spec:** [`../../product-specs/index.md`](../../product-specs/index.md)

## Objective

Stop a successful SMB login from waiting out the Bonjour lookup. macOS prefetch playback of clips from this Mac's own share reached `ready` in a constant 2217–2254 ms. `SMBService.connect` awaited `SMBBonjourHostLookup` for up to 2 seconds before the first login attempt, including when the IP address would have worked.

## Scope

- `SMBService.connect` logs in with the synchronous host list first (`connectionHosts`: the given host, plus reverse DNS for an IPv4 address).
- The `_smb._tcp` Bonjour name is resolved and tried only after those hosts fail.
- The file's debug `print` now goes through `VanmoLogger`.

## Out of Scope

- A new timing run on the Mac file-sharing share. That re-measure stays in the tech-debt tracker.
- iOS direct `smb://` playback, which uses libsmbclient rather than `SMBService`

## Verification

- `swift test --package-path Packages/VanmoCore`: 273 tests, 0 failures
- Serial `./scripts/check-app-build.sh ios-simulator` (`20261014-173853-47456`), then `macos` (`20261014-173918-47578`)
- The 2026-10-12 baseline was 2217–2254 ms to `ready` on this Mac's share `yinguSMB`, against 47–67 ms for the same local files
- 2026-10-15 re-measure on the same share, file `J.mp4`, three cold macOS prefetch opens: `ready` 686 ms, 208 ms, and 209 ms. `firstFrame` was 2687 ms, 1218 ms, and 1209 ms. The 2026-10-12 `firstFrame` range was 3718–3754 ms. No `connect bonjour fallback` line was logged

## Risks

- A server that rejects the IP and accepts only `hostname.local` now pays for the failed IP attempts before the Bonjour wait. That was the fallback this lookup exists for.
- The first of the three re-measure opens was slower (`ready` 686 ms) than the next two (208–209 ms). All three are well under the old 2.2 s.

## Progress Log

- 2026-10-14: Moved the Bonjour lookup behind a failed direct login. Package tests passed. The Mac share was not played again.
- 2026-10-15: Played `J.mp4` from this Mac's `yinguSMB` share through Vanmo-macOS prefetch three times. `ready` was 686 ms, then 208 ms and 209 ms. Debug browse enters a share with `navigateToDirectory`, because `openDirectory` returns immediately once browsing has started. `./scripts/check-app-build.sh macos` passed (`20261015-161945-86256`).

## Open Decisions

- None.
