# 115 Drive Connection Validation

**Status:** Completed  
**Created:** 2026-08-28  
**Completed:** 2026-10-21  
**Plan type:** Validation only  
**Related reliability authority:** [`../../RELIABILITY.md`](../../RELIABILITY.md)

## Objective

Record that the 115 Drive entry remains an official-cloud placeholder on both Vanmo iOS and VanmoMac. A pass means save stays disabled and `UnsupportedOfficialCloudDriveService` is not used as a working source.

## Scope

- Dual-platform Files add-form confirmation under the shared rules in [`../active/index.md`](../active/index.md).
- Expected UI: official-access caption, save disabled (`isOfficialCloudDrive`).
- Expected factory behavior if a connection were created: `connect`, `listDirectory`, and `streamURL` throw `unsupportedProtocol`.

## Out of Scope

- Implementing 115 Open Platform login
- Unofficial APIs
- Expanding `UnsupportedOfficialCloudDriveService` from this plan

## Prerequisites

- Debug Vanmo on iOS and VanmoMac

## Verification

1. Launch iOS Vanmo with `./run_device.sh --simulator` or a signed device. Open Files and choose 115 Drive.
2. Confirm the official-access caption and that Save is disabled.
3. Repeat the form observation on VanmoMac with `./run_device.sh --macos`.
4. Record that no listing or play was attempted because save is disabled.

The plan completes only when both platforms show the placeholder form.

## Log prefix

None expected. Connect is not reachable from the current save path.

## Risks

- Editing a leftover historical row could still hit `unsupportedProtocol`; that is not a pass for a working 115 client. The iOS Files list and the macOS sidebar showed no saved 115 row before the walk, so editing a historical row was not exercised.

## Static code path

The walked behavior matches the code, checked before and after the runs:

- `RemoteServiceFactory.create(for: .drive115)` returns `UnsupportedOfficialCloudDriveService`, whose `connect`, `listDirectory`, `streamURL`, and `download` all throw `NetworkError.unsupportedProtocol` ([`ServiceFactory.swift`](../../../Packages/VanmoCore/Sources/VanmoCore/Network/ServiceFactory.swift)).
- `ConnectionType.isOfficialCloudDrive` includes `.drive115` ([`ConnectionModels.swift`](../../../Packages/VanmoCore/Sources/VanmoCore/Models/ConnectionModels.swift)).
- iOS `AddConnectionView.isValid` returns `false` for every official-cloud type before the host check, and the Save toolbar button is `.disabled(!isValid || isBlocking)`; `connectionTypeCaption` supplies the 115 placeholder caption ([`AddConnectionView.swift`](../../../Vanmo/Features/Browser/Views/AddConnectionView.swift)).
- macOS `MacAddConnectionView` renders `officialCloudDriveForm` (name plus the placeholder description) instead of the host form, and its footer Save is `.disabled(!isValid || viewModel.isLoading)` with the same `isValid` early return ([`MacAddConnectionView.swift`](../../../VanmoMac/UI/Browser/Views/MacAddConnectionView.swift)).

## Environment

| Item | Recorded value |
| --- | --- |
| Date | 2026-10-21 |
| iOS | iPhone 17 Pro simulator (`0811807F-3DD6-4DF5-B5B3-C734ABC76F1F`), `Vanmo` Debug built into `build/DerivedData`, bundle `com.vanmo.app` |
| macOS | `Vanmo-macOS` Debug built and launched by `./run_device.sh --macos`, bundle `com.vanmo.app.mac` |
| Stack | Xcode 26.0.1 (17A400), iOS 26.0 simulator runtime, macOS 26.0 |
| Pre-existing data | Two saved connections in the iOS simulator (Emby `Reno`, SMB `Mac`); macOS sidebar showed its own saved connections. No 115 row existed on either platform. |

The first Debug build of this run failed with `ld: write() failed, errno=28` because the volume had 242 MiB free. The gitignored, regenerable `build/app-build-evidence/DerivedData` and `build/app-build-evidence/SourcePackages` caches (8.8 GB) were removed; the `build/app-build-evidence/runs` evidence records were kept. Both platforms then built and launched.

The closeout `./init.sh` baseline passed all three stages with 0 failures (279 `VanmoCore` tests, the CloudKit/multiplatform static check, and the Harness documentation check).

## Acceptance Record

| Step | iOS Simulator | VanmoMac |
| --- | --- | --- |
| 1. Open Files and choose 115 Drive | Pass: `文件` tab → `files.addConnection` → protocol menu → `115 网盘` | Pass: `连接` → add-connection sheet → type list → `115 网盘` |
| 2. Official-access caption | Pass: `115 网盘需通过开放平台入驻和应用审核；本入口仅保留合规接入提示，当前不使用非官方接口。` | Pass: `115 网盘需通过开放平台入驻和应用审核；当前仅保留合规接入提示。` |
| 3. Save disabled | Pass: accessibility element reports `enabled=false` with trait `NotEnabled` | Pass: operator clicked `保存`; the sheet stayed open with no error or connection dialog |
| 4. Listing / play | Not attempted; Save is unreachable | Not attempted; Save is unreachable |
| 5. Connection list after the walk | Unchanged: Emby `Reno` and SMB `Mac` only | Not re-read after the click; the sheet never closed, so no save path ran |

This is not a working 115 client. The disabled Save control is the documented official-cloud placeholder gate.

## Evidence captures

`build/` is gitignored. Captures from this run are under `build/drive115-validation/`:

- iOS: `ios-01-home.png`, `ios-04-protocol-menu.png`, `ios-05-menu-try2.png`, `ios-06-115-form.png`, `ios-07-after-cancel.png`, plus the matching `ios-0*-ax.json` accessibility dumps (home, Files, add form, protocol menu, 115 form).
- macOS: `mac-02-front.png` (launched app), `mac-03-115-form.png` (form opened by the operator), `mac-04-after-save-click.png` (form still open after clicking Save).

iOS Save element read with `idb ui describe-point` at the toolbar button:

```
{"AXLabel":"保存","type":"Button","enabled":false,"traits":["NotEnabled","Scrollable","Button"],"frame":{"x":332,"y":82,"width":50,"height":36}}
```

The macOS Save control uses the custom `MacPrimaryActionButtonStyle`, which keeps the accent-blue fill when disabled, so the dimmed-pixel check is not a valid signal there; the accepted evidence is the no-op click plus the `isValid` early return above. The iOS Save element was also absent from `idb ui describe-all` (sheet navigation-bar items are not listed) and was read through `describe-point` instead.

The iOS half was agent-operated (`idb ui tap` / `idb ui describe-*` plus `xcrun simctl io … screenshot`). On macOS the agent had no Accessibility or Apple Events permission for UI scripting, so the operator opened the sheet and clicked Save while the agent captured the screen and read the rendered text through a local Vision OCR pass. No screen recording was taken.

## Progress

- **2026-08-28:** Validation plan created. No dual-platform placeholder confirmation is recorded.
- **2026-10-21:** iOS Simulator walk completed. `./run_device.sh --simulator` could not build until the regenerable evidence caches were removed (disk full); after that the Debug build succeeded, `com.vanmo.app` installed and launched, and the Files → add-connection → protocol → `115 网盘` path showed the placeholder caption with the accessibility tree reporting `保存` as `enabled=false`. The sheet was cancelled and the connection list stayed at two rows.
- **2026-10-21:** VanmoMac walk completed. `./run_device.sh --macos` built and launched `com.vanmo.app.mac`. The operator opened the add-connection sheet and selected `115 网盘`; the form showed only 名称 plus the placeholder caption, and clicking `保存` did nothing. No listing or play was attempted on either platform.
- **2026-10-21:** Closed the plan. Both platforms show the placeholder form, and no 115 connect, listing, or stream call was reachable.

## Open Decisions

None.

## Follow-ups

- Real 115 Open Platform login stays unimplemented and out of scope here. It needs an approved 115 Open Platform application (client ID/secret kept in the existing OAuth credential storage) and the QR-code authorization flow before a real connect-and-list plan can exist.
- A future real 115 implementation should archive this placeholder record and open a new real-source validation plan.