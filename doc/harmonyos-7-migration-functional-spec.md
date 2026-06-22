# Vanmo iOS 至 HarmonyOS 7 迁移功能规格

本文档用于指导 Vanmo 从当前 iOS 原生应用完整迁移至 HarmonyOS 7。内容基于当前 iOS 项目源码、既有 SDK 迁移调研文档以及 Figma 设计还原约束整理，目标是在 HarmonyOS 7 上实现与 iOS 版本等价的功能、体验与视觉表现。

> 说明：当前仓库中可读取的主工程为 iOS 工程，未发现可直接读取的 HarmonyOS 工程目录。因此本文档以 iOS 现状为迁移源，以 HarmonyOS 7 的 ArkTS / ArkUI 应用架构作为目标形态。

## 1. 迁移目标

### 1.1 产品目标

Vanmo 是一款类似 Infuse 的媒体播放与媒体库管理应用。HarmonyOS 7 版本需要完整覆盖 iOS 版本的核心能力：

- 本地与远程视频播放。
- 媒体库管理、继续观看、收藏、搜索、筛选与详情页。
- SMB、WebDAV、Emby、Jellyfin、Plex 等媒体源连接与浏览。
- SRT / WebVTT / 内嵌字幕、多音轨、章节与剧集选择。
- 元数据缓存、海报/背景/Logo/演员/剧集封面展示。
- 设置、外观主题、缓存清理与偏好保存。

### 1.2 技术目标

- 使用 HarmonyOS 7 适配的 ArkTS / ArkUI 技术栈重建应用。
- 保持 iOS 现有 MVVM + Feature 分层思想，迁移为适合 ArkTS 的页面、ViewModel、Repository、Service 分层。
- 将 SwiftData 迁移为 HarmonyOS 关系型数据库或等价持久化层。
- 将 Keychain、UserDefaults、FileManager、Network.framework、AVFoundation、SwiftUI 等 iOS 专有能力替换为 HarmonyOS 对应能力。
- 保留现有“系统播放器 + FFmpeg 类播放器”的双引擎分流思路。
- 优先通过本地 HTTP PrefetchProxy 层统一远程串流，降低播放器与 SMB/WebDAV/媒体服务器协议耦合。

### 1.3 设计目标

所有 HarmonyOS UI 必须严格以 Figma 设计稿为唯一视觉真相来源。当前已知 Figma 页面包括：

- `LibraryHome`：媒体库首页。
- `MediaDetail`：媒体详情。
- `File`：文件浏览。
- `Favorites`：收藏列表。

对于 Figma 中未覆盖的页面或状态，例如播放器、搜索、设置、添加连接、音轨/字幕选择、章节选择、剧集选择、加载态、空态、错误态，必须先在 Figma 中补齐设计稿，再进入开发实现。

## 2. iOS 项目现状

### 2.1 工程与技术栈

| 项目 | iOS 当前实现 | HarmonyOS 7 迁移方向 |
| --- | --- | --- |
| 工程类型 | iOS App，`Vanmo.xcodeproj` | HarmonyOS Stage 模型应用 |
| 语言 | Swift 5.9+ | ArkTS，必要时配合 NDK / Native 模块 |
| UI | SwiftUI + UIKit 播放器承载层 | ArkUI + Video / XComponent |
| 架构 | MVVM + Feature 模块化 | Page + ViewModel + Repository + Service |
| 异步 | async/await、Actor、Combine | Promise / async、TaskPool、状态观察 |
| 本地数据 | SwiftData | 关系型数据库 / Preferences / 文件缓存 |
| 网络 | URLSession | HarmonyOS 网络请求能力 |
| 播放 | AVPlayer + KSPlayer/FFmpeg | 系统播放器 + ijkplayer/FFmpeg 类引擎 |
| 凭据 | Keychain | HarmonyOS 安全存储能力 |
| 图片 | Kingfisher | ArkUI Image / ImageKnife 类方案 |
| XML | SWXMLHash | XML 转换/解析能力 |
| 动画 | lottie-ios | HarmonyOS Lottie 方案或原生加载组件 |

### 2.2 主导航结构

当前 iOS 根视图为 4 个 Tab：

| Tab | iOS 视图 | 功能 |
| --- | --- | --- |
| 媒体库 | `LibraryView` | 首页、继续观看、收藏、服务器媒体库、扫描媒体库 |
| 文件 | `ConnectionsView` | 连接管理、目录浏览、播放、同步 |
| 搜索 | `SearchView` | 本地媒体库搜索 |
| 设置 | `SettingsView` | 播放、音频、字幕、媒体库、元数据、外观、缓存 |

HarmonyOS 7 版本应保持同等信息架构，使用 ArkUI Tabs 或等价底部导航实现。

### 2.3 核心数据模型

#### MediaItem

`MediaItem` 是媒体库核心实体，包含：

- 基础信息：`id`、`title`、`originalTitle`、`year`、`overview`。
- 图片与评分：`posterURL`、`backdropURL`、`logoURL`、`rating`。
- 文件信息：`mediaType`、`fileURL`、`fileSize`、`duration`、`container`、`originalFileName`。
- 播放状态：`lastPlayedAt`、`lastPlaybackPosition`、`isWatched`。
- 收藏状态：`isFavorite`。
- 元数据：`tmdbID`、`genres`、`director`、`cast`、`originCountry`。
- 剧集信息：`seasonNumber`、`episodeNumber`、`showTitle`、`episodeTitle`、`seriesId`。
- 来源信息：`serverId`、`sourceConnectionId`。
- 轨道信息：`audioTracks`、`subtitleTracks`。

HarmonyOS 数据库建议拆分为：

- `media_items` 主表。
- `media_item_genres` 或 JSON 字段。
- `media_item_cast` 或 JSON 字段。
- `audio_tracks`。
- `subtitle_tracks`。

若首版为了迁移速度使用 JSON 字段，需要保留后续范式化迁移空间。

#### SavedConnection

`SavedConnection` 是媒体源连接实体，包含：

- `id`、`name`、`type`。
- `host`、`port`、`username`、`path`。
- 本地文件夹访问凭据：iOS 为 `bookmarkData`。
- `isFavorite`、`lastConnectedAt`、`lastSyncedAt`、`addedAt`。

HarmonyOS 迁移时：

- 密码不得进入主数据库明文字段。
- 连接密码、媒体服务器 token 应统一进入安全存储。
- 本地目录访问权限需要替换为 HarmonyOS 文件选择器与 URI 权限持久化能力。

#### PlaybackRecord

当前 iOS 工程中 `PlaybackRecord` 已注册到 SwiftData Schema，但业务代码主要使用 `MediaItem.lastPlaybackPosition` 和 `MediaItem.lastPlayedAt`。HarmonyOS 迁移时可采用两种策略：

- 首版保持 iOS 行为，将播放进度继续写在 `media_items`。
- 若需要独立历史记录、跨设备同步或 Trakt 类功能，再启用 `playback_records`。

## 3. 功能模块规格

### 3.1 媒体库

#### 功能范围

- 首页加载。
- 继续观看。
- 收藏入口与收藏统计。
- Emby / Jellyfin 服务器媒体库分区。
- 扫描库分区。
- 电影 / 电视剧媒体库筛选。
- 媒体卡片网格与列表展示。
- 类型与地区筛选。
- 排序。
- 下拉刷新。
- 空态、错误态、加载态。

#### 迁移要求

- 首页数据优先从本地数据库恢复，随后后台刷新服务器 live 数据。
- Emby / Jellyfin 首页应支持 VirtualFolders、ResumeItems、FavoriteItems、CollectionFolder 预览。
- 扫描库需要根据连接来源生成电影、电视剧等虚拟分区。
- 收藏变更后应刷新首页、收藏列表和详情页状态。
- 首屏渲染不得阻塞在全量服务器同步上。

#### 视觉要求

- `LibraryHome` 必须严格按 Figma 节点还原。
- 媒体卡片、继续观看、收藏堆叠卡片、分区标题、筛选 Chip、空态都应覆盖默认、加载、空、错误状态。

### 3.2 媒体详情

#### 功能范围

- 背景图、海报、Logo 标题。
- 标题、原名、年份、评分、简介。
- 类型、地区、导演、演员。
- 播放按钮、继续播放。
- 收藏切换。
- 剧集列表。
- 元数据刷新。

#### 迁移要求

- Emby / Jellyfin / Plex 来源条目应支持服务器元数据刷新。
- 本地扫描条目可先展示文件名解析结果，后续再接入独立刮削。
- 收藏切换需要区分本地收藏和服务器收藏。
- 剧集详情需要保持季、集层级组织。

#### 视觉要求

- `MediaDetail` 必须严格按 Figma 节点还原。
- Logo 加载前后的标题展示策略需要与设计稿一致。

### 3.3 文件与连接

#### 功能范围

- 保存连接列表。
- 添加连接。
- 删除连接。
- 自动重连最近连接。
- 本地文件夹访问。
- 远程目录浏览。
- 返回上级目录。
- 刷新当前目录。
- 播放远程视频。
- 同步当前目录或整连接到媒体库。

#### 协议支持矩阵

| 协议 | iOS 当前状态 | HarmonyOS 7 首版目标 |
| --- | --- | --- |
| 本地文件夹 | 完整 | 完整，基于文件选择器和持久访问权限 |
| SMB | 基本完整 | 完整，优先通过 PrefetchProxy 消除明文播放 URL |
| WebDAV | 完整 | 完整 |
| Emby | 完整 | 完整 |
| Jellyfin | 完整 | 完整 |
| Plex | 完整 | 完整 |
| FTP | 占位 | 可延后，除非明确列入首版 |
| SFTP | 占位 | 可延后，除非明确列入首版 |
| NFS | 占位 | 可延后，需专项调研 |
| DLNA | 占位 | 可延后，需专项调研发现与投播能力 |

#### 迁移要求

- 所有协议实现统一遵循 `RemoteFileService` 等价抽象。
- 媒体服务器协议额外实现 `MediaServerService` 等价能力，支持分页导入媒体库。
- 目录浏览必须按文件夹优先、视频文件优先展示。
- 远程播放 URL 不应长期持久化敏感凭据。

### 3.4 播放器

#### 功能范围

- 全屏播放。
- 横屏沉浸式。
- 播放 / 暂停。
- 进度条拖动。
- 快进 / 快退。
- 断点续播。
- 播放结束状态。
- 倍速。
- 画面缩放。
- 亮度手势。
- 音量手势。
- seek 手势。
- 双击播放暂停。
- 长按倍速。
- 音轨选择。
- 字幕轨选择。
- 章节选择。
- 剧集选择。
- 字幕叠加显示。

#### 双引擎策略

| 格式 | iOS 当前引擎 | HarmonyOS 7 目标引擎 |
| --- | --- | --- |
| mp4 / mov / m4v / mp3 / m4a / aac / wav | AVPlayerEngine | 系统播放器 |
| mkv / avi / wmv / flv / rmvb / ts / m2ts / webm 等 | KSPlayerEngine | ijkplayer / FFmpeg 类引擎 |

#### 迁移要求

- 保留 `PlayerEngineFactory` 等价工厂。
- 上层播放器 ViewModel 不直接依赖具体播放器 SDK。
- 播放器状态应统一为 idle、loading、playing、paused、buffering、ended、error。
- 当前时间、总时长、缓冲进度、音轨、字幕、章节通过统一接口暴露。
- 远程 URL 优先注册到 PrefetchProxy 后交给播放器。
- 播放器退出时保存进度并释放代理 session。

### 3.5 PrefetchProxy

#### 功能范围

- 本地 HTTP 服务。
- 将远程 URL 映射为 `http://127.0.0.1:<port>/stream/<token>`。
- 支持 HTTP Range 请求。
- 支持缓存片段。
- 支持注册和注销播放 session。
- 支持远程请求失败时返回合理 HTTP 错误。

#### 迁移要求

- HarmonyOS 版本应优先重建该层，而不是让播放器直接理解 SMB/WebDAV 等协议。
- SMB 场景下，代理层持有连接和凭据，播放器只消费本地 HTTP。
- 代理 token 应短期有效，播放结束立即释放。
- 日志不得输出完整 token、密码、cookie、访问密钥。

### 3.6 搜索

#### 功能范围

- 从本地媒体库搜索标题、原始标题、文件名、剧集标题。
- 空搜索提示。
- 无结果提示。
- 点击结果进入详情或播放。

#### 迁移要求

- 首版可使用本地数据库查询或内存过滤。
- 大媒体库场景应预留索引优化。
- 搜索结果展示样式需补齐 Figma 设计稿。

### 3.7 设置

#### 功能范围

- 播放设置：自动下一集、断点续播、硬件解码、默认倍速。
- 音频设置：输出模式。
- 字幕设置：自动加载、字号、首选语言。
- 媒体库设置：自动扫描、未观看标记。
- 元数据设置：自动下载、缓存管理。
- 外观设置：跟随系统、浅色、深色、多个自定义主题。
- 存储设置：缓存大小计算、清理缓存。
- 关于：版本号。

#### 迁移要求

- iOS `@AppStorage` 对应迁移到 Preferences。
- 主题切换应立即刷新页面。
- 缓存清理必须区分通用缓存和元数据缓存。
- 设置页及二级页需要先补齐 Figma 设计。

### 3.8 元数据与缓存

#### 功能范围

- Emby / Jellyfin / Plex 元数据导入。
- 海报、背景、Logo、演员头像、剧集封面缓存。
- 首页媒体库快照缓存。
- 单条刷新。
- 缓存大小统计。
- 清空元数据缓存。

#### 迁移要求

- 元数据缓存应落在应用沙箱可控目录。
- 缓存 key 需稳定，避免 URL query 中 token 变化导致重复缓存。
- 删除连接时需要评估是否保留或清理关联缓存。
- 服务器元数据是当前主来源，独立 TMDb / TheTVDB 刮削不应作为首版已完成能力。

### 3.9 字幕

#### 功能范围

- SRT 解析。
- WebVTT 解析。
- 内嵌字幕选择。
- 外挂字幕选择。
- 字幕首选语言自动选择。
- 字幕字号设置。
- 播放器字幕叠加显示。

#### 迁移要求

- 保留语言别名匹配逻辑，例如 zh / zho / chi / chs / cht / cn / chinese / 中文。
- 字幕时间轴应使用毫秒或秒统一表示。
- 字幕渲染需跟随 Figma 播放器设计，不应直接照搬 iOS 默认样式。

## 4. Figma 还原规范

### 4.1 必须执行的流程

每个页面或组件迁移前必须完成：

1. 在 Figma 中定位目标节点。
2. 读取设计上下文与截图。
3. 提取布局、间距、字号、字重、颜色、圆角、阴影、图标、动效、状态。
4. 映射为 HarmonyOS 主题 token 和 ArkUI 组件。
5. 开发实现。
6. 真机或预览截图与 Figma 逐项比对。

### 4.2 当前已知页面

| 页面 | Figma 状态 | 迁移要求 |
| --- | --- | --- |
| 媒体库首页 | 已知存在 | 首批实现 |
| 媒体详情 | 已知存在 | 首批实现 |
| 文件浏览 | 已知存在 | 首批实现 |
| 收藏列表 | 已知存在 | 首批实现 |
| 播放器 | 未在规则中确认 | 先补设计 |
| 搜索 | 未在规则中确认 | 先补设计 |
| 设置 | 未在规则中确认 | 先补设计 |
| 添加连接 | 未在规则中确认 | 先补设计 |
| 音轨/字幕/章节/剧集选择 | 未在规则中确认 | 先补设计 |

### 4.3 禁止事项

- 禁止未查看 Figma 就直接实现 UI。
- 禁止用“近似”替代设计稿中的颜色、间距、字体、圆角和图标。
- 禁止设计稿缺失时自由发挥。
- 禁止忽略加载、空、错误、禁用、选中等状态。
- 禁止图标风格混用。

## 5. SDK 与平台能力迁移

| iOS 能力 / SDK | 使用场景 | HarmonyOS 7 迁移方向 | 风险 |
| --- | --- | --- | --- |
| SwiftData | 媒体、连接、播放记录 | 关系型数据库 | 中 |
| UserDefaults / AppStorage | 设置、主题 | Preferences | 低 |
| Keychain | 连接密码 | 安全存储 | 中 |
| AVFoundation | 原生格式播放、时长读取 | 系统播放器 / 媒体能力 | 中 |
| KSPlayer / FFmpeg | 复杂格式播放 | ijkplayer / FFmpeg 类引擎 | 高 |
| Network.framework | 本地 HTTP 代理 | Socket / 本地 HTTP 服务 | 高 |
| SMBClient | SMB 浏览与下载 | ArkTS SMB / NDK libsmbclient / 代理方案 | 高 |
| SWXMLHash | WebDAV XML | XML 转换/解析 | 低 |
| Kingfisher | 图片加载缓存 | ArkUI Image / ImageKnife | 低 |
| lottie-ios | Loading 动画 | HarmonyOS Lottie 或原生动画 | 低 |
| Security-scoped bookmark | 本地文件夹权限 | 文件选择器 + URI 权限 | 中 |
| UIApplicationDelegate 方向锁 | 播放器横屏 | 窗口方向控制 | 中 |
| UIBackgroundModes audio | 后台播放 | 后台任务 / 音频策略 | 中 |

## 6. 推荐迁移阶段

### 阶段 0：准备与设计盘点

- 确认 HarmonyOS 7 目标设备、最低 API、工程模板。
- 盘点 Figma 页面覆盖情况。
- 为缺失页面补设计稿。
- 输出视觉 token：颜色、字体、圆角、间距、阴影、图标。
- 输出页面路由表。

### 阶段 1：基础工程与架构

- 创建 HarmonyOS 工程。
- 建立目录结构：`common`、`domain`、`data`、`services`、`viewmodels`、`pages`、`components`、`player`。
- 建立 AppState、路由、主题、日志、错误模型。
- 建立 Repository 和 Service 基础接口。

### 阶段 2：数据层

- 建立媒体、连接、播放记录表。
- 迁移设置 Preferences。
- 实现安全凭据存储。
- 实现媒体库基础查询、插入、更新、删除。
- 实现连接 CRUD。

### 阶段 3：UI 基础页面

- 按 Figma 实现底部 Tab。
- 实现媒体库首页。
- 实现文件页。
- 实现收藏列表。
- 实现媒体详情。
- 实现通用组件：媒体卡片、空态、加载、错误、评分、筛选 Chip。

### 阶段 4：远程协议与媒体库同步

- 实现本地文件夹。
- 实现 WebDAV。
- 实现 Emby。
- 实现 Jellyfin。
- 实现 Plex。
- 实现 SMB 浏览。
- 实现媒体扫描和服务器分页导入。

### 阶段 5：播放器与字幕

- 实现系统播放器引擎。
- 实现复杂格式播放器引擎。
- 实现播放器工厂。
- 实现播放器 UI、手势、控制层。
- 实现播放进度保存。
- 实现字幕解析与叠加。
- 实现音轨、字幕、章节、剧集选择。

### 阶段 6：PrefetchProxy 与串流优化

- 实现本地 HTTP 代理。
- 支持 Range 请求。
- 支持远程 HTTP/WebDAV/媒体服务器代理。
- 支持 SMB 代理串流。
- 优化缓存、错误恢复和释放策略。

### 阶段 7：设置、缓存与体验完善

- 实现设置页与二级页面。
- 实现主题切换。
- 实现缓存大小统计与清理。
- 实现元数据缓存。
- 补齐加载态、空态、错误态。
- 补齐真机日志与诊断能力。

### 阶段 8：验收与发布

- 按功能矩阵逐项验收。
- 按 Figma 逐页视觉验收。
- 按协议逐项播放验收。
- 覆盖弱网、大媒体库、横竖屏、后台播放、长时间播放。
- 输出 HarmonyOS 7 发布检查清单。

## 7. 首版验收标准

### 7.1 功能验收

- 可添加、删除、自动重连本地文件夹、WebDAV、SMB、Emby、Jellyfin、Plex。
- 可浏览目录并播放视频文件。
- 可同步媒体到媒体库。
- 可展示继续观看、收藏、媒体库分区。
- 可进入详情页并播放。
- 可保存播放进度并断点续播。
- 可选择字幕和音轨。
- 可搜索本地媒体。
- 可修改设置并在重启后保持。
- 可清理缓存和元数据缓存。

### 7.2 视觉验收

- 已有 Figma 页面与实现截图逐项一致。
- 页面间距、字号、颜色、圆角、图标、阴影、状态符合设计稿。
- 缺失 Figma 页面不得进入“已完成”状态。

### 7.3 性能验收

- 首页首屏不依赖全量服务器同步。
- 大媒体库列表滚动无明显卡顿。
- 远程播放支持 seek 和 Range。
- 播放退出能及时释放代理和播放器资源。
- 缓存不会无限增长，用户可清理。

### 7.4 安全验收

- 密码、token、cookie 不进入普通日志。
- SMB 播放 URL 不长期持久化明文账号密码。
- 安全存储用于保存连接密码和服务器 token。
- 本地代理 token 短期有效，播放结束释放。

## 8. 当前差距与风险

| 风险 | 说明 | 建议 |
| --- | --- | --- |
| HarmonyOS 工程缺失 | 当前仓库未发现可读取的 HarmonyOS 工程 | 先创建目标工程并建立基础架构 |
| Figma 页面不完整 | 播放器、设置、搜索、添加连接等页面未在规则中确认 | 先补设计再开发 |
| SMB 安全风险 | iOS 当前可能持久化带密码的 `smb://` URL | HarmonyOS 版改为 PrefetchProxy 代理 |
| 复杂格式播放 | FFmpeg / ijkplayer 接入成本高 | 独立播放器 PoC 先行 |
| FTP/SFTP/NFS/DLNA 未完整 | iOS 侧当前偏占位 | 不纳入首版，或作为协议专项 |
| 后台播放与权限 | 平台策略差异较大 | 单独做真机验证 |
| 大媒体库性能 | 搜索、筛选、分页、缓存都可能遇到瓶颈 | 数据库索引和分页优先设计 |

## 9. 不纳入首版的能力

除非另行确认，以下能力不应作为 HarmonyOS 7 首版迁移完成标准：

- Trakt 同步。
- 独立 TMDb / TheTVDB 刮削。
- FTP / SFTP 真实协议实现。
- NFS 真实协议实现。
- DLNA / UPnP 自动发现与投播。
- 后台下载队列。
- 断点续传下载到本地。
- 跨设备播放记录同步。

## 10. 关键源码参考

| 领域 | iOS 文件 |
| --- | --- |
| 应用入口 | `Vanmo/App/VanmoApp.swift` |
| 根导航 | `Vanmo/App/ContentView.swift` |
| 全局状态 | `Vanmo/App/AppState.swift` |
| 媒体模型 | `Vanmo/Features/Library/Models/MediaItem.swift` |
| 连接模型 | `Vanmo/Features/Browser/Models/ConnectionModels.swift` |
| 连接 ViewModel | `Vanmo/Features/Browser/ViewModels/BrowserViewModel.swift` |
| 媒体库 ViewModel | `Vanmo/Features/Library/ViewModels/LibraryViewModel.swift` |
| 播放器 ViewModel | `Vanmo/Features/Player/ViewModels/PlayerViewModel.swift` |
| 播放器页面 | `Vanmo/Features/Player/Views/PlayerView.swift` |
| 播放引擎工厂 | `Vanmo/Core/Player/PlayerEngineFactory.swift` |
| PrefetchProxy | `Vanmo/Core/Player/Prefetch/PrefetchProxy.swift` |
| 媒体扫描 | `Vanmo/Core/Storage/MediaScanner.swift` |
| 远程服务协议 | `Vanmo/Shared/Protocols/RemoteFileService.swift` |
| 协议工厂 | `Vanmo/Core/Network/ServiceFactory.swift` |
| SMB | `Vanmo/Core/Network/SMBService.swift` |
| WebDAV | `Vanmo/Core/Network/WebDAVService.swift` |
| Emby | `Vanmo/Core/Network/EmbyService.swift` |
| Jellyfin | `Vanmo/Core/Network/JellyfinService.swift` |
| Plex | `Vanmo/Core/Network/PlexService.swift` |
| 设置 | `Vanmo/Features/Settings/ViewModels/SettingsViewModel.swift` |
| 主题 | `Vanmo/Shared/Extensions/Color+Vanmo.swift` |
| SDK 调研 | `doc/ai/ios-harmony os adapt.md` |

## 11. 后续建议产物

- HarmonyOS 工程目录规范。
- iOS Swift 文件到 HarmonyOS ArkTS 文件的逐文件迁移映射表。
- 数据库表结构 DDL。
- Figma 页面覆盖矩阵。
- 协议迁移优先级和 PoC 验收记录。
- 播放器 PoC 文档。
- 真机测试清单。
