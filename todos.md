# 未完成的功能与后续推进计划

## P0：已完成 MVP，仍需产品化推进

### 1. 播放器核心体验
- [x] **外挂字幕链路完善**：已完成本地 SRT/VTT 轨道接入、字幕延迟、样式设置、字幕轨选择持久化，并为远程视频补充同目录外挂字幕发现策略；ASS/SSA 特效字幕仍放在 P1 独立推进。
- [x] **HDR / ISO / BDMV 探测产品化**：已完成 HDR 文件名候选探测、真实 HDR 元数据读取、AVFoundation EDR/HDR 输出基础调优，以及 ISO/BDMV 格式识别与原盘 playlist 解析层设计；完整蓝光播放仍放在 P1 独立推进。

### 2. 媒体源与国内生态
- [x] **AList 网盘入口产品化**：已完成 WebDAV 兼容入口说明、AList/fnOS 路径前导斜杠规范化、404 路径错误指引、首页扫描媒体库回归，以及跨 host 302 取流时剥离 `Authorization` 的兼容与安全修复。
- [x] **IPTV MVP 产品化**：已完成 M3U/M3U8 播放列表解析、`group-title` / `tvg-logo` / `tvg-id` / `url-tvg` 元数据解析、频道分组与台标 UI、刷新强制重拉播放列表、空频道提示和直播播放体验优化（LIVE 标识、跳过续播、断流重试、HLS 走 AVFoundation），并接入 XMLTV/EPG 拉取与 ViewModel/UI 展示当前/下一节目；播放失败的频道会在列表内标记为无法播放。
- [x] **fnOS 轻量适配完善**：已按 WebDAV 兼容预设接入，完成 AList/fnOS 路径规范化、按类型拆分 404 路径提示、fnOS/SMB/WebDAV 预设说明、fnOS 默认路径与 HTTPS/端口联动、端口/路径表单校验；P0 阶段继续以 WebDAV/SMB 为主，不引入 fnOS 专属 API。

### 3. 媒体库与交互
- [ ] **全局搜索增强**：当前搜索覆盖本地已同步媒体并做去重；继续接入 Emby/Plex live API、网盘远程搜索和按来源分组展示。
- [ ] **书签功能闭环**：当前已有 `FolderBookmark` 数据模型；继续实现 Browser 长按添加书签、首页展示、点击恢复连接并跳转到对应路径。

## P1：仍未真正实现的功能

### 1. 播放器与字幕
- [ ] **ASS/SSA 特效字幕引擎**：接入 libass 或 KSPlayer 原生 ASS 渲染能力，支持样式、定位、描边、动画和复杂字幕特效；当前仅避免把 ASS/SSA 误当 SRT 解析。
- [ ] **KSPlayer PiP 支持**：调研并实现 MKV/TS/AVI 等 KSPlayer 路径的 PiP，或提供明确的不可用提示与 AVFoundation fallback。
- [ ] **硬件解码设置接入**：将设置页中的硬件解码开关真正传入 KSPlayer options，并验证不同格式下的稳定性。
- [ ] **蓝光 ISO / 原盘播放**：在已有 `Core/Player/Disc/` 占位解析层基础上实现真实 playlist 解析、章节/音轨/字幕映射、playlist 选择和远程 Range 读取策略。

### 2. 官方国内网盘
- [ ] **阿里云盘官方接入**：实现 OAuth2、token 刷新、列目录、分页、取流 URL、错误处理和 Keychain 凭据存储。
- [ ] **百度网盘官方接入**：实现 OAuth2、授权限制处理、文件列表、转码/原画取流策略和限速提示。
- [ ] **115 网盘接入**：调研可用开放能力或合规接入方式，实现登录、目录浏览、取流与刷新。
- [ ] **夸克网盘接入**：调研可用开放能力或合规接入方式，实现目录浏览、取流与刷新。

### 3. 云同步与多端
- [ ] **CloudKit 全局同步**：用 CloudKit 或 CloudKit-backed SwiftData 同步服务器配置、非 Emby/Plex 播放进度、收藏和书签；密码不得直接进入 CloudKit。
- [ ] **同步冲突合并**：设计多设备播放进度、收藏状态、书签变更的冲突解决策略和同步触发时机。
- [ ] **tvOS 适配**：适配 Apple TV 焦点系统、遥控器交互、播放器控制层和媒体库大屏布局。
- [ ] **macOS 适配**：适配窗口尺寸、键盘快捷键、鼠标悬停、文件访问权限和播放器窗口行为。

### 4. 媒体库增强
- [ ] **在线字幕搜索与下载**：实现 Shooter / Subhd 等 Provider，打通搜索、匹配、下载、缓存、轨道加载和播放器 UI 入口。
- [ ] **Emby/Jellyfin 合集 (Collections)**：接入 BoxSet / Collections API，在详情页展示所属合集，并支持进入合集列表。
- [ ] **远程全局搜索聚合**：并发搜索本地库、Emby、Plex、AList/WebDAV、未来官方网盘，并按来源分组、合并重复项。
