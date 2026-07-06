# VanmoCore 与 macOS 独立架构重构计划

本文档详细描述了 Vanmo 多端（iOS / macOS）架构重构的高可行性落地计划。基于“核心逻辑共享、UI 与表现层完全隔离”的原则（方案 C），我们将实现 macOS 端的从零干净开发，同时确保 CloudKit 多端同步的绝对安全与底层代码的高效复用。

---

## 1. 架构蓝图与核心原则

### 1.1 目标架构树

我们将整个工程拆分为三个物理隔离的模块：

```text
Vanmo/
├── Packages/
│   └── VanmoCore/                 # (新建) 本地 SPM 纯逻辑库
│       ├── Package.swift          # SPM 清单
│       ├── Sources/VanmoCore/
│       │   ├── Models/            # SwiftData @Model (确保双端 Schema 绝对一致)
│       │   ├── Network/           # 所有网盘协议、媒体服务器服务、OAuth
│       │   ├── Storage/           # MediaScanner, CloudSyncCoordinator
│       │   └── Parsers/           # 字幕解析, 原盘 Playlist 解析等
│       └── Tests/VanmoCoreTests/  # 核心逻辑单元测试
│
├── Vanmo/                         # (现有) iOS 纯净端
│   ├── UI/                        # 移动端全屏 UI, 手势, UITabBar
│   ├── ViewModels/                # 绑定移动端生命周期的 VM
│   └── Player/                    # 封装自 UIViewRepresentable 的播放器
│
└── VanmoMac/                      # (即将新建) macOS 纯净端，从零开发
    ├── UI/                        # 侧边栏, 多栏结构, 菜单栏响应
    ├── ViewModels/                # 桌面端专属 VM
    └── Player/                    # 封装自 NSViewRepresentable 的底层播放器
```

### 1.2 架构的“铁律” (Golden Rules)

1. **VanmoCore 绝对禁止 UI 依赖**：`VanmoCore` 模块内 **严禁** `import UIKit` 或 `import AppKit`。只能引入 `Foundation`、`SwiftData`、`CloudKit`、`AVFoundation`。
2. **模型唯一真相源**：所有参与持久化和云同步的 `@Model` 类必须存在于 `VanmoCore`，双端通过引入 `VanmoCore` 来初始化 `ModelContainer`。
3. **表现层隔离**：`UIColor`、`UIImage`、`NSColor`、`NSImage` 以及任何与视图直接相关的逻辑，必须留在端侧（`Vanmo/` 或 `VanmoMac/`），`VanmoCore` 只能输出 `Data`、`URL` 或纯十六进制颜色字符串。

---

## 2. 详细分阶段落地计划

整个架构转型分为三个递进的阶段，以保证现有 iOS 版本的稳定性不会在重构中途崩溃。

### 阶段一：建立 VanmoCore 与数据模型剥离 ~~(预计 1-2 天)~~ ✅ 已完成

**目标**：将所有 SwiftData 模型安全下沉，确保底层数据库无缝过渡。

1. **初始化 SPM 包**：
   - 在项目根目录创建 `Packages/VanmoCore` 文件夹。
   - 使用 `swift package init --type library` 初始化。
2. **修改 `project.yml`**：
   - 将 `VanmoCore` 作为本地依赖注册到当前的 iOS `Vanmo` Target 中。
3. **迁移核心数据模型**：
   - 移动 `MediaItem.swift`、`SavedConnection.swift`、`FolderBookmark.swift`、`CloudMediaState.swift` 等到 `VanmoCore/Models`。
   - **高能预警**：因为跨模块访问，必须将模型类的访问控制从 `internal` 提升为 `public`，并提供 `public init(...)`。
4. **验证 iOS 编译与同步**：
   - 在 iOS 工程中 `import VanmoCore`。
   - 解决所有引用报错，编译 iOS Target。
   - 运行真机，验证旧的数据库是否能正常被 `VanmoCore` 接管（只要属性名称类型不变，SwiftData 会自动兼容，数据不会丢失）。

### 阶段二：核心业务逻辑下沉与 UIKit 解耦 ~~(预计 2-3 天)~~ ✅ 已完成

**目标**：将网络请求、扫描逻辑和基础解析器移入 `VanmoCore`，并完成与 UIKit 的物理切割。

1. **下沉网络与解析层**：
   - 移动 `Network/` 目录下所有内容（SMB, WebDAV, Emby/Plex, Google Drive 等）。
   - 移动 `OAuth/` 层逻辑。
   - 移动 `Subtitle/` 中的 `SRTParser`、`VTTParser`（但**不包括** `SubtitleOverlayView`，视图留在端侧）。
2. **清理 UIKit 毒瘤**：
   - `OAuthCoordinator` 目前依赖 `UIApplication.shared` 寻找 `presentationAnchor`。
     - **解决方案**：在 `VanmoCore` 中定义一个抽象协议 `public protocol OAuthPresentationContextProvider`，由外部（iOS/macOS 端）实现并注入。
   - 图片处理（如 `DominantColorExtractor`）。
     - **解决方案**：提取器只接收 `Data` 或 `CGImage`，不直接依赖 `UIImage`。
3. **下沉存储与同步控制**：
   - 移动 `MediaScanner`、`CloudSyncCoordinator` 等逻辑层。

### 阶段三：废弃遗留靶点，从零构建 macOS Target ~~(独立推进)~~ 🔄 骨架已完成，UI 待开发

**目标**：清理当前半吊子的 macOS 兼容代码，创建真正的纯净版 macOS Target。

1. **大扫除**：
   - 从 iOS 工程和 `project.yml` 中删除当前为了兼容建立的 `VanmoMacApp.swift` 和半成品的 macOS Target 配置。
   - 删除代码中散落的 `#if os(macOS)` 补丁（因为新的 macOS 端是独立代码，不需要在 iOS 代码里写兼容）。
2. **在 `project.yml` 重建全新 Target**：
   ```yaml
   targets:
     Vanmo-macOS:
       type: application
       platform: macOS
       deploymentTarget: "14.0"
       sources:
         - path: VanmoMac
       dependencies:
         - package: VanmoCore
         # - 其他需要的 SPM 包
       settings:
         base:
           PRODUCT_BUNDLE_IDENTIFIER: com.vanmo.app.mac
       entitlements:
         path: VanmoMac/Vanmo-Mac.entitlements # 独立管理 macOS 的权限
   ```
3. **从零开发 macOS UI**：
   - 在新的 `VanmoMac` 目录下，新建全新的 `App` 入口。
   - 使用 `NavigationSplitView` 搭建原生的桌面端左右/三栏布局。
   - 重新编写完全脱离 UIKit 的 `PlayerViewModel` 和基于 `NSView` / `AVPlayerView` 的播放器界面。

---

## 3. 高风险点与应对策略

| 风险点 | 风险描述 | 应对策略 |
|---|---|---|
| **SwiftData 跨模块** | `@Model` 跨 Module 时，由于访问控制权限，容易引发初始化失败或编译器报错。 | 模型类必须显式声明 `public class`，每个持久化属性无需 public，但必须提供一个详尽的 `public init` 方法供外部调用。 |
| **CloudKit 权限** | `VanmoCore` 作为一个 Swift Package，无法拥有自己的 `entitlements`。 | **不要在 SPM 中设置签名**。`VanmoCore` 内部只写 `ModelConfiguration` 逻辑。真实的 `iCloud.com.vanmo.app` 容器权限声明在 iOS 和 macOS 的具体 App Target 的 `entitlements` 文件中。 |
| **OAuth 回调** | `ASWebAuthenticationSession` 强依赖 Window Anchor。 | 在 `VanmoCore` 提供接口，两端分别实现 Anchor。iOS 用 `UIWindow`，macOS 用 `NSWindow` 注入给 Coordinator。 |
| **第三方库依赖** | 原有 iOS 工程依赖的某些闭源或强依赖 UIKit 的库可能无法在 macOS 上运行。 | 在 `Package.swift` 中仔细甄别依赖。对于 `KSPlayer` 这种既有底层又有 UI 的库，建议底层逻辑留在 `VanmoCore`，而 UI 层分别在 iOS/macOS 依赖其对应的 UI 子模块。 |

---

## 4. 当前进度（截至 2026-07-06）

### 4.1 已完成

| 阶段 | 状态 | 说明 |
|---|---|---|
| **阶段一** | ✅ 已完成 | `Packages/VanmoCore` 已创建；`project.yml` 已注册本地 SPM 依赖；`MediaItem`、`SavedConnection`、`FolderBookmark`、`CloudMediaState`、`PlaybackRecord` 等 `@Model` 已迁入 `VanmoCore/Models`，并补齐 `public` 访问控制与 `public init`。 |
| **阶段二** | ✅ 已完成 | 网络层（SMB/WebDAV/Emby/Plex/云盘/OAuth）、存储层（`MediaScanner`、`CloudSyncCoordinator`）、元数据、字幕解析、播放器预取等核心逻辑已下沉；`OAuthPresentationContextProvider` 协议已抽象，iOS/macOS 端侧分别注入 Anchor。 |
| **阶段三（骨架）** | ✅ 已完成 | 独立 `Vanmo-macOS` Target 已建立；`VanmoMac/` 目录含 `VanmoMacApp` + `NavigationSplitView` 骨架；iOS 侧 `#if os(macOS)` 补丁已清理。 |
| **边界收口** | ✅ 已完成 | `PlatformDeviceInfo` 已移除 `UIKit` 依赖，改用 `Darwin.uname` + `ProcessInfo` + `UserDefaults` 持久化设备标识；`scripts/check-cloud-sync-multiplatform-scope.sh` 全项通过。注意：`deviceIdentifier` 在 iOS 升级后可能与旧版 `identifierForVendor` 不同，Emby/Jellyfin 会视为新设备；Plex 仍使用独立的 `PlexCredentialStore.clientIdentifier`。 |

### 4.2 构建验证结果

| 目标 | 结果 | 备注 |
|---|---|---|
| `swift build`（VanmoCore） | ✅ 通过 | |
| `swift test`（VanmoCoreTests） | ✅ 5/5 通过 | Schema / ConnectionType / Subtitle 等 |
| `Vanmo-macOS` scheme | ✅ 通过 | Debug / `CODE_SIGNING_ALLOWED=NO` |
| `Vanmo` iOS scheme | ⚠️ 编译通过，链接后脚本失败 | `Fix KSPlayer Framework Plist` 后置脚本需有效签名身份；与 VanmoCore 迁移无关 |

### 4.3 iOS 端侧保留（符合铁律）

以下模块 intentionally 留在 `Vanmo/`，不重复迁入 `VanmoCore`：

- `Core/Player/` — `PlayerEngine`、`KSPlayerEngine`（UIKit / AVAudioSession / KSPlayer UI）
- `Core/Subtitle/SubtitleOverlayView.swift` — 字幕渲染视图
- `Shared/Utilities/PlatformCompatibility.swift` — iOS 触觉反馈
- `Shared/Network/OAuthPresentationContextProvider+UIKit.swift` — OAuth Window Anchor
- 全部 `Features/` UI 与 ViewModel

---

## 5. 下一步行动建议

阶段一～三的核心迁移与边界收口已完成。后续按优先级推进：

### 5.1 macOS 原生 UI 开发（阶段三续）

1. **媒体库列表页**：在 `VanmoMac/UI/Library/` 新建 `LibrarySplitView`，复用 `VanmoCore` 的 `LibraryViewModel` 逻辑（或新建 macOS 专属 VM 调用 `MediaScanner` / `CloudSyncCoordinator`）。
2. **连接浏览页**：在 `VanmoMac/UI/Browser/` 实现 `ConnectionsView` 桌面版，接入 `SavedConnection` + `ServiceFactory`。
3. **播放器**：在 `VanmoMac/Player/` 基于 `AVPlayerView` / `NSViewRepresentable` 封装 macOS 播放器，依赖 `VanmoCore` 的 `PlayerCoreTypes` 与预取层，不引入 KSPlayer UIKit 模块。

### 5.2 iOS 端侧播放器进一步解耦

1. 将 `PlayerEngine` 协议与 `AVPlayerEngine` 中不含 UIKit 的部分评估是否可下沉到 `VanmoCore/Player/`（当前 `SubtitleContent` 含 `UIImage` 需先抽象为 `Data` / 协议）。
2. `DominantColorExtractor` 改为接收 `CGImage` / `Data`，去除 `UIImage` 依赖后迁入 `VanmoCore`。

### 5.3 回归测试与真机验证

1. 扩展 `VanmoCoreTests`：增加 `ModelContainerFactory` 内存容器 + CloudKit schema 一致性测试。
2. iOS 真机运行：验证旧数据库被 `VanmoCore` 接管后数据无丢失；CloudKit 同步在 Release 配置下正常。
3. macOS Release 配置：验证 `Vanmo-Mac-Cloud.entitlements` 下 SwiftData + CloudKit 双端同步。

### 5.4 CI 集成

1. 将 `scripts/check-cloud-sync-multiplatform-scope.sh` 纳入 CI。
2. CI 流水线至少覆盖：`swift test`（VanmoCore）+ `Vanmo-macOS` xcodebuild。
