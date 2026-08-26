# Product Sense

This document records durable Vanmo product judgment that cannot be inferred safely from code alone.

## Product Core

- **Primary user:** A person who owns or accesses video across local files, network shares, cloud drives, IPTV, or media servers and wants one coherent native player.
- **Job to be done:** Find, organize, download, and play personal video reliably across iPhone, iPad, and Mac while preserving source context and playback state.
- **Main frustration to remove:** Fragile media workflows caused by expiring URLs, disconnected sources, inconsistent playback support, lost progress, unclear background work, or platform-inappropriate UI.
- **Acceptance bar:** Critical behavior must be demonstrated on the relevant platform and source type. Code presence, a static check, or a shared-package test alone is not end-to-end product evidence.

## Product Priorities

1. Preserve access to the user's media and avoid destructive or duplicative actions.
2. Make playback, downloads, scanning, and synchronization states legible and recoverable.
3. Prefer a dependable path for supported sources over a broad list of nominally available integrations.
4. Respect native iOS and macOS interaction models instead of forcing identical presentation.
5. Keep credentials and private media data local to the narrowest appropriate boundary.

## Product Rules

- Every visible remote connection type must be described according to verified capability, not menu presence.
- A recoverable failure needs a clear error state and a next action; silent stalls are unacceptable.
- Long-running operations must expose enough state to distinguish queued, active, paused, completed, and failed work where those states apply.
- Playback and download flows must retain the identity of the originating media item so the user can return to the correct movie, show, or episode.
- Sync must not imply that the full media catalog or credentials are uploaded; Vanmo's cloud scope is deliberately narrow.
- Ambiguous behavior is a specification gap, not permission to guess.

## Evidence Discipline

- Automated `VanmoCore` tests establish shared-logic evidence only.
- Static checks establish configuration and boundary evidence only.
- An app build establishes compilation evidence, not user-flow acceptance.
- Device, simulator, macOS runtime, real remote source, and Release CloudKit claims require their corresponding manual or environment-specific evidence.
- Product specs must label unverified acceptance paths explicitly.

## No-Go Patterns

- hidden destructive actions or duplicate queue entries
- credentials, tokens, or complete authenticated URLs in storage not designed for secrets, logs, screenshots, or evidence
- indefinite loading without an error or retry path
- treating placeholder protocol support as production-ready
- changing user-visible behavior without updating its product spec and verification path
