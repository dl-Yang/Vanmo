# 字幕选择后无法显示

## 状态：已修复

## 现象

播放视频时，字幕轨可以正常被发现和选择（UI 中能看到字幕轨列表），但选择字幕后画面上不显示任何字幕内容。AVFoundation 引擎和 KSPlayer 引擎均受影响。

## 根因分析

经过多轮诊断（Mirror 反射检查内部队列状态），最终定位到**两个根本原因**：

### 1. 字幕渲染管线缺失

`AVPlayerLayer` 和 `KSMEPlayer.view` 均不自带字幕渲染能力。项目中虽然存在 `SubtitleOverlayView`，但从未被接入播放器视图层级，也没有从引擎获取字幕文本/图片的数据通道。

### 2. 图片字幕（PGS）未被处理

通过 Mirror 反射诊断 `SyncPlayerItemTrack<SubtitleFrame>` 的内部状态，发现：

- **`state=decoding`**：解码管线正常运行 ✓
- **`decoders=1`**：解码器已创建 ✓
- **`frameCount > 0`，`head/tail` 持续推进**：帧确实在被解码和入队 ✓
- **`partsCount=1, hasImage=true, hasText=false`**：匹配到的字幕帧是**图片**而非文本

关键发现：该视频所有 5 条字幕轨（chs&eng, cht&eng, chs, cht, eng）均为 **PGS 图片字幕**，而非预期的 ASS/SRT 文本字幕。判定依据是 `FFmpegAssetTrack.isEnabled` 初始值为 `false`——KSPlayer 对文本字幕的 `isEnabled` setter 始终将 `stream.discard` 设为 `AVDISCARD_DEFAULT`（getter 恒返回 `true`），只有图片字幕才会真正为 `false`。

### 3. `CircularBuffer.search` 消费性导致字幕闪现

KSPlayer 的 `CircularBuffer.search` 方法是**消费性**的——找到匹配项后立即从队列移除并推进 `headIndex`。这意味着同一字幕帧只会被 `search(for:)` 返回一次（0.5s 的一个 poll 周期），后续 poll 再也找不到。一条本该显示 3 秒的字幕只会闪现 0.5 秒。

KSPlayer 自身的 `SubtitleModel` 通过缓存上次找到的 `parts` 来解决此问题：若 `search` 返回空，则检查缓存的 parts 是否仍在有效时间范围内。

## 修复方案

### A. 建立字幕数据通道

在 `PlayerEngine` 协议中新增 `subtitleContentPublisher`，引入 `SubtitleContent` 结构同时承载文本和图片：

```swift
struct SubtitleContent: Equatable {
    var text: String?
    var image: UIImage?
}
```

- **AVPlayerEngine**：通过 `AVPlayerItemLegibleOutput` 捕获字幕文本，包装为 `SubtitleContent(text:)` 发布
- **KSPlayerEngine**：通过 `KSSubtitleProtocol.search(for:)` 查询字幕帧，提取 `text` 和 `image`

### B. 实现 parts 缓存机制

仿照 KSPlayer 的 `SubtitleModel` 模式：

```swift
let newParts = searchable.search(for: time)
if !newParts.isEmpty {
    cachedSubtitleParts = newParts
} else {
    cachedSubtitleParts = cachedSubtitleParts.filter { $0 == time }
}
```

- `search` 找到新 parts → 更新缓存
- `search` 返回空 → 检查缓存的 parts 是否仍在有效时间范围（`start <= time <= end`）
- 缓存过期 → 清空，字幕消失

### C. SubtitleOverlayView 支持图片渲染

- 文本字幕：`Text(text)` + 半透明背景
- 图片字幕：`Image(uiImage:)` + `scaledToFit`
- 叠加到 `PlayerView` 的视频层之上

## 诊断过程

1. **初步诊断**：添加 `[KSEngine]` 日志，发现 `search(for:)` 始终返回 `partsCount=0`
2. **深入检查**：发现 `FFmpegAssetTrack.isEnabled` 对文本字幕 setter 恒设 `AVDISCARD_DEFAULT`，怀疑是图片字幕
3. **Mirror 反射诊断**：绕过 KSPlayer internal 访问限制，直接反射检查 `SyncPlayerItemTrack` 内部状态：
   - `state`：确认解码管线状态
   - `outputRenderQueue.headIndex/tailIndex`：确认帧确实在被解码入队
   - `decoderMap.count`：确认解码器已创建
4. **最终确认**：`partsCount=1, hasImage=true` 证实是图片字幕；`head` 持续推进证实消费性搜索在消耗帧

## 涉及文件

- `Vanmo/Core/Player/PlayerEngine.swift` — 新增 `SubtitleContent` 结构，协议改为 `subtitleContentPublisher`
- `Vanmo/Core/Player/KSPlayerEngine.swift` — parts 缓存机制 + 图片字幕支持
- `Vanmo/Core/Subtitle/SubtitleOverlayView.swift` — 支持文本和图片两种渲染模式
- `Vanmo/Features/Player/ViewModels/PlayerViewModel.swift` — `currentSubtitleContent` 替代 `currentSubtitleText`
- `Vanmo/Features/Player/Views/PlayerView.swift` — 传递 `SubtitleContent` 给 overlay

## 关联 Issue

- [字幕语种切换无效](subtitle-language-setting-not-working.md)（已修复，前置问题）
