# 设置外观不生效

## 状态：已修复

## 现象

- 设置页里可以选择 `跟随系统 / 浅色 / 深色`
- 但实际界面始终是深色，切换后没有变化，也无法跟随系统主题

## 根因

1. `VanmoApp` 在根视图强制写死了 `.preferredColorScheme(.dark)`，覆盖了所有后续设置
2. 外观设置默认值为 `.dark`，即使用户未主动选择，也会优先落入深色

## 修复

- 在 `VanmoApp` 读取 `@AppStorage("appearance.theme")`，并将根视图改为：
  - `.preferredColorScheme(appearance.colorScheme)`
- 将设置默认值与“重置设置”目标统一改为 `.system`（跟随系统）

## 涉及文件

- `Vanmo/App/VanmoApp.swift`
- `Vanmo/Features/Settings/ViewModels/SettingsViewModel.swift`
