# SOP: Apple UI Validation Loop

Use this SOP for Vanmo iOS or macOS UI work. It replaces browser-specific
Chrome/DOM validation with Figma and Apple-platform runtime evidence.

## Read First

- [`../FRONTEND.md`](../FRONTEND.md)
- [`../RELIABILITY.md`](../RELIABILITY.md)
- [`../references/design-system-reference-llms.txt`](../references/design-system-reference-llms.txt)
- [`local-observability-feedback-loop.md`](./local-observability-feedback-loop.md)

## Required Inputs

- the correct platform-specific Figma frame or component
- a reproducible user journey and observable success criteria
- the matching runtime: iOS Simulator, iOS device, or native macOS
- a way to capture screenshots, accessibility state, and local console output

If the required screen or state does not exist in Figma, design it there before
implementation. Do not use the iOS frame as the macOS authority or vice versa.

## iOS CLI Backends

- Physical-device commands use XCUITest through `./scripts/ios-ui.sh device ...`.
  They can capture a screenshot or flat JSON accessibility tree and perform one
  identifier/exact-label tap, type, swipe, wait, or assert action per run.
- Simulator commands use `simctl` through `./scripts/ios-ui.sh simulator ...`.
  They support screenshot, launch, and terminate only; they do not provide
  selector inspection or interaction.
- Every physical-device command retains its result bundle, logs, attachment
  export diagnostics, and exported attachments under `build/ui-cli/runs/`.
  Copy only sanitized requested outputs into review evidence.

## Validation Loop

1. Define one bounded journey, platform, configuration, device or window size,
   initial state, and success criteria.
2. Capture **BEFORE** evidence:
   - the relevant Figma frame
   - a runtime screenshot; on iOS use `./scripts/ios-ui.sh device screenshot`
     or `./scripts/ios-ui.sh simulator screenshot` when that backend matches
     the validation scope
   - the visible state and navigation/window context
   - accessibility labels, values, traits, focus/reading order, and text-scale
     observations relevant to the change; a physical-device tree may be
     captured with `./scripts/ios-ui.sh device tree`
   - matching local console output when behavior is stateful or failing
3. Exercise exactly one journey. Cover the relevant empty, loading, success,
   error, and retry/recovery state rather than inferring them from code.
4. Compare runtime output with Figma and platform conventions. On iOS, inspect
   compact and relevant regular-width layouts, navigation, full-screen player
   presentation, touch targets, Dynamic Type, and lifecycle behavior. On macOS,
   inspect sidebar/detail routing, independent windows, activation, keyboard
   focus and shortcuts, pointer behavior, and cleanup on close.
5. Fix the smallest responsible component or state owner.
6. Rebuild or restart through the relevant command:

   ```bash
   ./run_device.sh --simulator
   ./run_device.sh
   ./run_device.sh --macos
   ```

7. Rerun the **same journey** from the same initial conditions.
8. Capture **AFTER** evidence with the same screenshot framing and inspection
   criteria, using the same `ios-ui.sh` backend when it was used for BEFORE.
   Confirm that the intended change is visible, accessibility remains usable,
   and unexpected console errors are absent or understood.
9. Repeat until the defined journey is clean. Record only the platforms,
   states, and environments actually inspected.

## Device-Only Evidence

Behavior that depends on a physical iOS device, hardware, signing,
security-scoped access, background execution, or a Release entitlement requires
recorded physical-device evidence. Use `./scripts/ios-ui.sh device ...` for the
bounded actions it supports, retain the run artifacts, and ask the user to
complete any unsupported journey steps. Matching sanitized logs must still be
copied manually from Xcode Console or Console.app.

Simulator screenshots, a successful build, Swift package tests, and code
inspection do not replace device-only evidence. Debug also cannot prove real
CloudKit behavior because Vanmo enables CloudKit only for Release.

## Clean Criteria

- Runtime output matches the correct Figma source within the inspected state.
- The same journey passes after restart and rerun.
- Required states, text scaling, controls, accessibility, focus, and
  platform-specific navigation/window behavior were inspected.
- BEFORE and AFTER evidence use comparable conditions.
- No unrun platform or state is described as verified.

When a validated journey becomes durable acceptance, link its evidence from the
relevant product spec or execution plan and update `docs/RELIABILITY.md` only
with facts actually observed.
