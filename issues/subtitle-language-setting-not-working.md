# 字幕语种切换无效

## 状态：已修复

## 现象

设置页中可以切换“字幕首选语言”，但实际播放时并不会按该语言自动选择字幕轨道，看起来设置无效。

## 根因

`subtitle.preferredLanguage` 仅在设置页被写入 `AppStorage`，播放器加载媒体后没有读取该设置并执行字幕轨道选择逻辑。

## 修复

在 `PlayerViewModel` 接入首选字幕语言自动选择：

- 读取设置项：
  - `@AppStorage("subtitle.autoLoad")`
  - `@AppStorage("subtitle.preferredLanguage")`
- 在播放器 `onAppear()` 中拿到字幕轨后，执行 `applyPreferredSubtitleIfNeeded()`
- 规则：
  - 若关闭“自动加载字幕”，则自动关闭字幕轨
  - 若开启自动加载，则按首选语言匹配字幕轨并自动选中
  - 匹配支持常见别名（如 `zh/zho/chi/chs/cht`、`en/eng`、`ja/jpn`、`ko/kor`）及标题兜底匹配

## 涉及文件

- `Vanmo/Features/Player/ViewModels/PlayerViewModel.swift`
