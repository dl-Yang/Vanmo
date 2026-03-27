# MKV 播放画面抖动与进度条回跳

## 操作

通过 WebDAV 打开远程 MKV 视频（4K HEVC，23.976fps），使用 FFmpegPlayerEngine + VideoToolbox 硬件解码播放。

## 问题现象

1. **画面抖动** — 视频画面反复前后跳跃，不是正常顺序播放
2. **进度条回跳** — 进度条来回抖动，时间显示忽前忽后
3. **看起来像慢倍速播放** — 由于大量帧被丢弃或乱序显示，有效帧率远低于预期

## 根因分析

### 问题 1（主因）：VideoToolbox 输出帧按解码序而非显示序

`VTDecompressionSession` 输出解码帧的回调顺序是**解码序**（decode order），而非**显示序**（display order）。对于 HEVC 使用 B 帧的视频，解码序和显示序不同：

- 解码序：`I(0) P(3) B(1) B(2) P(6) B(4) B(5) ...`
- 显示序：`I(0) B(1) B(2) P(3) B(4) B(5) P(6) ...`

旧代码在 `onFrameDecoded` 回调中直接将帧送入 `VideoRenderer` 并更新 `currentTimeSubject`，导致：
- 画面在时间轴上前后跳跃（先显示 PTS=0.125s 的帧，再显示 PTS=0.042s 的帧）
- `currentTime` 非单调递增，进度条来回抖动

```swift
// 旧代码：直接渲染，无重排
videoDecoder?.onFrameDecoded = { [weak self] frame in
    self.videoRenderer?.enqueue(frame.pixelBuffer)  // 按解码序直接显示
    DispatchQueue.main.async {
        self.currentTimeSubject.send(frame.pts)     // PTS 非单调递增
    }
}
```

### 问题 2：解码线程逐包节流不适用于 B 帧

`throttleVideoDecodeLoop` 按每个 packet 的 PTS 对比 `audioClock` 做 sleep，但 B 帧的 PTS 在解码序中非递增（如 PTS=0, 0.125, 0.042, 0.083...），导致：

- P 帧 PTS 远超 audioClock → 过度 sleep → 解码变慢
- B 帧 PTS 小于 audioClock → 不 sleep → 突然加速
- 解码节奏忽快忽慢，帧到达不均匀

```swift
// 旧代码：按 packet PTS 节流，对 B 帧不适用
private func throttleVideoDecodeLoop(targetPTS: Double) {
    let diff = targetPTS - audioPTS
    if diff > 0.005 {
        Thread.sleep(forTimeInterval: min(diff / rate, 0.5))
    }
}
```

### 问题 3：缺少显示节拍器

没有 `CADisplayLink` 驱动帧显示，帧的显示完全由解码回调推动（push 模式），无法保证帧在正确的时间点上屏。

## 修复方案

### 核心思路：帧重排缓冲 + CADisplayLink 拉取

将数据流从 "解码即渲染"（push）改为 "缓冲排序 + 定时拉取"（pull）：

```
旧：VT回调 → 直接渲染 + 发送currentTime
新：VT回调 → 帧缓冲(按PTS排序) → CADisplayLink按audioClock拉取 → 渲染 + 发送currentTime
```

### 修复 1：新增帧重排缓冲区

在 `FFmpegPlayerEngine` 中添加按 PTS 排序的帧缓冲区：

```swift
private var frameBuffer: [DecodedVideoFrame] = []
private let frameBufferLock = NSLock()
private let maxFrameBufferSize = 16
private var lastDisplayedPTS: Double = -1

private func enqueueToFrameBuffer(_ frame: DecodedVideoFrame) {
    frameBufferLock.lock()
    let insertIndex = frameBuffer.firstIndex { $0.pts.seconds > frame.pts.seconds }
        ?? frameBuffer.endIndex
    frameBuffer.insert(frame, at: insertIndex)
    frameBufferLock.unlock()
}
```

### 修复 2：新增 CADisplayLink 帧节拍器

以 `audioClock` 为基准时间，每个显示周期从有序缓冲区中拉取 PTS <= audioClock 的最新帧渲染，保证 `currentTimeSubject` 单调递增：

```swift
@objc private func displayLinkFired(_ link: CADisplayLink) {
    guard state == .playing else { return }
    let audioPTS = audioRenderer?.audioClock ?? 0
    guard audioPTS > 0 else { return }

    frameBufferLock.lock()
    var frameToDisplay: DecodedVideoFrame?
    while let first = frameBuffer.first, first.pts.seconds <= audioPTS + 0.02 {
        frameToDisplay = frameBuffer.removeFirst()
    }
    frameBufferLock.unlock()

    guard let frame = frameToDisplay else { return }
    videoRenderer?.enqueue(frame.pixelBuffer)
    if frame.pts.seconds > lastDisplayedPTS {
        lastDisplayedPTS = frame.pts.seconds
        currentTimeSubject.send(frame.pts)
    }
}
```

### 修复 3：删除旧的逐包节流，改为缓冲区背压

删除 `throttleVideoDecodeLoop` 和 `syncVideoFrame`，改为缓冲区大小限制来实现背压：

```swift
// videoDecodeLoop 中，解码前检查缓冲区
while frameBufferCount > maxFrameBufferSize && isRunning && !seekRequested {
    Thread.sleep(forTimeInterval: 0.005)
}
```

### 修复 4：硬解和软解统一走帧缓冲

- 硬解 `onFrameDecoded` 回调改为 `enqueueToFrameBuffer(frame)` 而非直接渲染
- 软解 `decodeVideoSoftware` 构造 `DecodedVideoFrame` 后同样 `enqueueToFrameBuffer`
- 删除旧的 `syncVideoFrame`（逐帧 sleep 对 B 帧不适用）

### 修复 5：生命周期管理

- `seek()`：调用 `flushFrameBuffer()` 清空缓冲区，重置 `lastDisplayedPTS`
- `stop()`：先 `stopDisplayLink()` 再 `flushFrameBuffer()`，然后清理其他资源
- `pause()`/`play()`：displayLink 回调中 `state != .playing` 自动跳过，无需额外处理

## 涉及文件

| 文件 | 变更 |
|------|------|
| `Vanmo/Core/Player/FFmpegPlayerEngine.swift` | 新增帧重排缓冲区和 CADisplayLink；改造硬解/软解路径统一走缓冲；删除 `throttleVideoDecodeLoop` 和 `syncVideoFrame`；更新 seek/stop 生命周期 |

## 参考日志

```
[FFmpeg] video stream: codec=hevc, codecID=173, 3840x2160, fps=23.976024
[FFmpeg] hwCodecType=1752589105, hwSupported=true
HardwareDecoder configured: 3840x2160, codec=1752589105
[FFmpeg] hardware decode configured for hevc
[HWDecoder] first output frame: 3840x2160, pts=0.000000s
[FFmpeg][HWCallback] first decoded frame received: 3840x2160, pts=0.000000s
[VideoRenderer] first frame enqueued: 3840x2160
[VideoRenderer] first successful draw, texture 3840x2160, drawableSize=1080.000000x2340.000000
```
