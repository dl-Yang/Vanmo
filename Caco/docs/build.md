# Build Notes

## Requirements

- DevEco Studio with HarmonyOS NEXT SDK.
- ArkTS support enabled.
- A HarmonyOS phone or tablet profile for device validation.

## Open Project

Open the `Caco/` directory in DevEco Studio. The main module is `entry`.

## Configuration Checklist

- Confirm `bundleName` in `AppScope/app.json5`.
- Configure signing in `build-profile.json5`.
- Verify `entry/src/main/module.json5` permissions match the enabled protocols.
- Replace placeholder app icon resources before release packaging.

## First Build Target

The first build target is the app shell only:

- `EntryAbility`
- `pages/Index`
- Library, Files, Search and Settings tabs
- Shared theme and placeholder components

Player, RelationalStore, HUKS, WebDAV parser and SMB support are staged behind their PoC docs and should be enabled incrementally.
