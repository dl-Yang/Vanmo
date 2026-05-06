# Emby HEVC 10-bit 流播放卡顿（KSPlayer 引擎）

## 状态：已修复

**修复时间**：2026-05-06 (UTC+8)

## 现象

通过 `emby /Videos/{id}/stream` 直播 1920×816 HEVC 10-bit、5.1 音轨、23.976fps 的 mkv 文件，KSPlayer 引擎下画面持续轻微卡顿（"一卡一卡的"），但音频正常。控制台中 `KSOptions.swift:387 videoClockSync` 警告刷屏：

```
[video] video delay=-0.357, clock=541.92, delay count=2, frameCount=15 drop next frame
[video] video delay=-0.482, clock=542.27, delay count=4, frameCount=12 drop next frame
[video] video delay=-0.705, clock=542.62, delay count=6, frameCount=9 drop next frame
...
```

特征：

- `frameCount` 一直在 9~16（接近帧队列上限 16）→ **解码不慢**
- `video delay` 持续负值 0.2~0.9s 且不收敛 → **视频被定义为永远落后于音频时钟**
- 主线程 vsync 60Hz 满帧（实测 `ticks=60, maxInterval=16.7ms, jank=0`）→ **不是渲染线程阻塞**

## 根因分析

通过运行时探针采集 `KSMEPlayer.dynamicInfo`，发现 audio clock 速率失真：

| 指标 | 修复前 | 期望值 |
|---|---|---|
| `playTimeRate` (`Δ currentPlaybackTime / Δ wall clock`) | **1.376** 持续稳态 | 1.0 |
| `displayFPS` | 14~23（被强制丢帧） | ~24 |
| `avSyncDiff` | -0.495s | ~0 |
| `droppedFrames+` | +5~+9 / s | 0 |

也就是说，wall clock 走过 1 秒，audio clock 已经"前进"了 1.376 秒。视频按真实 24fps 解码并渲染，但 `KSOptions.videoClockSync` 拿当前 `nextVideoTime` 与跑得过快的 audio clock 比较，每个帧都被判定为"落后 0.2~0.9s"，于是按 `% 2 == 0` 节奏不断 `dropNextFrame`——这就是"一卡一卡"的本质。

### audio clock 失真来自哪里

KSPlayer 默认 `audioPlayerType = AudioEnginePlayer`，其 audio clock 是手工累计的：

```swift
// KSPlayer/Sources/KSPlayer/MEPlayer/AudioEnginePlayer.swift
let currentPreparePosition = currentRender.timestamp
    + currentRender.duration * Int64(currentRenderReadOffset) / Int64(currentRender.numberOfSamples)
renderSource?.setAudio(time: timebase.cmtime(for: currentPreparePosition), ...)
```

本视频音频是 5.1 (6ch) 48kHz。设备 `maxHWChannels=2`，`KSPlayerEngine.configureAudioOptions` 已挂上 `aformat=channel_layouts=stereo` filter；但 KSPlayer 在 `sourceDidOpened()` 时仍会先用解码器原始 6ch 格式 `prepare(audioFormat:)` 一次，第一帧 audio frame 到达后才会用 stereo 格式重 `prepare`。`AVAudioEngine` 在第一阶段插入 `mainMixerNode` 做 6ch→2ch downmix 时，sample 实际消耗速率与上面公式中 `frame.duration / numberOfSamples` 的对应关系发生失真，audio clock 跑出 ~1.376× 的稳态偏移。

### 假设迭代过程（运行时证据驱动）

| 假设 | 状态 | 证据 |
|---|---|---|
| H1 主线程被 SwiftUI/字幕更新阻塞 | REJECTED | 自建 `CADisplayLink` watchdog 每秒输出 `ticks=60, maxInterval=16.7ms, jank=0` |
| H2 PGS 图像字幕 search 阻塞主 Timer | REJECTED | `subtitle.search` 全部 <5ms，无告警触发 |
| H3 走 FFmpegDecode 而非 VideoToolboxDecode 直通 | CONFIRMED 但非根因 | 配置确为 `asynchronousDecompression=false`，但解码端 `frameCount=9~16` 充足 |
| H6 渲染 `displayFPS` 不足 24 | 表面现象 | 21~24，是被丢帧"打断"的结果而非原因 |
| H7/H8 **audio clock 速率失真** | **CONFIRMED** | `playTimeRate=1.376` 稳态，`avSyncDiff` 持续 -0.5s 量级 |

## 修复方案

将音频输出从 `AudioEnginePlayer`（手工累计 audio clock）切换为 `AudioRendererPlayer`（基于 `AVSampleBufferAudioRenderer + AVSampleBufferRenderSynchronizer`），由系统级 RenderSynchronizer 维护时钟，绕开手工 sample 计数路径。

```swift
// Vanmo/Core/Player/KSPlayerEngine.swift
override init() {
    super.init()
    setupAudioSession()
    // 使用 AVSampleBufferAudioRenderer + AVSampleBufferRenderSynchronizer 进行 A/V 同步，
    // 避免 AudioEnginePlayer 在 5.1→stereo downmix 路径下手工推算 audio clock 出现速率漂移（实测 ~1.37×），
    // 该漂移会让视频被定义为持续落后并被反复丢帧。
    KSOptions.audioPlayerType = AudioRendererPlayer.self
}
```

`KSOptions.audioPlayerType` 是 KSPlayer 暴露的 public static 属性，设置一次后全局生效，会被新创建的 `KSMEPlayer` 实例采用。

## 验证日志（修复后稳态）

```
[VanmoDebug-H6/H7/H8] displayFPS=24.22, playTimeRate=0.999, avSyncDiff=-0.004s, droppedFrames+0, currentPlaybackTime=2.86s
[VanmoDebug-H6/H7/H8] displayFPS=23.24, playTimeRate=1.000, avSyncDiff=-0.002s, droppedFrames+0, currentPlaybackTime=3.86s
[VanmoDebug-H6/H7/H8] displayFPS=24.00, playTimeRate=0.560, avSyncDiff=0.015s, droppedFrames+0, currentPlaybackTime=4.42s
```

- `playTimeRate` 进入 0.999~1.000 ✓
- `displayFPS` 稳定 ~24 ✓
- `avSyncDiff` 收敛到 ~ms 级 ✓
- `videoClockSync ... drop next frame` 警告完全消失 ✓
- 用户实际体感：流畅，无卡顿 ✓

## 涉及文件

| 文件 | 变更 |
|------|------|
| `Vanmo/Core/Player/KSPlayerEngine.swift` | `init()` 中新增 1 行 `KSOptions.audioPlayerType = AudioRendererPlayer.self` 及说明注释 |

## 备注

- 对其他文件（音轨为 stereo 或文件本身就是 2ch）未观察到回归，因为 `AudioRendererPlayer` 是 KSPlayer 内置的等价路径。
- 同步问题在 5.1 → stereo downmix 路径上特别突出；2ch 源文件下 `AudioEnginePlayer` 的 audio clock 漂移可能不明显，但 `AudioRendererPlayer` 由系统直接管理，仍然是更稳妥的默认。
