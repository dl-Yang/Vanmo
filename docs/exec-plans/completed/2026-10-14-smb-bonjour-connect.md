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
- The 2026-10-12 baseline remains 2217–2254 ms to `ready` on this Mac's share, against 47–67 ms for the same local files

## Risks

- A server that rejects the IP and accepts only `hostname.local` now pays for the failed IP attempts before the Bonjour wait. That was the fallback this lookup exists for.
- The success path was not timed again, so the 2.2 s figure is not yet shown to be gone.

## Progress Log

- 2026-10-14: Moved the Bonjour lookup behind a failed direct login. Package tests passed. The Mac share was not played again.

## Open Decisions

- None.
