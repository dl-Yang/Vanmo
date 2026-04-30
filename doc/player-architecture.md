# Vanmo 播放器架构文档

## 概述

Vanmo 播放器采用**双引擎架构**，通过统一的 `PlayerEngine` 协议抽象播放能力，根据媒体格式自动选择最合适的解码引擎。

- **AVPlayerEngine**：基于 Apple AVFoundation，用于原生支持的格式（MP4、MOV 等）
- **KSPlayerEngine**：基于 KSPlayer（内置 FFmpeg），用于非原生格式（MKV、AVI、RMVB 等）

---

## 架构图

```
┌─────────────────────────────────────────────────┐
│                  PlayerView                      │
│  ┌──────────┐  ┌───────────┐  ┌──────────────┐  │
│  │videoLayer│  │gestureLayer│  │controlsOverlay│  │
│  └────┬─────┘  └───────────┘  └──────────────┘  │
│       │                                          │
│  ┌────┴──────────────────────────────────────┐   │
│  │           PlayerViewModel (@MainActor)     │   │
│  │  ┌─────────────────────────────────────┐  │   │
│  │  │ Combine Bindings (state/time/dur)   │  │   │
│  │  └──────────────┬──────────────────────┘  │   │
│  └─────────────────┼─────────────────────────┘   │
└────────────────────┼─────────────────────────────┘
                     │
          ┌──────────┴──────────┐
          │   PlayerEngine      │  ← 协议
          │   (Protocol)        │
          └──────────┬──────────┘
                     │
        ┌────────────┼────────────┐
        ▼                         ▼
┌───────────────┐       ┌─────────────────┐
│ AVPlayerEngine│       │ KSPlayerEngine  │
│ (AVFoundation)│       │ (KSPlayer/FFmpeg)│
│               │       │                 │
│ MP4 MOV M4V  │       │ MKV AVI WMV FLV │
│ MP3 M4A AAC  │       │ RMVB TS WEBM    │
│ WAV CAF      │       │ OGV 3GP MPEG    │
└───────────────┘       └─────────────────┘
```

---

## 核心文件

| 文件 | 路径 | 职责 |
|------|------|------|
| `PlayerEngine.swift` | `Core/Player/` | 定义 `PlayerEngine` 协议和 `AVPlayerEngine` 实现 |
| `KSPlayerEngine.swift` | `Core/Player/` | KSPlayer 适配器，包装 `KSMEPlayer` |
| `PlayerEngineFactory.swift` | `Core/Player/` | 根据 URL 扩展名选择引擎 |
| `PlayerState.swift` | `Core/Player/` | 状态枚举、配置、音频模式等数据类型 |
| `PlayerViewModel.swift` | `Features/Player/ViewModels/` | 播放业务逻辑，桥接 Engine 与 View |
| `PlayerView.swift` | `Features/Player/Views/` | SwiftUI 播放界面 |

---

## PlayerEngine 协议

```swift
protocol PlayerEngine: AnyObject {
    // 状态发布
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    var currentTimePublisher: AnyPublisher<CMTime, Never> { get }
    var durationPublisher: AnyPublisher<CMTime, Never> { get }
    var bufferProgressPublisher: AnyPublisher<Double, Never> { get }

    // 只读状态
    var state: PlaybackState { get }
    var currentTime: CMTime { get }
    var duration: CMTime { get }
    var playbackRate: Float { get set }

    // 播放控制
    func load(url: URL, startPosition: CMTime?) async throws
    func play()
    func pause()
    func seek(to time: CMTime) async
    func stop()

    // 轨道选择
    func selectAudioTrack(index: Int) async
    func selectSubtitleTrack(index: Int?) async
    func availableAudioTracks() async -> [AudioTrackInfo]
    func availableSubtitleTracks() async -> [SubtitleTrackInfo]
}
```

所有状态通过 **Combine `CurrentValueSubject`** 发布，`PlayerViewModel` 订阅并驱动 UI 更新。

---

## 引擎选择策略

`PlayerEngineFactory` 根据 URL 的文件扩展名决定使用哪个引擎：

| 类别 | 扩展名 | 引擎 |
|------|--------|------|
| 原生格式 | mp4, mov, m4v, mp3, m4a, aac, wav, caf | `AVPlayerEngine` |
| FFmpeg 格式 | mkv, avi, wmv, flv, rmvb, rm, ts, m2ts, webm, ogv, 3gp, asf, vob, mpg, mpeg | `KSPlayerEngine` |
| 无扩展名 | （如 Emby 流式 URL） | `KSPlayerEngine`（默认） |

---

## 播放状态机

```
         load()
  idle ─────────► loading
                    │
                    ▼
                  paused ◄───── seek(完成+非播放)
                    │
               play()│
                    ▼
  buffering ◄──► playing ────► ended
     │              │
     │         pause()│
     │              ▼
     └──────► paused
                    │
               stop()│
                    ▼
                  idle
```

### PlaybackState 枚举

| 状态 | 含义 | UI 表现 |
|------|------|---------|
| `.idle` | 未加载 | 黑屏 |
| `.loading` | 正在加载媒体 | 居中 ProgressView |
| `.playing` | 正在播放 | 显示暂停按钮 |
| `.paused` | 已暂停 | 显示播放按钮 |
| `.buffering` | 缓冲中 | 居中 ProgressView |
| `.error(String)` | 出错 | 错误提示 |
| `.ended` | 播放结束 | 显示播放按钮 |

---

## KSPlayerEngine 实现细节

### 初始化与加载

1. `init()` 中配置 `AVAudioSession`（.playback + .moviePlayback + .longFormAudio）
2. `load()` 中在 **主线程** 创建 `KSMEPlayer`（因为内部会创建 Metal 渲染视图）
3. 通过 `CheckedContinuation` 将 `MediaPlayerDelegate.readyToPlay` 回调桥接为 async/await
4. 就绪后启动 0.5s 间隔的 Timer 更新 `currentTime`

### Seek 逻辑

```
seek(to:)
  │
  ├─ 记录 wasPlaying = (state == .playing || .buffering)
  ├─ 设置 shouldResumeAfterBuffering = wasPlaying
  ├─ 调用 player.seek(time:) 并等待完成
  ├─ 更新 currentTimeSubject
  └─ 如果 wasPlaying → player.play() + 发送 .playing
```

### 缓冲状态防抖

KSPlayer 的 `changeLoadState` 回调频繁在 `.loading` / `.playable` 之间切换，导致 UI 上 loading 指示器闪烁。解决方案：

- 记录 `lastPlayableTime`（上次变为 playable 的时间戳）
- 当 `.loading` 到来时，如果距离上次 `.playable` 不到 **0.5 秒**，忽略本次切换
- `changeBuffering` 回调只更新缓冲进度数值，不触发状态切换

### 视频渲染

KSPlayer 的 `KSMEPlayer.view` 是一个内置 Metal 渲染的 UIView，通过 `KSPlayerVideoLayer`（UIViewRepresentable）嵌入 SwiftUI：

```swift
struct KSPlayerVideoLayer: UIViewRepresentable {
    let videoView: UIView
    let scaleMode: VideoScaleMode

    func makeUIView(context: Context) -> UIView {
        // 创建容器，将 KSPlayer 的 view 通过 AutoLayout 铺满
    }
}
```

---

## 音频配置

### AVAudioSession

```swift
session.setCategory(.playback, mode: .moviePlayback, policy: .longFormAudio)
```

- `.playback`：允许后台播放，静音键不影响
- `.moviePlayback`：针对影片播放优化的音频路由
- `.longFormAudio`：适用于长时间播放内容

### 音频输出模式

在设置页面可选择三种模式，存储在 `UserDefaults("audio.outputMode")`：

| 模式 | 行为 |
|------|------|
| **自动** | 设备硬件 ≤2 声道时自动降混为立体声；支持多声道时保留原始声道 |
| **立体声** | 始终通过 FFmpeg `aformat=channel_layouts=stereo` 滤镜降混为 2 声道 |
| **环绕声** | 启用 `setSupportsMultichannelContent(true)`，多声道设备设置 `preferredOutputNumberOfChannels` |

### 5.1 声道降混

当设备只有 2 声道输出（iPhone 扬声器/普通耳机）时，5.1 音源必须降混为立体声。如果不降混，中置声道（Center = 人声对白）会丢失，只能听到环境音。

降混通过 KSOptions 的 `audioFilters` 实现：
```swift
options.audioFilters = ["aformat=channel_layouts=stereo"]
```

### 编解码器识别

从 KSPlayer 轨道的 `description` 字符串解析出友好名称：

| 原始标识 | 显示名称 |
|----------|----------|
| truehd / mlp | TrueHD |
| eac3 / e-ac-3 | Dolby Digital Plus |
| ac3 / ac-3 | Dolby Digital |
| dts-hd ma | DTS-HD MA |
| dts / dca | DTS |
| aac | AAC |
| flac | FLAC |

声道布局：1=Mono, 2=Stereo, 6=5.1, 8=7.1

音轨选择器显示格式示例：`English · Dolby Digital Plus · 5.1`

---

## PlayerViewModel

`@MainActor` 标注，驱动整个播放界面的业务逻辑。

### 生命周期

```
PlayerView.task → viewModel.onAppear()
  ├─ engine.load(url:, startPosition:)
  ├─ 获取音轨 / 字幕轨信息
  ├─ 自动匹配首选字幕语言
  ├─ 加载章节列表
  ├─ engine.play()
  └─ 启动控件自动隐藏计时器

PlayerView.onDisappear → viewModel.onDisappear()
  ├─ 保存播放进度到 MediaItem
  └─ engine.stop()
```

### 字幕自动匹配

按优先级评分选择字幕轨：
1. `languageCode` 完全匹配首选语言别名（score=3）
2. `title` 匹配首选语言别名（score=2）
3. `languageCode` 前缀匹配（score=1）

支持的语言别名：
- 中文：zh, zho, chi, chs, cht, cn, chinese, 中文, 简体, 繁体
- 英文：en, eng, english, 英文
- 日语：ja, jpn, japanese, 日语, 日本語
- 韩语：ko, kor, korean, 韩语, 한국어

### 进度保存

`onDisappear` 时自动保存：
- `lastPlaybackPosition` = 当前播放时间
- `lastPlayedAt` = 当前日期
- 如果播放进度 > 90%，标记 `isWatched = true`

---

## PlayerView 手势系统

播放界面分为三列手势区域：

```
┌──────────┬──────────┬──────────┐
│          │          │          │
│  亮度调节  │  中央区域  │  音量调节  │
│  (左1/3)  │  (中1/3)  │  (右1/3)  │
│          │          │          │
│  上下拖动  │ 单击:控件  │  上下拖动  │
│          │ 双击:暂停  │          │
│          │ 左右拖:进度 │          │
│          │ 长按:2x加速│          │
└──────────┴──────────┴──────────┘
```

| 手势 | 区域 | 功能 |
|------|------|------|
| 上下拖动 | 左侧 1/3 | 调节屏幕亮度 |
| 上下拖动 | 右侧 1/3 | 调节音量 |
| 单击 | 中央 1/3 | 显示/隐藏控件 |
| 双击 | 中央 1/3 | 播放/暂停 |
| 左右拖动 | 中央 1/3 | 进度拖动（±120s 范围） |
| 长按 0.5s | 中央 1/3 | 2x 倍速播放（松开恢复） |

---

## 控件栏

### 顶部栏
- 返回按钮（dismiss）
- 章节列表按钮（有章节时显示）
- 音轨/字幕选择器
- 播放速度选择（0.5x ~ 4.0x）
- 画面比例选择（适应/填充/拉伸）

### 中央
- 后退 10s / 播放暂停 / 前进 10s
- loading/buffering 时显示 ProgressView

### 底部栏
- 进度条（支持拖动 seek，显示缓冲进度）
- 当前时间 / 剩余时间

### 自动隐藏
- 控件显示后 3 秒自动隐藏（仅在 playing 状态下）
- 任何交互操作会重置计时器

---

## 第三方依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| [KSPlayer](https://github.com/kingslay/KSPlayer) | 2.3.4+ | FFmpeg 播放引擎，支持 MKV/AVI 等格式，硬件解码，Metal 渲染 |
| FFmpegKit | 6.1.3 | KSPlayer 的子依赖，FFmpeg 预编译二进制 |

KSPlayer 通过 Swift Package Manager 集成。
