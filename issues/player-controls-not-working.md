# 播放器倍速调整与画面适配点击不生效

## 操作

在播放器界面点击顶栏右侧的倍速调整按钮（如 "1.0x"）或画面适配按钮（适应/填充/拉伸），选择选项后功能不生效。

## 问题现象

1. **倍速按钮和画面适配按钮点击无反应** — 点击后没有弹出菜单或弹出后不稳定
2. **控制台报错** — `Called -[UIContextMenuInteraction updateVisibleMenuWithBlock:]` 和 `Adding '_UIReparentingView' as a subview of UIHostingController.view is not supported`
3. **倍速 UI 更新但播放速度不变** — 选择 2.0x 后按钮显示 "2.0x"，但视频仍以原速播放
4. **双击暂停/播放失效** — 双击视频区域无法触发暂停/播放

## 根因分析

### Bug 1：手势层（gestureLayer）挡住控件点击

`PlayerView` 的 ZStack 层级为：

```
ZStack {
    Color.black               // 背景
    videoLayer                 // UIViewRepresentable (AVPlayerLayer / MTKView)
    gestureLayer               // 全屏手势区域（拖拽、点击、长按）
    controlsOverlay            // 控件层（按钮、菜单）
    feedbackOverlays           // 反馈浮层
}
```

`gestureLayer` 覆盖全屏并注册了多个手势（`DragGesture`、`onTapGesture`、`LongPressGesture`），即使 `controlsOverlay` 在 ZStack 中位于其上方，SwiftUI 的手势解析仍会让底层手势干扰上层 `Menu` 组件的点击识别。

### Bug 2：SwiftUI Menu 与 UIViewRepresentable 冲突

SwiftUI 的 `Menu` 组件内部使用 UIKit 的 `UIContextMenuInteraction`，它会创建 `_UIReparentingView` 并尝试插入到 `UIHostingController.view`。当同一视图层级中存在 `UIViewRepresentable`（`AVPlayerVideoLayer` 的 `AVPlayerLayer` 和 `MetalVideoLayer` 的 `MTKView`）时，UIKit 的视图层级管理与 SwiftUI 冲突，触发报错并导致菜单功能异常。

### Bug 3：单击/双击手势顺序错误

```swift
// 错误顺序：单击先声明，双击永远无法触发
.onTapGesture { viewModel.toggleControls() }           // count: 1
.onTapGesture(count: 2) { viewModel.togglePlayPause() } // count: 2
```

SwiftUI 中 `.onTapGesture`（count: 1）在 `.onTapGesture(count: 2)` 之前声明时，单击会立即触发，不会等待可能的第二次点击，导致双击处理器永远无法被调用。

### Bug 4：FFmpegPlayerEngine 的 playbackRate 是空属性

```swift
// FFmpegPlayerEngine.swift
var playbackRate: Float = 1.0  // 没有 didSet，设置后对播放完全无影响
```

`FFmpegPlayerEngine` 的 `playbackRate` 是一个纯存储属性，没有 `didSet` 将倍速传递给音频播放管线。`AudioRenderer` 中 `AVAudioEngine` 的音频图谱也没有接入变速节点（`AVAudioUnitTimePitch`），无法改变播放速率。

### Bug 5：AVPlayerEngine 缓冲恢复后不恢复倍速

```swift
// 缓冲恢复观察器：只发了状态，没恢复 player.rate
if isReady, self?.state == .buffering {
    self?.stateSubject.send(.playing)  // 漏了 player?.rate = playbackRate
}
```

网络卡顿导致缓冲时，`AVPlayer` 的 `rate` 降为 0。缓冲恢复后只发送了 `.playing` 状态但没有恢复 `player.rate`，导致倍速在网络波动后被重置为 1.0x。

## 修复方案

### 修复 1：控件可见时禁用手势层

在 `gestureLayer` 上添加 `.allowsHitTesting(!viewModel.controlsVisible)`，当控件可见时彻底禁用手势层的触摸接收，确保所有点击事件都由控件层处理：

```swift
gestureLayer
    .allowsHitTesting(!viewModel.controlsVisible)
```

### 修复 2：用纯 SwiftUI 浮动面板替换 Menu

移除 SwiftUI `Menu` 组件（消除 `UIContextMenuInteraction` 冲突），改用 `Button` + `@State` 控制的自定义浮动选择面板：

```swift
@State private var showSpeedPicker = false
@State private var showScaleModePicker = false

// 倍速按钮：Button 替代 Menu
Button {
    withAnimation(.easeInOut(duration: 0.2)) {
        showSpeedPicker.toggle()
        showScaleModePicker = false
    }
} label: {
    Text("\(viewModel.config.playbackRate, specifier: "%.1f")x")
        // ...styling...
}
```

自定义浮动面板使用 `.ultraThinMaterial` 背景 + 圆角，定位在右上角按钮下方。关闭逻辑：
- 点击面板外部 → 透明遮罩层 `onTapGesture` 关闭
- 选择选项后 → 自动关闭
- 控件自动隐藏时 → `.onChange(of: controlsVisible)` 同步关闭
- 打开一个面板时 → 自动关闭另一个

### 修复 3：修正单击/双击手势顺序

将高 count 的手势声明在前，SwiftUI 会先等待双击判定，超时后才触发单击：

```swift
// 正确顺序：双击先声明
.onTapGesture(count: 2) { viewModel.togglePlayPause() }
.onTapGesture { viewModel.toggleControls() }
```

### 修复 4：控制层背景添加点击关闭

在 `Color.black.opacity(0.3)` 背景上添加 `onTapGesture`，让空白区域点击可以关闭控件（替代被禁用的手势层）：

```swift
Color.black.opacity(0.3)
    .ignoresSafeArea()
    .onTapGesture { viewModel.toggleControls() }
```

### 修复 5：AudioRenderer 插入 AVAudioUnitTimePitch 变速节点

在 `AVAudioEngine` 音频图谱中插入 `AVAudioUnitTimePitch` 节点：

```
旧：playerNode → mainMixerNode
新：playerNode → timePitch → mainMixerNode
```

```swift
private let timePitch = AVAudioUnitTimePitch()

private func setupEngine() {
    engine.attach(playerNode)
    engine.attach(timePitch)
    engine.connect(playerNode, to: timePitch, format: format)
    engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    engine.prepare()
}

func setRate(_ rate: Float) {
    timePitch.rate = rate
}
```

`AVAudioUnitTimePitch` 在保持音调的同时改变播放速率。视频帧同步以 `audioClock` 为基准，音频变快后 `audioClock` 推进加快，视频自动跟着变快。

### 修复 6：FFmpegPlayerEngine.playbackRate 加 didSet

```swift
var playbackRate: Float = 1.0 {
    didSet {
        audioRenderer?.setRate(playbackRate)
    }
}
```

同时在 `setupAudioDecoder()` 创建新 `audioRenderer` 后恢复当前倍速，防止切换音轨后倍速丢失。

### 修复 7：AVPlayerEngine 缓冲恢复后恢复倍速

```swift
if isReady, self?.state == .buffering {
    self?.player?.rate = self?.playbackRate ?? 1.0
    self?.stateSubject.send(.playing)
}
```

## 涉及文件

| 文件 | 变更 |
|------|------|
| `Vanmo/Features/Player/Views/PlayerView.swift` | gestureLayer 添加 `.allowsHitTesting`；Menu 替换为 Button + 自定义浮动面板；修正 onTapGesture 顺序；controlsOverlay 背景添加 onTapGesture；添加 @State 控制 picker 显示/隐藏 |
| `Vanmo/Core/Player/AudioRenderer.swift` | 新增 `AVAudioUnitTimePitch` 节点插入音频图谱；新增 `setRate()` 方法；`reconfigure()` 保持变速节点连接 |
| `Vanmo/Core/Player/FFmpegPlayerEngine.swift` | `playbackRate` 添加 `didSet` 传递倍速给 `AudioRenderer`；`setupAudioDecoder()` 后恢复当前倍速 |
| `Vanmo/Core/Player/PlayerEngine.swift` | AVPlayerEngine 缓冲恢复观察器补充恢复 `player.rate` |
