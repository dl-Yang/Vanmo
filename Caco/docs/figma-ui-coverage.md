# Figma UI Coverage

Figma remains the source of truth for all HarmonyOS UI work.

| Screen | Figma node | HarmonyOS file | Status |
| --- | --- | --- | --- |
| LibraryHome | `295:6` | `entry/src/main/ets/pages/library/LibraryHomePage.ets` | Structure created, visual parity pending screenshot comparison |
| MediaDetail | `203:2` | `entry/src/main/ets/pages/MediaDetail.ets` | Structure created, visual parity pending screenshot comparison |
| File | `317:80` | `entry/src/main/ets/pages/files/FilePage.ets` | Structure created, visual parity pending screenshot comparison |
| Favorites | `322:192` | `entry/src/main/ets/pages/library/FavoritesPage.ets` | Structure created, visual parity pending screenshot comparison |
| Search | Missing | `entry/src/main/ets/pages/search/SearchPage.ets` | Needs Figma design before final styling |
| Settings | Missing | `entry/src/main/ets/pages/settings/SettingsPage.ets` | Needs Figma design before final styling |
| Player | Missing | `entry/src/main/ets/pages/Player.ets` | Needs Figma design before final styling |
| Connection form | Missing | Not started | Needs Figma design |
| Empty/loading/error states | Missing | Shared placeholders created | Needs Figma design |

## Rule

ArkUI pages may use neutral placeholders for migration scaffolding, but final UI acceptance requires Figma screenshots and token-by-token comparison for layout, spacing, typography, color, radius, shadow, icons and interaction states.
