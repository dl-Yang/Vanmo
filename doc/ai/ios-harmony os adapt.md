# Vanmo 项目 iOS 至 HarmonyOS NEXT（纯血鸿蒙）第三方 SDK 迁移调研报告

本报告针对原 iOS 项目中的核心第三方依赖进行技术平移分析，评估在 HarmonyOS NEXT（ArkTS/ArkUI 架构）下的适配状态、原生平移方案以及架构重构建议。

---

## 一、 SDK 迁移替换全局矩阵

| 原始 iOS SDK | 核心业务场景 | 最优选择（推荐方案） | 次选择（备选方案） | 迁移难易度 |
| :--- | :--- | :--- | :--- | :--- |
| **FFmpegKit** | 基础多媒体裁剪、格式适配、命令包装 | **鸿蒙原生媒体服务**<br>(AVCodec / AVMuxer) | **ohos_ffmpeg**<br>(社区原生 NDK 编译版) | ⭐⭐ (原生)<br>⭐⭐⭐⭐ (NDK) |
| **KSPlayer** | 双引擎播放分流、高级播放配置、多音轨切换 | **系统 AVPlayer** (常规格式) +<br>**鸿蒙版 ijkplayer** (复杂格式) | **纯 ijkplayer**<br>(全格式通吃，统一维护) | ⭐⭐⭐ |
| **Kingfisher** | 异步图片加载、多级缓存、预加载、占位图 | **ArkUI 原生 `Image` 组件**<br>(常规场景) | **`@ohos/imageknife`**<br>(深度致敬 Glide/Kingfisher) | ⭐ |
| **SWXMLHash** | 链式/下标解析 XML 数据 | **系统原生 `xml.ConvertXML`**<br>(一键将 XML 转为 ArkTS 对象) | **`fast-xml-parser`**<br>(OHPM 社区移植版) | ⭐ |
| **SMBClient** | NAS 局域网连接、文件列表浏览、文件下载 | **重构架构：PrefetchProxy 代理**<br>+ 纯 ArkTS 移植 `smb2` | **NDK 编译 `libsmbclient`**<br>并塞入 ijkplayer 播放器 | ⭐⭐⭐⭐ |

---

## 二、 各 SDK 详细替换与落地指南

### 1. FFmpegKit & KSPlayer（音视频双引擎架构）
由于这两个 SDK 在项目中强耦合构成了多媒体播放链路，故合并分析。

#### 📌 最优选择：系统 `AVPlayer` + 鸿蒙版 `ijkplayer` 双引擎工厂（强烈推荐）
* **落地方式**：完美复刻 iOS 的 `PlayerEngineFactory` 逻辑。`.mp4/.mov/.m4v` 等常规格式走鸿蒙系统内置的 `AVPlayer`，享受系统级硬件加速与超低功耗；其他冷门或复杂格式走开源社区深度适配的 `ijkplayer`（底层为 NDK 编译的 FFmpeg）。
* **UI 渲染层**：原 SwiftUI 的 `UIViewRepresentable` 承载的视频层，整体替换为 ArkUI 的 **`XComponent`** 组件（设置 `type: XComponentType.SURFACE`）。通过 N-API 跨层调用，将 ijkplayer C++ 层的 `ANativeWindow` 绑定给 `XComponent` 的 SurfaceID 即可。
* **配置参数对齐**：`KSOptions` 中的高级配置（如 `formatContextOptions["buffer_size"]`、`probesize`、seek 策略等），可以直接平移给鸿蒙版 ijkplayer 的 `setOption` 接口（格式、内容完全兼容）。

#### 📌 次选择：全量走鸿蒙版 `ijkplayer`
* **落地方式**：取消格式分流工厂，所有视频流统一由 ijkplayer 驱动。优点是播放器状态机（State）完全统一，上层 ViewModel 逻辑最简单，但在播放常规格式视频时，功耗会略高于系统原生播放器。

---

### 2. Kingfisher（图片加载与缓存）

#### 📌 最优选择：ArkUI 原生 `Image` 组件（常规场景首选）
* **落地方式**：鸿蒙 NEXT 的原生 `Image` 组件能力非常激进。它本身自带内存缓存，且原生支持 `alt`（占位图）属性以及图片加载完成后的渐变淡入动画。对于普通的列表、头像展示，原生组件的性能和内存控制是系统级最优的。

#### 📌 次选择：社区重量级平替 `@ohos/imageknife`（复杂场景首选）
* **落地方式**：如果项目涉及**大图查看器、严格的磁盘缓存大小限制（如上限 500MB，一键清理）、自定义图片处理器（高斯模糊/水印）、或者网络防盗链 Header 注入**，请通过 OHPM 引入 ImageKnife。其 API 结构、LRU 缓存管理以及 `BaseTransform` 变换接口与 Kingfisher 高度相似，迁移成本极低。

---

### 3. SWXMLHash（XML 解析）

#### 📌 最优选择：系统原生 `@kit.ArkTS` 中的 `xml.ConvertXML`（强烈推荐）
* **落地方式**：无需引入任何三方库。利用系统自带的 `convertToJSObject` 接口，可以将 XML 字符串一键拍平转换为标准的 ArkTS 嵌套 JavaScript 对象。
* **代码改动与防崩**：将 Swift 的中括号下标逻辑（如 `xml["books"]["book"][0]["title"]`）替换为 ArkTS 的对象属性访问。由于 Swift 中下标找不到节点会返回空对象而不崩溃，而 ArkTS 访问未定义属性会抛出异常，**务必在 ArkTS 端使用可选链操作符 `?.`（如 `result?.books?.book?.title?._text`）来确保安全**。

#### 📌 次选择：`fast-xml-parser`（社区移植版）
* **落地方式**：如果是极其复杂的旧版 XML 映射（如涉及大量 CDATA 块或特殊命名空间前缀），可以使用前端生态非常成熟的 `fast-xml-parser` 鸿蒙兼容版，完全在 ArkTS 纯脚本层处理，不依赖底层 C 库。

---

### 4. SMBClient（局域网文件共享）
结合项目中 `Browser` 模块的业务设计（上层隔离、拼出 `smb://` 送进播放器消费），此处的迁移是一个进行架构演进的绝佳契机。

#### 📌 最优选择：立项 “PrefetchProxy（本地 HTTP 代理）” 架构 + 纯 ArkTS 适配 `smb2`
* **落地方式**：
  1. **业务层（BrowserViewModel）**：使用纯 ArkTS/TS 移植前端生态的 `smb2` 库（利用鸿蒙原生的 `@kit.NetworkKit` 中的 Socket 能力），负责完成 `connect()`、`listDirectory()` 和 `download()` 核心业务，**彻底避开繁琐的 NDK 交叉编译**。
  2. **播放层（PrefetchProxy）**：在本地挂载一个轻量级 HTTP 代理服务（如 `http://127.0.0.1:port/smb_stream?id=media_id`），接管播放器的 Range 请求。
* **降维打击优势**：
  * **安全性大升级**：原本持久化在数据库（iOS SwiftData / 鸿蒙 RelationalStore）中的 `MediaItem.fileURL` 再也不需要包含带明文密码的 `smb://` 链接，只存纯净的逻辑 ID。账号密码由本地内存中的代理持有。
  * **播放器彻底解耦**：鸿蒙版的 ijkplayer 甚至**不需要额外编译 `libsmbclient` 选项**！它只需要像播放标准网络视频一样播放本地 HTTP 流即可。甚至常规 MP4 格式可以直接塞给系统的 `AVPlayer` 播放，一举打通系统引擎和三方引擎的协议壁垒。

#### 📌 次选择：NDK 交叉编译 `libsmbclient` 并塞入 ijkplayer 播放器
* **落地方式**：沿用 iOS 老架构。在编译鸿蒙版 ijkplayer 的 NDK 底层时，在 `config.sh` 中开启对 `libsmbclient` 或 `libdsm` 的交叉编译支持。`streamURL(for:)` 继续拼出带凭据的明文 `smb://` 字符串丢给播放器底层硬啃。
* **痛点**：需要使用鸿蒙 NDK 工具链（CMake/Clang）去重新交叉编译经典的 Samba C 库到 `arm64-v8a` 架构，且无法消除密码持久化的安全 Trade-off。

---

## 三、 迁移演进下一步行动指南

1. **统一数据持久化层**：将 iOS 的 `SwiftData` 替换为鸿蒙原生的 **`@kit.ArkData (RelationalStore)`** 关系型数据库。
2. **多线程安全配置**：由于 ArkTS 采用单线程模型（EventLoop），在重构 `listDirectory()` 或自定义 XML 解析等耗时/网络阻塞任务时，务必将执行体丢入鸿蒙的 **`TaskPool`（任务池）** 中异步执行，避免卡死 ArkUI 主线程。
3. **沙箱与权限声明**：SMB 局域网发现需在 `module.json5` 中声明 `ohos.permission.INTERNET` 权限；通过 `Browser` 下载的文件必须落地在当前应用的沙箱路径（如 `context.filesDir`），若需系统文件应用可见，需对接 `FileShare` 服务。