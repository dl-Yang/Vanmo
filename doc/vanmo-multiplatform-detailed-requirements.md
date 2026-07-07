# Vanmo iOS & macOS 功能需求与架构详细文档

本文档基于 `doc/vanmo-ios-current-requirements.md` 和 `doc/mac-todo.md` 等架构规划资料，详细整理了 Vanmo iOS（当前主产品）的功能基线，以及 Vanmo-macOS（独立开发的全新桌面端）的功能对齐情况和架构实现路线。

---

## 1. 架构定位与核心原则

Vanmo 采用 **"核心逻辑共享、UI 与表现层完全隔离"** 的架构蓝图：

- **VanmoCore (底层 SPM 纯逻辑库)**: 绝对禁止 UI 依赖（无 UIKit/AppKit），包含 `Models` (SwiftData 确保双端 Schema 一致)、`Network` (网络协议/OAuth)、`Storage` (媒体扫描/云同步)、`Parsers` (字幕/原盘解析)。
- **Vanmo (iOS 纯净端)**: 包含移动端全屏 UI、基于 TabBar 的导航、iOS 专属 ViewModels 和基于 UIViewRepresentable 的播放器。
- **VanmoMac (macOS 纯净端)**: 从零开发，包含原生的侧边栏 (Sidebar) 导航、多栏结构、桌面专属 ViewModels、以及基于 NSViewRepresentable 的底层播放器。

---

## 2. 功能对齐总览表

| 模块 | Vanmo iOS (基准线) | Vanmo macOS (MVP 实现情况) |
|------|--------------------|----------------------------|
| **导航架构** | 底部四大 Tab：媒体库、文件、搜索、设置 | 原生侧边栏 + 主内容区 |
| **连接管理** | 本地、SMB、WebDAV、AList、fnOS、Emby、Jellyfin、Plex、IPTV、各 OAuth 网盘 | 核心协议全支持，通过 VanmoCore 复用。IPTV UI 暂时延后 |
| **目录浏览** | 浏览、递归扫描当前目录、文件夹书签 | 浏览、菜单重扫、收藏夹书签。本地支持 Quick Look 与拖拽播放 |
| **媒体库首页**| 继续观看、收藏、书签、Emby虚拟库、扫描库 | 分区完全对齐：书签/收藏预览、Emby/扫描库预览、子列表、网格切换 |
| **搜索** | 本地 SwiftData + 远程并发搜索 | 侧边栏搜索框 + 分组结果页，250ms 防抖 |
| **详情页** | 元数据展示、TV选集、收藏、关联合集 | 收藏双端同步、已看标记、元数据刷新、季集列表选择 |
| **播放器引擎**| AVFoundation + KSPlayer | 主打 AVPlayer，完整实现字幕/音轨/倍速/全屏/自动下一集。<br/>FFmpeg (KSPlayer) 评估完成用于特殊格式软解 |
| **云同步** | CloudKit 跨设备同步 (配置、书签、进度) | 完全对齐：通过 `VanmoCore.CloudSyncCoordinator` 确保双端一致 |
| **偏好设置** | 8大类完整设置项 | 完成 P0/P1：iCloud、播放偏好、字幕样式、外观等，共用 `@AppStorage` key |

---

## 3. Vanmo iOS 详细需求 (基准)

### 3.1 媒体源与扫描
- **扫描规则**：递归目录扫描（限制深度），支持电影和电视剧名解析、季集聚合。跳过不可播放文件。
- **差异化行为**：
  - 本地文件夹、SMB、WebDAV 等支持全量与增量扫库。
  - **Emby/Jellyfin** 不走本地扫库，首页直接对接服务端虚拟库 API。
  - **IPTV** 不入库，仅作为直播流解析，不记录续播。
  - **网盘合规**：百度网盘仅支持浏览+播放前解析，不自动扫库；禁止使用逆向 API。

### 3.2 媒体项与元数据
- 记录标题、类型、海报、时长、播放进度、首选字幕、HDR 标记等。
- 元数据目前优先从媒体服务器（如 Emby）提取，暂未包含独立的 TMDb 刮削模块。

### 3.3 搜索规则
- 并发匹配本地 SwiftData (标题、导演、演员) 和 媒体服务器 Live API。
- 对未入库的文件协议仅提供远程目录的浅层搜索。

### 3.4 播放器核心能力
- **引擎分发**：MP4/HLS 等走原生 AVFoundation，MKV/BDMV 走 KSPlayer。
- **续播逻辑**：非媒体服务器走本地进度，并与 CloudKit 同步；媒体服务器以服务端为准。
- **字幕管理**：支持内外挂 SRT/VTT/ASS，以及 OpenSubtitles 在线搜索下载。支持字体、颜色、延迟调整。

### 3.5 云同步 (CloudKit) 边界
- **同步对象**：非敏感的连接配置 (`SavedConnection`)、文件夹书签、本地播放进度与收藏 (`CloudMediaState`)。
- **不同步对象**：密码、OAuth Token (存本机 Keychain)，完整媒体元数据，以及 Emby/Jellyfin 自身的播放状态。

---

## 4. Vanmo macOS 详细实施路线 (三线并行至 MVP)

为了高效拉齐与 iOS 的能力，macOS 端采用从零建立 UI 与独立 VM，并在阶段 0 完成生命周期接线后，划分为三条并行主线：

### 线 1：媒体库 Parity (轨道 B)
- **ViewModel**：移植 iOS 的 `LibraryViewModel` 为 `MacLibraryViewModel`，接管 `VanmoCore` 的 `HomeCollectionCache` 和刷新逻辑。
- **首页 UI**：构建收藏叠卡、书签横滑、Emby/Jellyfin 虚拟库预览。
- **列表 UI**：建立 5 大子列表（`MacCollectionFolderListView`、`MacScannedLibraryListView` 等），实现网格与列表双模式及排序过滤功能。

### 线 2：播放器增强 (轨道 C)
- 依赖于核心 `MacPlayerViewModel`，主力完善 AVPlayer 的周边体验。
- **交互控制**：快捷键 (Space 暂停、左右快进、F全屏)、缓冲进度条、连续播放 (自动下一集)。
- **媒体流与字幕**：集成 `MacSubtitleOverlayView` 支持字幕渲染；构建 `MacTrackSelectorView` 用于音轨与字幕的实时切换，并集成在线字幕 Provider。

### 线 3：发现与配置 (轨道 D, E, F, G)
- **外壳与路由**：完善 `MacAppState` 侧边栏路由状态，使用户可在库、连接、搜索、设置中流转。
- **搜索与详情**：构建 `MacSearchViewModel` 进行本地及远程并发搜索，落地 `MacSearchResultsView`；打造 `MacMediaDetailView`，支持收藏、已看操作及电视剧选集。
- **设置面板**：搭建 `MacSettingsView`，涵盖 iCloud、播放(倍速/硬解/续播)、字幕样式等核心功能，且保证和 iOS 共享同样的 `@AppStorage` key 以确保偏好一致性。
- **平台专属增强**：右键菜单、拖拽播放、原生 Quick Look 以及顶部的 MenuBar 控制。

---

## 5. 安全与运维标准

- **安全性**：任何平台端侧收集的 OAuth access/refresh token 均不得写入云同步链路，依靠各端本地 Keychain 进行凭据隔离。
- **CI与双端一致性**：引入了 macOS xcodebuild，在 CI 环境下通过 `check-cloud-sync-multiplatform-scope.sh` 脚本确保 iOS 与 macOS 的云同步对象范围和属性名称绝对一致，防止任意一端破坏 Schema。
- **后续打磨**：现阶段 macOS MVP 已成型，后续迭代将着眼于 KSPlayer macOS FFmpeg 的深入调优、IPTV (延后需求) 以及独立下载队列的建设。

