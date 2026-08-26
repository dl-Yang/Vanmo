# Active Execution Plans

Active plans include not-started, in-progress, or blocked work that still requires evidence.

## Current Plans

- [`2026-08-26-debug-build-evidence-layer.md`](2026-08-26-debug-build-evidence-layer.md) — **Implemented.** Layered Debug compile evidence exists. The later iOS golden-journey work repaired the `.paused` compile blocker; this plan's first recorded matrix remains the historical red iOS result.
- [`2026-08-25-mac-download-real-source-validation.md`](2026-08-25-mac-download-real-source-validation.md) — **Not started.** Manually validate existing macOS download recovery and detail navigation with a real SMB or HTTP source.

## Rules

- Keep one file per bounded plan.
- Update status, progress, risks, and decisions from factual evidence.
- Do not expand implementation from a validation-only plan.
- Move a plan to `../completed/` only when its required evidence is recorded.
