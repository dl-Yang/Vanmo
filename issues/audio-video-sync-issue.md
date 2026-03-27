# 音画不同步：声音比视频画面快

## 操作

通过 FFmpegPlayerEngine 播放视频（MKV 或其他非原生格式），使用 AudioRenderer（AVAudioEngine）输出音频，VideoRenderer（Metal）渲染视频。

## 问题现象

播放过程中声音始终比视频画面快一点点（约 20-50ms），表现为：
- 对白先于口型
- 音效先于画面动作
- 整体观感"音频领先视频"

## 根因分析

音画不同步由三个延迟叠加导致：

### 1. audioClock 在音频渲染回调之间"冻结"

`AudioRenderer.audioClock` 基于 `playerNode.lastRenderTime` 计算当前音频播放位置。但 `lastRenderTime` 只在音频渲染回调时更新（iOS 默认 I/O buffer 约 11-23ms 更新一次）。在两次回调之间，`displayLinkFired` 读取到的 `audioClock` 是"过时的"——实际音频已经播放到更远的位置，但时钟报告的还是上次回调时的值。

这导致 `audioClock` 平均落后实际音频输出约半个 I/O buffer（5-11ms），视频帧选择依据的时间基准偏小，显示的帧偏早。

```swift
// 修复前：只返回上次渲染回调的位置
var audioClock: TimeInterval {
    // ...
    return base + Double(playerTime.sampleTime) / playerTime.sampleRate
}
```

### 2. VideoRenderer 异步 dispatch 增加一帧延迟

`displayLinkFired`（CADisplayLink 回调，运行在主线程）选定帧后调用 `videoRenderer.enqueue()`，该方法内部通过 `DispatchQueue.main.async` 调用 `setNeedsDisplay()`。虽然已经在主线程，async dispatch 仍会将 `setNeedsDisplay()` 推迟到下一个 run loop 迭代，可能错过当前 vsync 的绘制时机，增加约 16.7ms（60Hz）的显示延迟。

```swift
// 修复前：不必要的异步 dispatch
func enqueue(_ pixelBuffer: CVPixelBuffer) {
    // ...
    DispatchQueue.main.async { [weak self] in
        self?.metalView.setNeedsDisplay()
    }
}
```

### 3. 帧选择阈值未补偿管线延迟差异

原来使用固定 `+0.02s` 阈值选择要显示的帧：

```swift
while let first = frameBuffer.first, first.pts.seconds <= audioPTS + 0.02 { ... }
```

但音频和视频的输出管线延迟不同：
- **音频输出延迟**（`AVAudioSession.outputLatency`）：约 5-15ms
- **视频显示延迟**（从 displayLink 到实际上屏）：约 8-16ms

固定阈值无法适应不同设备和音频配置（扬声器 vs 蓝牙耳机）的延迟差异。

### 延迟叠加示意

```
时间轴 →

音频管线：  [解码] → [AudioEngine 缓冲] → [outputLatency] → 🔊 用户听到
视频管线：  [解码] → [帧缓冲] → [displayLink] → [async dispatch] → [GPU渲染] → [vsync] → 👁 用户看到
                                                  ↑ 额外延迟源
```

总延迟差：视频比音频多出 ~20-40ms 到达用户，导致"声音先于画面"。

## 修复方案

### 修复 1：AudioRenderer — 实时插值 audioClock

通过 `mach_absolute_time()` 对比 `lastRenderTime.hostTime`，将时钟从上次渲染回调插值到当前时刻：

```swift
var audioClock: TimeInterval {
    // ... 获取 playerTime ...
    var clock = base + Double(playerTime.sampleTime) / playerTime.sampleRate

    // 插值到当前 host time
    if nodeTime.isHostTimeValid {
        let renderNanos = Double(nodeTime.hostTime) * Self.machTimebaseNanosPerTick
        let nowNanos = Double(mach_absolute_time()) * Self.machTimebaseNanosPerTick
        let elapsed = (nowNanos - renderNanos) / 1_000_000_000
        if elapsed > 0 && elapsed < 0.5 {
            clock += elapsed
        }
    }
    return clock
}
```

`machTimebaseNanosPerTick` 缓存为 `static let` 避免每次调用 `mach_timebase_info`。`elapsed < 0.5` 防止暂停后恢复时过度补偿。

### 修复 2：FFmpegPlayerEngine — 动态补偿管线延迟

用 `CADisplayLink.targetTimestamp` 和 `AVAudioSession.outputLatency` 动态计算帧选择阈值：

```swift
let videoDisplayLatency = max(link.targetTimestamp - CACurrentMediaTime(), 0)
let audioOutputLatency = AVAudioSession.sharedInstance().outputLatency
let syncTarget = audioPTS + videoDisplayLatency - audioOutputLatency
```

- `videoDisplayLatency`：从当前时刻到帧实际上屏的延迟
- `audioOutputLatency`：从 AudioEngine 输出到扬声器/耳机的延迟
- 两者之差即音视频需要补偿的偏移量

这样帧选择自动适应设备和音频输出方式（蓝牙耳机延迟更大时会自动调整）。

### 修复 3：VideoRenderer — 消除异步 dispatch 延迟

新增 `displayImmediately()` 方法，在 `displayLinkFired`（已在主线程）中直接调用 `setNeedsDisplay()`：

```swift
func displayImmediately(_ pixelBuffer: CVPixelBuffer) {
    bufferLock.lock()
    currentPixelBuffer = pixelBuffer
    bufferLock.unlock()
    metalView.setNeedsDisplay()  // 直接调用，不经过 async dispatch
}
```

保留原 `enqueue()` 方法供非主线程调用者使用。

## 涉及文件

| 文件 | 修改内容 |
|------|---------|
| `Vanmo/Core/Player/AudioRenderer.swift` | `audioClock` 属性增加 hostTime 插值逻辑 |
| `Vanmo/Core/Player/FFmpegPlayerEngine.swift` | `displayLinkFired` 使用动态 syncTarget 替代固定阈值 |
| `Vanmo/Core/Player/VideoRenderer.swift` | 新增 `displayImmediately()` 方法 |
