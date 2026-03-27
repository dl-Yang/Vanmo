# MP4 网络播放黑屏（moov atom not found）

## 操作

通过 WebDAV 打开远程 MP4 视频（带认证凭据的 HTTPS URL），视频无法播放，显示黑屏。

## 问题现象

1. **MP4 文件无法打开** — 报错 `moov atom not found`
2. **部分 MP4 打开后黑屏** — 视频加载成功但无画面、进度条不动

## 根因分析

### Bug 1：moov atom not found

MP4 文件的 moov atom（元数据）位于文件末尾，FFmpeg 需要通过 HTTP Range 请求 seek 到文件尾部读取。但存在两个问题：

- **自定义 AVIO 上下文的 HTTP seek 不可靠**：`MKVDemuxer.openNetworkStream` 原先通过 `avio_open2` 创建自定义 AVIO 上下文，再赋值给 `formatContext.pb`。这种方式下 HTTP Range 请求的 seek 行为不正确，导致 MOV demuxer 无法在文件末尾找到 moov atom。
- **URL 内嵌凭据未传递到 Range 子请求**：即使改用 `avformat_open_input` 直接打开，FFmpeg 的 HTTP 处理器在发起 Range 子请求时未正确传递 URL 中嵌入的认证凭据（`https://user:pass@host/path`），导致服务器拒绝请求。

### Bug 2：视频加载成功但黑屏

`AudioRenderer.audioClock` 计算错误。该属性使用 `currentPTS`（最后入队缓冲区的 PTS）加上播放偏移量来估算当前音频播放位置。但音频解码远快于 4K 视频解码，`currentPTS` 会迅速跑到远超实际播放位置的值。

`FFmpegPlayerEngine` 的 A/V 同步逻辑依赖 `audioClock` 判断视频帧是否"过时"：

```swift
let audioPTS = self.audioRenderer?.audioClock ?? 0  // 错误值，如 2.0s
let diff = seconds - audioPTS                        // 0.0 - 2.0 = -2.0
if audioPTS > 0.1 && diff < -0.1 {
    return  // 视频帧被丢弃
}
```

由于 `audioClock` 虚假地超前，所有视频帧都被判定为"太晚"而丢弃，导致黑屏且进度条不更新。

## 修复方案

### 修复 1：MKVDemuxer.swift — 移除自定义 AVIO + 提取认证凭据

- 移除 `avio_open2` 创建自定义 AVIO 上下文的逻辑，改用 `avformat_open_input` 直接打开网络流
- 从 URL 中提取用户名/密码，通过 `Authorization: Basic` HTTP 请求头传递认证信息
- 将去除凭据的干净 URL 传给 FFmpeg，确保所有 HTTP 请求（包括 Range 子请求）都携带认证

```swift
private func openNetworkStream(url: URL) throws {
    var opts: OpaquePointer?
    setupHTTPOptions(&opts)

    var cleanURLString = url.absoluteString
    if let user = url.user, let password = url.password {
        let credentials = "\(user):\(password)"
        let base64 = Data(credentials.utf8).base64EncodedString()
        av_dict_set(&opts, "headers", "Authorization: Basic \(base64)\r\n", 0)
        // 从 URL 中移除凭据
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        if let clean = components?.string { cleanURLString = clean }
    }

    var ctx: UnsafeMutablePointer<AVFormatContext>?
    let ret = avformat_open_input(&ctx, cleanURLString, nil, &opts)
    // ...
}
```

### 修复 2：AudioRenderer.swift — 修正音频时钟

引入 `basePTS`（第一个入队缓冲区的 PTS），用 `basePTS + playerNode 实际播放采样时间` 替代错误的 `currentPTS + 播放偏移量`：

```swift
private var basePTS: TimeInterval = 0
private var hasBasePTS = false

var audioClock: TimeInterval {
    lock.lock()
    let base = basePTS
    lock.unlock()
    guard playerNode.isPlaying,
          let nodeTime = playerNode.lastRenderTime,
          let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
        return base
    }
    return base + Double(playerTime.sampleTime) / playerTime.sampleRate
}
```

在 `enqueue` 时记录首个缓冲区 PTS 作为基准，在 `flush()` 和 `stop()` 时重置。

## 涉及文件

| 文件 | 变更 |
|------|------|
| `Vanmo/Core/Player/MKVDemuxer.swift` | 重写 `openNetworkStream`，移除自定义 AVIO，提取凭据为 HTTP 头 |
| `Vanmo/Core/Player/AudioRenderer.swift` | 修正 `audioClock` 计算逻辑，引入 basePTS |

## 参考日志

```
[Demuxer] avio_open2 succeeded, seekable=1
[mov,mp4,m4a,3gp,3g2,mj2 @ 0x121df0a00] moov atom not found
[Demuxer] avformat_open_input failed: Invalid data found when processing input (code: -1094995529)
```
