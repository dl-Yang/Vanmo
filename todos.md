# 未完成的功能与后续推进计划

## P0：已完成 MVP，仍需产品化推进
2026.06.29更新：**已完成 P0**

### 1. 播放器核心体验

- [x] **外挂字幕链路完善**：已完成本地 SRT/VTT 轨道接入、字幕延迟、样式设置、字幕轨选择持久化，并为远程视频补充同目录外挂字幕发现策略；ASS/SSA 特效字幕仍放在 P1 独立推进。
- [x] **HDR / ISO / BDMV 探测产品化**：已完成 HDR 文件名候选探测、真实 HDR 元数据读取、AVFoundation EDR/HDR 输出基础调优，以及 ISO/BDMV 格式识别与原盘 playlist 解析层设计；完整蓝光播放仍放在 P1 独立推进。

### 2. 媒体源与国内生态

- [x] **AList 网盘入口产品化**：已完成 WebDAV 兼容入口说明、AList/fnOS 路径前导斜杠规范化、404 路径错误指引、首页扫描媒体库回归，以及跨 host 302 取流时剥离 `Authorization` 的兼容与安全修复。
- [x] **IPTV MVP 产品化**：已完成 M3U/M3U8 播放列表解析、`group-title` / `tvg-logo` / `tvg-id` / `url-tvg` 元数据解析、频道分组与台标 UI、刷新强制重拉播放列表、空频道提示和直播播放体验优化（LIVE 标识、跳过续播、断流重试、HLS 走 AVFoundation），并接入 XMLTV/EPG 拉取与 ViewModel/UI 展示当前/下一节目；播放失败的频道会在列表内标记为无法播放。
- [x] **fnOS 轻量适配完善**：已按 WebDAV 兼容预设接入，完成 AList/fnOS 路径规范化、按类型拆分 404 路径提示、fnOS/SMB/WebDAV 预设说明、fnOS 默认路径与 HTTPS/端口联动、端口/路径表单校验；P0 阶段继续以 WebDAV/SMB 为主，不引入 fnOS 专属 API。

### 3. 媒体库与交互

- [x] **全局搜索增强**：当前搜索覆盖本地已同步媒体并做去重；继续接入 Emby/Plex live API、网盘远程搜索和按来源分组展示。
- [x] **书签功能闭环**：当前已有 `FolderBookmark` 数据模型；继续实现 Browser 长按添加书签、首页展示、点击恢复连接并跳转到对应路径。

## P1：仍未真正实现的功能

### 1. 播放器与字幕

- [x] **ASS/SSA 特效字幕引擎**：已允许本地/远程 ASS/SSA 外挂轨进入选轨列表，KSPlayer 路径交由 `URLSubtitleInfo` / `KSSubtitleProtocol` 富字幕渲染并支持图片字幕输出；AVFoundation 或不可用路径会给出明确提示，仍避免误当 SRT/VTT 解析。
- [x] **KSPlayer PiP 支持**：已接入 KSPlayer sample-buffer PiP 能力探测与启动/退出入口；不可启动时提供明确提示，AVFoundation 原生路径继续使用既有 PiP。
- [x] **硬件解码设置接入**：已统一 `playback.hardwareDecoding` 偏好读取并传入 `KSOptions.hardwareDecode`，硬解加载失败时自动软解重试；设置页说明该开关下次加载生效。
- [x] **蓝光 ISO / 原盘播放**：已将 `Core/Player/Disc/` 从占位扩展为本地 BDMV / `.mpls` playlist 解析、主 playlist 选择、章节映射与 KSPlayer 播放 URL 解析；ISO 与远程原盘在未引入 UDF/libbluray/远程随机读完整链路前提供明确提示并保留 KSPlayer 直喂 fallback。

### 2. 官方国内网盘

- [x] **百度网盘官方接入合规占位**：已新增官方连接入口与未配置提示，明确仅走开放平台 OAuth/API，不使用 Cookie、抓包或逆向接口；文件列表、转码/原画取流策略和限速提示待官方参数与权限确认后继续实现。
- [x] **115 网盘合规接入占位**：已新增官方连接入口与开放平台入驻/审核提示，当前不使用非官方接口；登录、目录浏览、取流与刷新待开放平台权限确认后继续实现。
- [x] **夸克网盘合规接入占位**：已新增官方连接入口与合规调研提示，当前不使用非官方接口；目录浏览、取流与刷新待官方开放能力确认后继续实现。

### 2.1 国际网盘（2026.07.01 新增）

- [x] **通用 OAuth 2.0 基础设施**：`OAuthCoordinator`/`OAuthCredentialStore`/`OAuthProviderConfiguration` 支持 PKCE（公共客户端）与 Client Secret 两种授权码流程，`vanmo://oauth/{type}` 统一回调；开发者 Client ID / Secret 全部留空占位，需要手动在对应开发者后台申请后填入 `OAuthProviderConfiguration`。
- [x] **Google Drive**：`GoogleDriveService` 已实现目录浏览（`files.list` 分页）、取流（`alt=media`，播放期间持续携带 Bearer token）、下载与 401 自动 refresh；需要在 Google Cloud Console 创建 iOS 类型 OAuth 客户端并填入 Client ID。
- [x] **OneDrive**：`OneDriveService` 已实现目录浏览（Microsoft Graph `/me/drive` children 分页）、取流（`@microsoft.graph.downloadUrl` 匿名直链）与下载；需要在 Microsoft Entra 管理中心注册公共客户端应用并填入 Application (client) ID。
- [x] **Box**：`BoxDriveService` 已实现目录浏览（`folders/{id}/items`）、取流（拦截 `/files/{id}/content` 的 302 只取 `Location`）与下载；需要在 Box Developer Console 创建自定义 App 并填入 Client ID / Client Secret。
- [x] **pCloud**：`PCloudDriveService` 已实现目录浏览（`listfolder`）、取流（`getfilelink`）与下载，自动识别登录返回的 US/EU 数据中心 host；需要在 pCloud 开发者后台注册 App 并填入 Client ID / Client Secret。
- [x] **Yandex.Disk**：`YandexDiskService` 已实现目录浏览（`/v1/disk/resources`）、取流（`/resources/download`）与下载；需要在 oauth.yandex.com 注册应用并填入 Client ID / Client Secret。
- [ ] **上述 5 个网盘的真实登录/浏览/播放/下载验证**：当前仅完成协议实现与编译验证，尚未填入真实开发者凭据做端到端联调；拿到凭据后需要逐个真机验证登录态刷新、大文件续传、分页边界、错误提示文案。
- [ ] **MEGA 完整接入待评估**：官方无标准 REST + OAuth 接口，需要官方 MEGA SDK（C++，端到端加密，每个文件需客户端侧解密）深度集成，工作量和风险显著高于其余网盘；当前仅保留合规占位入口（`ConnectionType.mega`，复用官方网盘占位 UI 与 `UnsupportedOfficialCloudDriveService`），完整支持留待后续单独评估排期。

### 3. 云同步与多端

- [ ] **CloudKit 全局同步**：用 CloudKit 或 CloudKit-backed SwiftData 同步服务器配置、非 Emby/Plex 播放进度、收藏和书签；密码不得直接进入 CloudKit。
- [ ] **同步冲突合并**：设计多设备播放进度、收藏状态、书签变更的冲突解决策略和同步触发时机。
- [ ] **tvOS 适配**：适配 Apple TV 焦点系统、遥控器交互、播放器控制层和媒体库大屏布局。
- [ ] **macOS 适配**：适配窗口尺寸、键盘快捷键、鼠标悬停、文件访问权限和播放器窗口行为。

### 4. 媒体库增强

- [x] **在线字幕搜索与下载**：实现 Shooter / Subhd 等 Provider，打通搜索、匹配、下载、缓存、轨道加载和播放器 UI 入口。
- [x] **Emby/Jellyfin 合集 (Collections)**：接入 BoxSet / Collections API，在详情页展示所属合集，并支持进入合集列表。
- [x] **远程全局搜索聚合**：并发搜索本地库、Emby、Plex、AList/WebDAV、未来官方网盘，并按来源分组、合并重复项。