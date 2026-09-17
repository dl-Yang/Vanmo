# Notch Download Status Bar

**Status:** Completed  
**Created:** 2026-09-17  
**Plan type:** Feature / downloads UI  
**Related product spec:** [`../../product-specs/downloads.md`](../../product-specs/downloads.md)  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

On notch iPhones without a Dynamic Island, stop placing a download bar under the notch. Fly the detail-page capsule to the leading status-bar slot, shrinking it on the way, then show a solid-blue “status-bar capsule” with a white icon and a white progress border. Hide the app status bar so the system time cannot cover that capsule.

## Scope

- Detect `hasNotchStatusBar` separately from `hasDynamicIsland`
- Capsule destination is the leading status-bar slot (`notchLandingFrame`), not `fallbackBarFrame`
- Solid-blue in-app capsule: white download / pause / complete icon, white progress border, no title or poster, no Expanded
- Hide the app status bar on notch phones so the key-window overlay is not covered
- Hero shrinks to capsule size during the flight, not after it lands
- Same `DownloadActivityPresentation` selection, completion pulse, and collapse-dismiss as fake-island Compact
- Capsule tap opens Downloads while downloading or completed; paused tap resumes
- iPhone SE / iPad keep the existing glass fallback bar
- Research the system background-task / privacy pill; hook downloads into it only if a public API exists

## Out of Scope

- Dynamic Island fake-island and widget layout changes
- SE / iPad fallback visual redesign
- macOS download capsule
- Landscape acceptance
- Raising QUALITY_SCORE without a recorded notch-device walk

## Verification

1. Physical notch iPhone via `./run_device.sh` (no Simulator walk as completion evidence)
2. Detail enqueue: capsule shrinks to the leading status-bar slot, then the solid-blue status-bar capsule stays visible because the app status bar is hidden
3. Downloads-page pause / resume / progress update the capsule border and icon
4. Capsule tap opens Downloads while downloading; paused tap resumes
5. Delete scales the capsule away
6. A Dynamic Island phone still shows Compact / Expanded
7. Operator captures screenshots or a screen recording and returns them to the agent

## Risks

- `statusBarHidden` can zero `safeAreaInsets.top`; detection uses the status-bar frame and caches a positive notch result
- Early window-not-ready detection can briefly look like SE until insets or the status-bar frame resolve
- ActivityKit on notch phones can show a lock-screen / banner Live Activity, but it cannot become the system location/microphone/hotspot pill

## Progress

- 2026-09-17: Added LibraryHome Figma frames `588:2` (downloading) and `588:9` (paused). Implemented `hasNotchStatusBar`, `DownloadNotchStatusBarHost`, notch landing, and narrowed `shouldShowFallbackBar`.
- 2026-09-17: `./scripts/check-harness-docs.sh` passed. Signed `./run_device.sh --team HYGMY7H2C5` installed and launched on physical iPhone 13 mini (`00008110-001E254A3A60401E`, iOS 26.6).
- 2026-09-17: Operator rejected liquid glass and Gaussian disks, then a frosted capsule that the system time covered, then a status-bar-level window that never revealed the landed capsule (`tem/13mini-ScreenRecording.MP4`). The closeout hides the app status bar on notch phones and keeps the solid-blue capsule in the key-window overlay. Hero size interpolates to 64×28 during the flight.
- 2026-09-17: Operator recording `tem/cmp.mp4` (about 20.5s) on the same 13 mini passed the closeout: detail enqueue flies and shrinks to the leading slot, the solid-blue capsule stays visible, pulling down the lock screen shows a Live Activity, and pause controls stay in sync with the in-app capsule and the Downloads page. Operator marked the walk passing. This recording did not re-walk delete collapse or a Dynamic Island phone.

## Decisions

- Artwork tap previously opened Downloads because there is no Expanded mode. The redesigned capsule keeps that path while downloading or completed; paused tap resumes.
- SE / iPad stay on the previous glass fallback for this plan.
- The Apple left-hand capsule in `tem/1.PNG` is the system location privacy indicator. Third-party apps cannot inject download progress into it. The feasible hook is ActivityKit on the lock screen and banner, plus an in-app recreation of the leading pill.
- Notch phones hide the app status bar while active, the same policy as island phones, so the in-app capsule is not covered by the system time.

## Outcome

Notch iPhones without a Dynamic Island hide the system status bar, fly a shrinking hero capsule to the leading status-bar slot, then show a solid-blue in-app capsule with a white icon and white progress border. Lock-screen Live Activity is requested on notch phones. Operator recording `tem/cmp.mp4` on iPhone 13 mini passed flight, landed capsule, lock-screen Live Activity, and pause sync. QUALITY_SCORE was not raised.

## Remaining

- Capsule tap → Downloads, delete collapse, and a Dynamic Island Compact/Expanded regression were not in `tem/cmp.mp4`
- The system location/microphone/hotspot privacy pill still has no third-party host API
