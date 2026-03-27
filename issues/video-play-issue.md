# issue：
## 操作：
**打开一份 mkv 视频开始播放**
## 问题：
- **视频不是 1 倍速播放，播放速度非常快**
- **设备发热明显**
- **快进和快退操作无效，视频直接卡住**
- **视频是填充满整个屏幕，而不是宽高等比适配缩放**
## 参考日志：
    ```
        video streamUrl: https://yy_tk2r50226:123456@alist.haoizan.com:443/dav/%E5%9B%9B%E5%BA%93%20%E4%B8%8D%E9%99%90%E9%80%9F%20%E8%A7%86%E9%A2%91/4K%E7%94%B5%E5%BD%B1/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%971-5%204K_20260119_205438/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%975%EF%BC%9A%E6%AD%BB%E6%97%A0%E5%AF%B9%E8%AF%81.2017.4K.mkv
[PlayerVM] init, file: 加勒比海盗5：死无对证.2017.4K.mkv, URL: https://yy_tk2r50226:123456@alist.haoizan.com:443/dav/%E5%9B%9B%E5%BA%93%20%E4%B8%8D%E9%99%90%E9%80%9F%20%E8%A7%86%E9%A2%91/4K%E7%94%B5%E5%BD%B1/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%971-5%204K_20260119_205438/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%975%EF%BC%9A%E6%AD%BB%E6%97%A0%E5%AF%B9%E8%AF%81.2017.4K.mkv
[EngineFactory] URL: https://yy_tk2r50226:123456@alist.haoizan.com:443/dav/%E5%9B%9B%E5%BA%93%20%E4%B8%8D%E9%99%90%E9%80%9F%20%E8%A7%86%E9%A2%91/4K%E7%94%B5%E5%BD%B1/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%971-5%204K_20260119_205438/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%975%EF%BC%9A%E6%AD%BB%E6%97%A0%E5%AF%B9%E8%AF%81.2017.4K.mkv, ext: mkv, format: ffmpeg
[EngineFactory] 选择 FFmpegPlayerEngine (FFMPEG_ENABLED=true)
[PlayerVM] engine type: FFmpeg
[PlayerVM] state changed: idle
[PlayerVM] duration updated: 0.000000s
[PlayerVM] onAppear, loading file: 加勒比海盗5：死无对证.2017.4K.mkv
[PlayerVM] calling engine.load(), startPosition: 0.000000s
[FFmpeg] load() called, url: https://yy_tk2r50226:123456@alist.haoizan.com:443/dav/%E5%9B%9B%E5%BA%93%20%E4%B8%8D%E9%99%90%E9%80%9F%20%E8%A7%86%E9%A2%91/4K%E7%94%B5%E5%BD%B1/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%971-5%204K_20260119_205438/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%975%EF%BC%9A%E6%AD%BB%E6%97%A0%E5%AF%B9%E8%AF%81.2017.4K.mkv
[FFmpeg] opening demuxer...
[Demuxer] opening: https://yy_tk2r50226:123456@alist.haoizan.com:443/dav/%E5%9B%9B%E5%BA%93%20%E4%B8%8D%E9%99%90%E9%80%9F%20%E8%A7%86%E9%A2%91/4K%E7%94%B5%E5%BD%B1/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%971-5%204K_20260119_205438/%E5%8A%A0%E5%8B%92%E6%AF%94%E6%B5%B7%E7%9B%975%EF%BC%9A%E6%AD%BB%E6%97%A0%E5%AF%B9%E8%AF%81.2017.4K.mkv, isFileURL=false
[PlayerVM] state changed: idle
[PlayerVM] duration updated: 0.000000s
[PlayerVM] state changed: loading
[Demuxer] avformat_open_input succeeded, finding stream info...
[Demuxer] stream[0]: type=0, codec=hevc, lang=nil, 3840x2160, sampleRate=0, channels=0
[Demuxer] stream[1]: type=1, codec=aac, lang=nil, 0x0, sampleRate=48000, channels=6
[Demuxer] opened: 2 streams, duration=7746.2s, 0 chapters, videoIdx=0, audioIdx=1, subIdx=-1
[FFmpeg] demuxer opened, videoStreamIndex: 0, audioStreamIndex: 1
[FFmpeg] duration: 7746.250000s
[FFmpeg] setting up video decoder...
[FFmpeg] setupVideoDecoder: found 1 video stream(s)
[FFmpeg] video stream: codec=hevc, codecID=173, 3840x2160, fps=23.976024
[PlayerVM] duration updated: 7746.250000s
[FFmpeg] found decoder: hevc
[FFmpeg] hwCodecType=1752589105, hwSupported=true
[FFmpeg] configuring HW decoder, extradata size=129
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
HardwareDecoder configured: 3840x2160, codec=1752589105
[FFmpeg] hardware decode configured for hevc
[FFmpeg] video decoder ready, hw=true, swCodecCtx=false
[FFmpeg] setting up audio decoder...
[FFmpeg] setupAudioDecoder: audioStreamIndex=1
[FFmpeg] audio stream: codec=aac, codecID=86018, sampleRate=48000, channels=6
[FFmpeg] creating AudioRenderer: sampleRate=48000.000000, outputChannels=2, sourceChannels=6
[AudioRenderer] starting engine, format: 48000.000000Hz, 2ch
[AudioRenderer] started successfully, isRunning=true, playerNode.isPlaying=true
[FFmpeg] audio decoder setup complete, swrContext=true
[FFmpeg] audio decoder ready, audioCodecCtx=true, audioRenderer=true
[FFmpeg] creating VideoRenderer on main thread...
[VideoRenderer] Metal device: Apple A15 GPU
[VideoRenderer] shader library: loaded
[VideoRenderer] vertex=true, fragment=true
[VideoRenderer] textureCache: created
[VideoRenderer] initialized successfully
[FFmpeg] setupVideoDecoderCallback, videoDecoder=true
[FFmpeg] starting decode threads...
[FFmpeg] load complete: 加勒比海盗5：死无对证.2017.4K.mkv
[PlayerVM] state changed: paused
[FFmpeg][Demux] demux loop started
[PlayerVM] engine.load() succeeded, state: paused
[FFmpeg][VideoDecode] video decode loop started, hwDecoder=true, swCodecCtx=false
[FFmpeg][Demux] first packet read: stream=0, size=1961, pts=0, keyframe=true
[FFmpeg][AudioDecode] audio decode loop started, audioCodecCtx=true
[PlayerVM] audio tracks: 1, subtitle tracks: 0
[PlayerVM] calling engine.play()
[FFmpeg] play() called, current state: paused
[FFmpeg] now playing
[PlayerVM] engine.play() called, state: paused
[PlayerVM] state changed: playing
[VideoRenderer] draw: no pixelBuffer
[AudioRenderer] first audio buffer enqueued: 1024 samples, pts=0.000000s, channels=2
[FFmpeg][AudioDecode] first audio frame decoded, samples=1024, pts=0
[HWDecoder] first output frame: 3840x2160, pts=0.000000s
[FFmpeg][HWCallback] first decoded frame received: 3840x2160, pts=0.000000s
[VideoRenderer] first frame enqueued: 3840x2160
[FFmpeg][HWDecode] first frame decoded successfully, pts=0.000000s
[FFmpeg][VideoDecode] first video packet dequeued, size=1961, pts=0, keyframe=true
[VideoRenderer] first successful draw, texture 3840x2160, drawableSize=1080.000000x2340.000000
[FFmpeg][Demux] progress: 500 packets, vQueue=42, aQueue=5
[FFmpeg][Demux] progress: 1000 packets, vQueue=8, aQueue=2
[FFmpeg][Demux] progress: 1500 packets, vQueue=7, aQueue=2
[FFmpeg][Demux] progress: 2000 packets, vQueue=23, aQueue=4
[FFmpeg][Demux] progress: 2500 packets, vQueue=91, aQueue=3
[FFmpeg][Demux] progress: 3000 packets, vQueue=100, aQueue=17
[FFmpeg][Demux] progress: 3500 packets, vQueue=99, aQueue=2
[FFmpeg][Demux] progress: 4000 packets, vQueue=1, aQueue=6
[FFmpeg][Demux] progress: 4500 packets, vQueue=1, aQueue=0
[FFmpeg][Demux] progress: 5000 packets, vQueue=14, aQueue=15
[FFmpeg][Demux] progress: 5500 packets, vQueue=4, aQueue=8
[FFmpeg][Demux] progress: 6000 packets, vQueue=2, aQueue=2
[FFmpeg][Demux] progress: 6500 packets, vQueue=2, aQueue=2
[FFmpeg][Demux] progress: 7000 packets, vQueue=2, aQueue=4
[FFmpeg][Demux] progress: 7500 packets, vQueue=9, aQueue=3
[FFmpeg][Demux] progress: 8000 packets, vQueue=63, aQueue=2
[FFmpeg][Demux] progress: 8500 packets, vQueue=98, aQueue=2
[FFmpeg][Demux] progress: 9000 packets, vQueue=2, aQueue=1
[FFmpeg][Demux] progress: 9500 packets, vQueue=3, aQueue=0
[FFmpeg][Demux] progress: 10000 packets, vQueue=7, aQueue=1
[FFmpeg][Demux] progress: 10500 packets, vQueue=34, aQueue=19
[FFmpeg][Demux] progress: 11000 packets, vQueue=50, aQueue=8
[FFmpeg][Demux] progress: 11500 packets, vQueue=21, aQueue=2
[FFmpeg][Demux] progress: 12000 packets, vQueue=1, aQueue=2
[FFmpeg][Demux] progress: 12500 packets, vQueue=5, aQueue=5
[FFmpeg][Demux] progress: 13000 packets, vQueue=2, aQueue=2
[FFmpeg][Demux] progress: 13500 packets, vQueue=2, aQueue=3
[FFmpeg][Demux] progress: 14000 packets, vQueue=2, aQueue=4
[FFmpeg][Demux] progress: 14500 packets, vQueue=2, aQueue=4
[FFmpeg][Demux] progress: 15000 packets, vQueue=2, aQueue=3
[FFmpeg][Demux] progress: 15500 packets, vQueue=2, aQueue=4
[FFmpeg][Demux] progress: 16000 packets, vQueue=5, aQueue=10
[FFmpeg][Demux] progress: 16500 packets, vQueue=1, aQueue=1
[FFmpeg][Demux] progress: 17000 packets, vQueue=3, aQueue=4
[FFmpeg][Demux] progress: 17500 packets, vQueue=4, aQueue=3
[FFmpeg][Demux] progress: 18000 packets, vQueue=24, aQueue=4
[FFmpeg][Demux] progress: 18500 packets, vQueue=26, aQueue=16
[FFmpeg][Demux] progress: 19000 packets, vQueue=1, aQueue=0
[FFmpeg][Demux] progress: 19500 packets, vQueue=7, aQueue=0
[FFmpeg][Demux] progress: 20000 packets, vQueue=5, aQueue=3
[FFmpeg][Demux] progress: 20500 packets, vQueue=80, aQueue=12
[FFmpeg][Demux] progress: 21000 packets, vQueue=88, aQueue=4
[FFmpeg][Demux] progress: 21500 packets, vQueue=65, aQueue=0
[FFmpeg][Demux] progress: 22000 packets, vQueue=101, aQueue=4
[FFmpeg][Demux] progress: 22500 packets, vQueue=99, aQueue=1
[FFmpeg][Demux] progress: 23000 packets, vQueue=87, aQueue=2
[FFmpeg][Demux] progress: 23500 packets, vQueue=52, aQueue=4
[FFmpeg][Demux] progress: 24000 packets, vQueue=1, aQueue=0
[FFmpeg][Demux] progress: 24500 packets, vQueue=49, aQueue=10
[FFmpeg][Demux] progress: 25000 packets, vQueue=79, aQueue=4
[FFmpeg][Demux] progress: 25500 packets, vQueue=34, aQueue=6
[FFmpeg][Demux] progress: 26000 packets, vQueue=41, aQueue=2
[FFmpeg][Demux] progress: 26500 packets, vQueue=69, aQueue=7
[FFmpeg][Demux] progress: 27000 packets, vQueue=62, aQueue=2
[FFmpeg][Demux] progress: 27500 packets, vQueue=87, aQueue=3
[FFmpeg][Demux] progress: 28000 packets, vQueue=47, aQueue=4
[FFmpeg][Demux] progress: 28500 packets, vQueue=2, aQueue=4
[FFmpeg][Demux] progress: 29000 packets, vQueue=3, aQueue=4
[FFmpeg][Demux] progress: 29500 packets, vQueue=2, aQueue=0
[FFmpeg][Demux] progress: 30000 packets, vQueue=2, aQueue=3
[FFmpeg][Demux] progress: 30500 packets, vQueue=0, aQueue=2
[FFmpeg][Demux] progress: 31000 packets, vQueue=1, aQueue=2
[FFmpeg][Demux] progress: 31500 packets, vQueue=2, aQueue=3
[FFmpeg][Demux] progress: 32000 packets, vQueue=1, aQueue=4
[FFmpeg][Demux] progress: 32500 packets, vQueue=1, aQueue=2
    ```