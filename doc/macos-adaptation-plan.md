# macOS 适配现状与后续落地方案

本文档整理 Vanmo 当前 macOS 适配状态、已完成范围、主要风险，以及后续可执行的分阶段落地计划。

---

## 当前结论

macOS 目前处于 **基础骨架已落地，但完整桌面版尚未完成** 的阶段。

已完成内容足以让工程中存在独立 `VanmoMac` target，并具备 macOS App 入口、基础签名配置、CloudKit Debug/Release 分流和部分平台呈现隔离。但大量业务代码仍沿用 iOS 假设，尤其是播放器、字幕、颜色工具、OAuth 与部分 SwiftUI 视图中仍直接依赖 UIKit。

后续推进目标不应是一次性“全量迁移”，而应先保证 macOS target 可稳定生成、可编译，再逐步完成播放器 MVP 与桌面交互产品化。

---

## 已完成范围

### 工程与 target

- 已新增 `VanmoMac` target。
- 已新增 `Vanmo/App/VanmoMacApp.swift` 作为 macOS 入口。
- 已新增 `Vanmo/Resources/Info-Mac.plist`。
- 已新增 macOS entitlements：
  - `Vanmo/Vanmo-Mac.entitlements`：Debug 使用，不包含 iCloud capability。
  - `Vanmo/Vanmo-Mac-Cloud.entitlements`：Release 使用，包含 CloudKit。
- `Vanmo.xcodeproj/project.pbxproj` 中 macOS Debug/Release 配置已分流：
  - Debug: `Vanmo/Vanmo-Mac.entitlements`
  - Release: `Vanmo/Vanmo-Mac-Cloud.entitlements`
  - Release 增加 `-DCLOUDKIT_SYNC_ENABLED`

### App 入口

`VanmoMacApp` 当前已接入：

- `AppState`
- `ConnectionsViewModel`
- `CloudSyncCoordinator`
- SwiftData `ModelContainerFactory.makeSharedContainer()`
- 主题偏好 `ColorTheme`
- 字幕 provider 注册
- Prefetch 临时文件清理
- 基础窗口尺寸：`minWidth: 960`、`minHeight: 640`、默认 `1200 x 800`

### 云同步与签名策略

CloudKit 采用 Debug/Release 分流：

- Debug 构建不带 iCloud entitlement，兼容个人开发者账号。
- Release 构建通过 `CLOUDKIT_SYNC_ENABLED` 启用 CloudKit-backed SwiftData。
- Settings 中已通过 `CloudSyncAvailability` 避免 Debug 下误导用户开启 iCloud 同步。

### 平台隔离

已完成的基础隔离：

- `ContentView` 中播放器呈现方式分平台：
  - iOS: `fullScreenCover`
  - macOS: `sheet`
- `PlatformCompatibility.swift` 已提供：
  - iOS haptics
  - macOS 设备信息兜底
- `PlatformCompatibility.swift` 已放回 `Shared/Utilities`，避免 Xcode 将其解析为错误路径。

### 静态检查

`scripts/check-cloud-sync-multiplatform-scope.sh` 已覆盖：

- iOS/macOS Debug entitlement 不包含 iCloud。
- iOS Release entitlement 包含 CloudKit 容器；macOS Cloud entitlement 文件存在且包含 CloudKit。
- `project.pbxproj` 中 Release 使用 `CLOUDKIT_SYNC_ENABLED`。
- macOS Release entitlement 与容器 ID 的完整绑定校验仍建议在阶段 1 补齐。
- `PlatformCompatibility.swift` 位于 `Shared/Utilities`。
- `VanmoMac` target 存在。

---

## 当前主要缺口

### 1. `project.yml` 尚未完整承载 macOS target

当前 `project.yml` 主要仍是 iOS `Vanmo` target 配置。虽然 `Vanmo.xcodeproj` 中已经存在 `VanmoMac` target，但如果后续重新执行 XcodeGen，macOS target 有被覆盖或丢失的风险。

需要补齐：

- `VanmoMac` target。
- `VanmoMac` scheme。
- macOS dependencies / sources / resources。
- `Info-Mac.plist`。
- macOS Debug/Release entitlements 分流。
- Release `-DCLOUDKIT_SYNC_ENABLED`。
- 与现有静态检查联动。

### 2. UIKit 依赖仍较多

当前仍能看到多处直接依赖 UIKit 或 UIKit 类型：

- `UIApplication`
- `UIDevice`
- `UIImpactFeedbackGenerator`
- `UIColor`
- `UIImage`
- `UIView`
- `UIViewRepresentable`

高风险文件包括：

| 文件 | 风险 |
|------|------|
| `Core/Player/PlayerEngine.swift` | 直接使用 `UIImage` 等 UIKit 类型 |
| `Core/Player/KSPlayerEngine.swift` | `UIKit` / `UIView` / KSPlayer view 绑定 |
| `Core/Player/PlayerState.swift` | `UIView.ContentMode` |
| `Features/Player/Views/PlayerView.swift` | `UIViewRepresentable` 播放器承载 |
| `Core/Subtitle/SubtitleOverlayView.swift` | `UIImage` / `UILabel` / `UIViewRepresentable` |
| `Features/Player/Views/PlayerProgressBar.swift` | 直接 import UIKit |
| `Shared/Extensions/Color+Vanmo.swift` | `UIColor` 动态色 |
| `Shared/Utilities/DominantColorExtractor.swift` | `UIColor` / `UIImage` |
| `Core/Network/OAuth/OAuthCoordinator.swift` | `UIApplication` presentation anchor |
| `Features/Browser/Views/BrowserView.swift` | `UIColor` 动态背景 |
| `Features/Library/Views/LibraryView.swift` | `UIColor` 动态色 |
| `Features/Library/Views/FavoritesListView.swift` | `UIColor` 动态色 |

### 3. 播放器链路尚未形成 macOS MVP

播放器是 macOS 适配最大风险点：

- iOS 目前使用 `UIViewRepresentable` 承载 AVFoundation / KSPlayer 视频视图。
- macOS 需要对应 `NSViewRepresentable` 或独立 AppKit 播放器 surface。
- KSPlayer 在 macOS 上的能力、依赖与渲染视图需要单独验证。
- PiP、手势、触感、横竖屏、全屏策略均需要按 macOS 重新设计。

建议 macOS MVP 先保证：

- AVFoundation 路径可播放。
- 基础播放控制可用。
- SRT/VTT 文本字幕可用。
- KSPlayer、ASS/SSA、图片字幕、PiP 等能力后置。

### 4. OAuth 登录需要平台化

`OAuthCoordinator` 当前仍依赖 UIKit 的 `UIApplication.shared.connectedScenes` 查找 presentation anchor。

macOS 需要：

- 使用 `ASWebAuthenticationSession` 的 macOS presentation anchor。
- 避免直接引用 `UIApplication`。
- 将 iOS/macOS anchor 获取抽为平台层。
- 验证 Google Drive、OneDrive、Box、pCloud、Yandex.Disk 登录回调。

### 5. 桌面交互尚未产品化

当前 UI 仍以移动端 `TabView + NavigationStack` 为主。macOS 可运行后还需要桌面体验改造：

- 侧边栏 / 多栏导航。
- 菜单栏 commands。
- 键盘快捷键。
- 右键菜单。
- 拖拽导入。
- 多窗口或独立播放器窗口。
- 窗口尺寸、状态恢复和全屏行为。

---

## 后续落地阶段

### 阶段 1：工程稳定与可再生成

目标：确保 macOS target 不依赖手工修改 `project.pbxproj`，重新生成工程后仍存在。

任务：

- 在 `project.yml` 中新增 `VanmoMac` target。
- 为 `VanmoMac` 配置：
  - `platform: macOS`
  - `bundle identifier: com.vanmo.app.mac`
  - `Info-Mac.plist`
  - `Vanmo-Mac.entitlements`
  - `Vanmo-Mac-Cloud.entitlements`
  - Debug / Release CloudKit 分流
  - `MACOSX_DEPLOYMENT_TARGET = 14.0`
- 新增 `VanmoMac` scheme。
- 更新静态检查，确保 `project.yml` 和 `project.pbxproj` 都保留 macOS target。
- 执行一次 XcodeGen 后确认 `VanmoMac` target 没有丢失。

验收标准：

- `xcodebuild -list` 能看到 `Vanmo` 与 `VanmoMac`。
- 重新生成工程后 `VanmoMac` target 仍存在。
- Debug 不含 iCloud capability。
- Release 含 CloudKit entitlement 与 `CLOUDKIT_SYNC_ENABLED`。

### 阶段 2：macOS 编译闭环

目标：让 `VanmoMac` target 在 Debug 下完成编译。

任务：

- 跑 `xcodebuild -scheme VanmoMac -configuration Debug`。
- 整理 UIKit 编译错误清单。
- 将平台相关类型集中抽象：
  - `PlatformImage`
  - `PlatformColor`
  - `PlatformView`
  - `PlatformContentMode`
  - `PlatformApplication`
  - `PlatformAuthenticationAnchor`
- 对无法立即支持的 iOS-only 能力加明确 macOS fallback。
- 将纯 iOS 能力限制在 `#if os(iOS)` 内，例如：
  - haptics
  - PiP
  - 横竖屏
  - iOS app delegate 行为

验收标准：

- `VanmoMac` Debug 编译通过。
- iOS `Vanmo` Debug 编译不回退。
- 不引入 tvOS 范围。

### 阶段 3：播放器 macOS MVP

目标：先让 macOS 能打开播放器并完成基础播放。

任务：

- 新增 macOS 播放器 surface：
  - iOS: `UIViewRepresentable`
  - macOS: `NSViewRepresentable`
- 优先打通 AVFoundation 播放路径。
- 将 KSPlayer macOS 支持作为独立验证项：
  - 若可用，接入 `NSView` 渲染。
  - 若不可用，macOS 暂时 fallback 到 AVFoundation，并显示能力提示。
- 梳理播放器功能分级：
  - 必须：播放 / 暂停 / 进度 / 音量 / 全屏 / 关闭。
  - 次要：字幕选择 / 章节 / 倍速 / 音轨。
  - 后置：PiP / 手势 / ASS 特效 / 图片字幕 / sample-buffer PiP。
- 将触感、手势、设备方向等 iOS-only 逻辑移出 macOS 路径。

验收标准：

- macOS 可播放本地或远程基础视频。
- 播放器 sheet 或独立窗口可以正常关闭。
- 播放进度能写入 SwiftData。
- 不影响 iOS 播放器现有能力。

### 阶段 4：字幕与图像处理平台化

目标：恢复 macOS 下字幕和主色提取等视觉能力。

任务：

- 将 `SubtitleOverlayView` 拆分：
  - SwiftUI 通用层
  - iOS UIKit 渲染层
  - macOS AppKit 渲染层
- `UIImage` / `NSImage` 抽象为平台图片。
- `UIColor` / `NSColor` 抽象为平台颜色。
- `DominantColorExtractor` 支持 macOS 图片输入。
- 动态色逻辑改为 SwiftUI `Color` 优先，必要时再落到平台色。

验收标准：

- SRT/VTT 字幕在 macOS 下可显示。
- 媒体封面主色提取不因 UIKit 类型阻断编译。
- iOS 动态色表现不回退。

### 阶段 5：OAuth 与连接能力验证

目标：macOS 下可以完成登录、浏览和播放。

任务：

- 平台化 `OAuthCoordinator` presentation anchor。
- 验证以下 OAuth 网盘：
  - Google Drive
  - OneDrive
  - Box
  - pCloud
  - Yandex.Disk
- 验证非 OAuth 协议：
  - WebDAV / AList / fnOS
  - SMB
  - 本地文件夹
  - IPTV
  - Emby / Jellyfin / Plex
- 本地文件夹接入 security-scoped bookmark。
- macOS 沙盒下验证下载目录、缓存目录、临时文件清理。

验收标准：

- macOS 下至少完成 WebDAV / 本地文件夹 / 一个 OAuth 网盘端到端验证。
- OAuth 登录回调成功。
- 连接配置仍可参与 CloudKit 同步。

### 阶段 6：桌面体验产品化

目标：从“能运行”升级为“符合 macOS 使用习惯”。

任务：

- 将主界面逐步从移动端 `TabView` 升级为：
  - `NavigationSplitView`
  - 侧边栏导航
  - 内容区列表/网格
  - 详情区
- 增加菜单栏 commands：
  - 新建连接
  - 刷新媒体库
  - 搜索
  - 打开设置
  - 播放 / 暂停
  - 快进 / 快退
  - 全屏
- 增加快捷键：
  - `Space`: 播放 / 暂停
  - `Command+F`: 搜索
  - `Command+R`: 刷新
  - `Command+,`: 设置
  - `Command+Enter`: 全屏播放
- 增加右键菜单：
  - 媒体项
  - 连接
  - 文件夹
  - 收藏
  - 书签
- 增加拖拽：
  - 拖入本地视频播放
  - 拖入文件夹添加本地连接
- 评估多窗口：
  - 主窗口
  - 独立播放器窗口
  - 设置窗口

验收标准：

- 常用操作可通过菜单或快捷键完成。
- 主界面在 1200x800 与更大窗口下布局合理。
- 鼠标右键、拖拽、窗口关闭行为符合 macOS 预期。

### 阶段 7：Release 与 CloudKit 验证

目标：验证 macOS Release + CloudKit 多端同步。

任务：

- 使用付费开发者账号构建 macOS Release。
- 验证 `Vanmo-Mac-Cloud.entitlements`。
- 验证 CloudKit 容器 `iCloud.com.vanmo.app`。
- 验证 iOS / macOS 间同步：
  - 连接配置
  - 文件夹书签
  - 非媒体服务器播放进度
  - 非媒体服务器收藏状态
- 验证 Debug 下设置页禁用 iCloud 同步提示。

验收标准：

- iOS 与 macOS Release 能共享 CloudKit 数据。
- Debug 仍可用个人开发者账号签名运行。
- 密码与 OAuth token 仍只保存在本机 Keychain，不进入 iCloud。

---

## 推荐优先级

| 优先级 | 事项 | 原因 |
|--------|------|------|
| P0 | `project.yml` 补齐 `VanmoMac` | 防止 XcodeGen 覆盖 macOS target |
| P0 | macOS Debug 编译闭环 | 所有后续体验优化的前提 |
| P0 | 播放器 AVFoundation MVP | macOS 版本核心价值 |
| P1 | OAuth anchor 平台化 | 影响官方网盘登录 |
| P1 | 字幕与颜色平台化 | 影响播放体验和 UI 质量 |
| P1 | 本地文件夹 security-scoped bookmark | macOS 沙盒必要能力 |
| P2 | 侧边栏 / 菜单 / 快捷键 | 桌面体验产品化 |
| P2 | 多窗口与拖拽 | macOS 增强体验 |
| P2 | Release CloudKit 多端验证 | 多端同步最终验收 |

---

## 不在当前阶段范围

- tvOS 适配。
- 重做播放器架构。
- 引入新的远程日志、遥测或代理链路。
- 为 macOS 单独重写全部 UI。
- 在未验证 macOS 编译前直接做大规模桌面交互重构。

---

## 建议下一步

下一轮建议从 **阶段 1：工程稳定与可再生成** 开始：

1. 更新 `project.yml`，正式声明 `VanmoMac` target。
2. 重新生成 Xcode 工程并确认 target 不丢失。
3. 运行 `VanmoMac` Debug 编译，收集真实错误。
4. 基于错误清单推进平台抽象与播放器 MVP。
