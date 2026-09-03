# SOP: Local Observability Feedback Loop

Use this SOP to diagnose Vanmo runtime failures on iOS Simulator, an iOS
device, or macOS without introducing a remote observation pipeline.

## Read First

- [`../RELIABILITY.md`](../RELIABILITY.md)
- [`../SECURITY.md`](../SECURITY.md)
- [`apple-ui-validation-loop.md`](./apple-ui-validation-loop.md) for visible UI
  journeys

## Local Evidence Sources

- Xcode Console for an attached run or device
- Console.app for iOS device or macOS process output
- the project's existing logs
- narrowly scoped `print`, `os.Logger`, or `NSLog` output when no suitable
  project logger exists

Remote telemetry, log upload, external observability SDKs, proxy collection,
and server-side instrumentation are not the default debugging path. They
require explicit authorization and a separate security review.

## Logging Rules

- Instrument only the smallest suspected path: entry points, state changes,
  asynchronous boundaries, error branches, return values, and critical timing.
- Use a stable searchable prefix such as `[Debug][Player]`,
  `[Debug][Downloads]`, or `[Debug][CloudSync]`.
- Include only useful context: safe object identifiers, source type, sanitized
  host/path fragments, state names, task boundaries, error types, and elapsed
  time.
- Never emit passwords, tokens, cookies, authorization headers, complete
  authenticated URLs, user file contents, or private media metadata.
- Wrap temporary diagnostics in `#if DEBUG` where practical.
- Remove temporary noise after the issue is resolved. Keep only low-volume,
  structured, non-sensitive logs with ongoing maintenance value.

## Feedback Loop

Follow this exact sequence:

1. **Query:** Reproduce one bounded journey and collect the relevant local
   console lines using the stable prefix.
2. **Reason:** Correlate the events, identify the owning layer, and state the
   smallest evidence-backed failure hypothesis.
3. **Fix:** Change only the responsible path. Do not add remote collection or
   broaden the architecture to obtain evidence.
4. **Restart:** Fully restart the affected app, process, player window, or
   persisted workflow as required by the failure mode.
5. **Rerun:** Repeat the same journey with the same platform, configuration,
   source type, and relevant initial state.
6. **Verify:** Compare the failure and success evidence, check for new console
   errors, and record what passed and what remains unverified.

In short: `query -> reason -> fix -> restart -> rerun -> verify`.

## Device Evidence Handoff

For iOS device-only behavior, ask the user to reproduce on the device and
manually copy the matching non-sensitive lines from Xcode Console or
Console.app. A simulator trace is not evidence for hardware, entitlement,
background, or real CloudKit behavior that only exists on the target
device/environment. Simulator Debug is not CloudKit evidence.

## Definition of Done

- The failure and post-fix result are tied to the same repeatable journey.
- Logs are local, searchable, minimal, and non-sensitive.
- Restart and rerun evidence is recorded.
- Temporary diagnostics are removed or deliberately retained as low-noise
  Debug logs.
- New durable diagnostic or recovery expectations are reflected in
  `docs/RELIABILITY.md`.
