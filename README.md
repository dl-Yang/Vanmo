# Vanmo

一款类似 Infuse 的 iOS 视频播放器应用，支持多格式播放、网络串流、媒体库管理、字幕和元数据抓取。

## 功能特性

### 视频播放
- AVFoundation 硬件解码播放引擎
- 支持 MP4、MKV、AVI、MOV 等常见格式
- 手势控制：左右滑动快进快退、左侧亮度、右侧音量
- 双击暂停/播放、长按倍速、捏合缩放
- 多音轨/字幕轨切换
- 播放速度调节 (0.5x ~ 4.0x)
- 断点续播

### 媒体库
- 网格/列表双模式浏览
- 按电影/剧集/收藏/未观看分类
- 支持标题、年份、评分、添加日期排序
- 继续观看、最近添加智能列表
- 详情页展示海报、背景图、演员、文件信息

### 网络串流
- SMB / FTP / SFTP / WebDAV 协议支持
- 远程文件浏览与流式播放
- 连接管理与凭据安全存储 (Keychain)

### 字幕
- SRT / WebVTT 格式解析
- 自动匹配同名字幕文件
- 字幕样式自定义（字号、颜色、位置）
- 时间偏移调整
- CJK 编码自动检测

### 元数据
- TMDb API 电影/剧集信息抓取
- 智能文件名解析 (S01E02、年份、清晰度标签)
- 自动匹配海报、评分、演员等信息

### 搜索
- 本地媒体库全文搜索
- TMDb 在线搜索

## 技术栈

| 项目 | 选型 |
|------|------|
| 语言 | Swift 5.9+ |
| 最低系统 | iOS 16.0 |
| UI 框架 | SwiftUI + UIKit (播放器层) |
| 架构模式 | MVVM + Clean Architecture |
| 异步 | Swift Concurrency (async/await, Actor) |
| 本地存储 | SwiftData |
| 网络 | URLSession |
| 播放核心 | AVFoundation |

## 项目结构

```
Vanmo/
├── App/                  # 应用入口、全局状态、导航
├── Core/                 # 核心基础设施
│   ├── Player/           # 播放引擎
│   ├── Network/          # 网络协议服务 (SMB, WebDAV, FTP)
│   ├── Storage/          # 媒体扫描、图片缓存
│   ├── Subtitle/         # 字幕解析与渲染
│   └── Metadata/         # TMDb API、文件名解析
├── Features/             # 功能模块
│   ├── Library/          # 媒体库
│   ├── Player/           # 播放器界面
│   ├── Browser/          # 文件浏览器
│   ├── Search/           # 搜索
│   └── Settings/         # 设置
├── Shared/               # 共享组件
│   ├── Components/       # 可复用 UI (PosterCard, RatingBadge...)
│   ├── Extensions/       # Swift 扩展
│   ├── Protocols/        # 公共协议
│   └── Utilities/        # 工具类 (Logger, Keychain)
└── Resources/            # 资源文件
```

## 开始开发

### 前置要求
- Xcode 15.0+
- iOS 16.0+ 设备或模拟器
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (推荐)

### 生成 Xcode 项目

```bash
# 安装 XcodeGen
brew install xcodegen

# 生成项目
xcodegen generate

# 打开项目
open Vanmo.xcodeproj
```

或直接在 Xcode 中新建 iOS App 项目并导入 `Vanmo/` 目录下的所有源文件。

### 配置

1. 在 Xcode 中设置 Development Team
2. 获取 [TMDb API Key](https://www.themoviedb.org/settings/api) 并在设置中配置
3. 连接真机或模拟器运行

## 许可证

见 [LICENSE](LICENSE) 文件。
