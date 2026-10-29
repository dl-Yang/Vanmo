# Active Execution Plans

Active plans include not-started, in-progress, or blocked work that still requires evidence.

This index also holds the shared dual-platform acceptance rules for remote-connection validation plans. Completed connection plans under `../completed/` cite these rules.

## Shared Dual-Platform Acceptance

These rules apply to every remote-connection validation plan. A validation-only plan does not authorize implementation expansion. If a run exposes a defect, record it and open a separately scoped fix.

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device, and VanmoMac with `./run_device.sh --macos`.
2. Open Files and add the named connection type. Implemented protocols save or complete OAuth login. Official-cloud placeholders stop at the disabled Save control and the official-access caption; do not require a saved connection or listing.
3. Confirm connect using that plan's log prefix. A compile, launch, or unit test is not a real connection.
4. Confirm the first listing shows readable directories, files, or media items. Placeholder protocols instead confirm the documented empty list or unsupported stream. Official-cloud placeholders do not reach listing.
5. For implemented protocols, play one listed video and record the engine path. iOS often uses a direct URL or KSPlayer. macOS remote HTTP should use the localhost prefetch proxy.
6. Copy sanitized Console lines. Do not record passwords, tokens, complete authenticated URLs, or private media titles.
7. iOS evidence does not prove macOS. Both platforms must pass before a plan can move to `../completed/`.

Out of default scope for a validation plan: downloads, library scan persistence, playback-progress sync, CloudKit, and Figma changes.

## Current Plans

### Implementation, blocked on 115 Open Platform credentials

- [`2026-10-21-drive115-open-platform-integration.md`](2026-10-21-drive115-open-platform-integration.md) — **Blocked.** Replaces the 115 placeholder with official QR authorization, listing, stream, and download; needs an approved 115 Open Platform application

## Rules

- Keep one file per bounded plan.
- Update status, progress, risks, and decisions from factual evidence.
- Do not expand implementation from a validation-only plan.
- Move a plan to `../completed/` only when its required evidence is recorded.
