---
name: figma-design-fidelity
description: Enforce that every UI change in the Vanmo iOS app strictly replicates the Figma design source of truth, that any missing screen is first designed in Figma before being coded, that icons are sourced via the better-icons MCP (Iconify), and that motion/Lottie animations are authored via the lottiefiles-creator MCP — all fused into both the Figma design and the SwiftUI project. Use whenever the user asks to build, modify, or restyle any UI / 界面 / 页面 / 组件 / 视图 / SwiftUI View, mentions 设计稿 / Figma / 还原 / 复刻 / 高保真 / 图标 / icon / SF Symbol / 动效 / 动画 / Lottie / loading 动画, or starts UI work where a design, icon, or animation may or may not exist yet.
---

# Vanmo Figma 设计还原 Skill

> 核心约束（用户原话，必须遵守）：
> 该项目的设计稿在 Figma 上，所有设计 UI 的修改都要严格按照设计稿完整复刻，如果设计稿上没有设计图则需要现在 Figma 上生成设计图再实现代码。

## Figma 设计源

- 项目：**Vanmo**
- 地址：[https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/TIDE?node-id=0-1&t=VPyaJ6BK9pikK3sh-1](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/TIDE?node-id=0-1&t=VPyaJ6BK9pikK3sh-1)
- `fileKey`：`miM6YTQAnerz6SgkkYZMjo`

任何 UI 改动开始前，先把对应页面/组件的 Figma 节点定位出来（节点 URL 形如 `...?node-id=1-23`，调用工具时把 `node-id` 的 `-` 转成 `:`）。

## 铁律

1. **Figma 是唯一设计真相来源**：UI 的布局、间距、字号、字重、颜色、圆角、阴影、图标、状态，全部以设计稿为准，不得凭空发挥或"差不多就行"。
2. **先有设计，后有代码**：实现任何 UI 前，必须已存在对应 Figma 设计图。
3. **缺图先在 Figma 上补**：如果设计稿里没有该界面/组件，先在 Figma 上生成设计图，确认后再写代码。
4. **完整复刻**：复刻要覆盖全部视觉细节与交互状态（默认 / 选中 / 禁用 / 加载 / 空 / 错误等），不要只还原"主视觉"。
5. **优先复用设计系统**：实现时优先映射到项目已有的 token / 组件（如 `Color+Vanmo`、共享组件），而不是硬编码新的魔法数值。
6. **图标走 better-icons**：需要图标时（无论是在 Figma 补设计图，还是在代码里落地），统一通过 **better-icons MCP**（Iconify 200+ 图标库）检索/获取，不要凭空画图标，也不要从其它渠道随意找图。落地到 iOS 时遵循下方「图标来源与落地」规则。
7. **动效走 lottiefiles-creator**：需要 Lottie 动画 / 动效 / 加载动画 / 过场 / 微交互时，统一通过 **lottiefiles-creator MCP** 制作动画并导出 Lottie JSON，再同时融合到 Figma 设计稿与 SwiftUI 代码，不要手搓 JSON 或临时找来路不明的动画文件。落地遵循下方「动效与 Lottie 动画」规则。

## 工作流程

### A. 设计稿已存在 → 高保真还原（Figma → 代码）

复制此清单并逐项推进：

```
还原进度：
- [ ] 1. 在 Figma 中定位目标节点，拿到 node-id
- [ ] 2. 读取设计上下文（get_design_context）+ 截图（get_screenshot）
- [ ] 3. 提取规格：布局/间距/字号字重/颜色/圆角/阴影/图标/各状态
- [ ] 4. 映射到项目已有 token 与共享组件，缺失再新增
- [ ] 5. 图标落地：能用 SF Symbol 就用；设计稿图标系统没有时，用 better-icons 取 Iconify SVG 落地到 Assets.xcassets（见下章）
- [ ] 6. 动效落地：设计稿/需求含动画时，用 lottiefiles-creator 制作并导出 Lottie JSON，落地到代码（见下章）
- [ ] 7. 实现/修改 SwiftUI 代码
- [ ] 8. 与设计稿逐项比对，修正偏差直到完整复刻
```

工具用法：

- 用 `get_design_context`（传入 `fileKey` + `nodeId`）拿参考代码与设计提示，这是**参考**而非最终代码，需适配本项目 SwiftUI 技术栈与约定。
- 用 `get_screenshot` 做视觉真相比对。
- 命中 Code Connect / 设计注解 / 设计 token 时，按其指引落地，不要绕过。

### B. 设计稿不存在 → 先在 Figma 生成设计图（代码/需求 → Figma → 代码）

```
补设计进度：
- [ ] 1. 确认该界面/组件在 Figma 中确实缺失
- [ ] 2. search_design_system 找可复用组件 / 变量 / 样式
- [ ] 3. 用 better-icons 选好该界面需要的图标（recommend_icons / search_icons），确定统一风格与图标集
- [ ] 4. 若界面含动效，用 lottiefiles-creator 制作 Lottie 动画并导出 JSON（先 get_rules + get_api_doc）
- [ ] 5. 在 Figma 上生成设计图（use_figma / generate_figma_design），复用设计系统，插入选定的图标 SVG，并标注/嵌入动效占位，而非凭空造组件/图标/动画
- [ ] 6. 把生成结果反馈给用户确认（必要时迭代）
- [ ] 7. 确认通过后，再回到流程 A 按设计稿实现代码
```

> 调用 `use_figma` 前必须先加载 `figma-use` skill；做整页/弹窗/多区块布局前加载 `figma-generate-design` skill。详见这些 skill 的强制前置要求。

## 图标来源与落地（better-icons MCP）

图标统一通过 **better-icons** MCP（服务器标识 `user-better-icons`，封装 Iconify 200+ 图标库）获取，再按下面规则同时融合到「Figma 设计稿」与「SwiftUI 项目」。

### 工具速查

- `recommend_icons`（use_case + style）：按使用场景拿推荐图标，适合"导航栏/设置按钮/播放控制"等场景化选图。
- `search_icons`（query + 可选 prefix/category）：关键词搜图，`prefix` 锁定图标集（如 `lucide`、`mdi`、`heroicons`）保证整套风格一致。
- `get_icon` / `get_icons`（icon_id，可传 color/size）：拿单个/批量图标的 SVG 源码，`icon_id` 形如 `lucide:home`。
- `find_similar_icons`（icon_id）：同一图标换风格（solid/outline）或换图标集时用。
- `scan_project_icons` / `list_collections` / `get_icon_preferences`：查已落地图标、可用图标集、已学习的偏好图标集，避免重复与风格漂移。

> 注意：`sync_icon` 的 framework 只支持 react/vue/svelte/solid/svg，**不适用于本 SwiftUI 项目**，iOS 落地一律用 `get_icon` 拿 SVG 后按下方手动落地。

### 选图原则

1. **SF Symbols 优先**：本项目图标现状几乎全是 `Image(systemName:)`。如果某图标在 SF Symbols 中有等价且符合设计稿的符号，直接用 SF Symbol，不必引入外部图标。
2. **系统缺失才用 better-icons**：仅当设计稿要求的图标 SF Symbols 没有合适等价物时，才从 better-icons 取 Iconify 图标。
3. **同套风格统一**：一个界面/一类功能的图标尽量来自同一图标集（用 `prefix` 锁定，或先 `get_icon_preferences` 看偏好集），避免线性/填充混用。
4. **Figma 与代码用同一图标**：在 Figma 设计稿里放的图标，必须和代码落地的图标是同一个 `icon_id`，保证设计与实现一致。

### 融合到 Figma 设计稿（流程 B）

- 先用 `recommend_icons` / `search_icons` 选定图标与风格，记下 `icon_id`。
- 用 `get_icon` 取 SVG，在 `use_figma` 生成设计图时把该 SVG 作为图标节点插入对应位置（复用设计系统的尺寸/颜色 token）。
- 把选定的 `icon_id` 记录下来，供后续代码落地复用。

### 融合到 SwiftUI 项目（流程 A）

iOS 落地路径：把 Iconify SVG 作为**矢量 imageset** 放进 `Vanmo/Resources/Assets.xcassets`，再以 template 模式着色调用。

1. `get_icon`（或 `get_icons` 批量）拿到 SVG，`color` 用 `currentColor`，让颜色交给 SwiftUI 的 `.foregroundStyle` 控制。
2. 在 `Vanmo/Resources/Assets.xcassets` 下新建 `<IconName>.imageset/`，放入 `<IconName>.svg` 与 `Contents.json`，并开启矢量保留：

```json
{
  "images": [
    { "filename": "IconName.svg", "idiom": "universal" }
  ],
  "info": { "author": "xcode", "version": 1 },
  "properties": {
    "preserves-vector-representation": true,
    "template-rendering-intent": "template"
  }
}
```

3. 在 SwiftUI 中调用并用项目 token 着色：

```swift
Image("IconName")
    .renderingMode(.template)
    .foregroundStyle(Color.vanmoPrimary) // 用 Color+Vanmo 中的 token
```

4. 落地前先 `scan_project_icons`（或查看 `Assets.xcassets`）确认未重复；命名与设计稿图标语义一致（如 `playFilled`、`downloadOutline`）。

> 真机调试若图标显示异常，按 `ios-device-debug-logs` 规则，在本地加 `Image` 相关调试 `print` 让我从 Xcode Console 复制，不要引入远程日志。

## 动效与 Lottie 动画（lottiefiles-creator MCP）

需要动效时（加载动画 / 空状态动画 / 过场 / 点赞收藏等微交互 / 播放器控件动效），统一用 **lottiefiles-creator** MCP（服务器标识 `user-lottiefiles-creator`）在 LottieFiles Creator 里制作动画，导出 Lottie JSON，再同时融合到 Figma 设计稿与 SwiftUI 代码。

### 强制前置（每个会话至少一次）

调用 `run_script` 写脚本制作动画**之前必须**先：

1. `get_api_doc`：分页读取 Creator API 的 TS 类型定义，从 `page=1` 开始**逐页读完所有页**。该 API 独特，不能凭常识猜，否则会 TypeError。
2. `get_rules`：获取脚本约定（如图层顺序等影响视觉正确性的规则）。

读完后再用 `run_script` 执行 JS 操作动画（通过全局 `creator` 对象创建/编辑图层、形状、关键帧、颜色等），用 `console.log()` 输出结果。

> 重要限制（实测）：该 MCP **只能制作/编辑动画，无法用脚本导出 Lottie JSON**（`creator`/`scene` 没有 export/toLottie，`scene.toJSON()` 只返回 `{id,type}`）。导出必须在 **LottieFiles Creator 应用内手动 `Export → Lottie JSON`**，保存到 `Vanmo/Resources/`。先用 `run_script` 探测 `creator.activeScene` 确认应用已连接，再开始制作。

### 制作流程

```
动效进度：
- [ ] 1. 明确动效需求：触发时机、时长、循环方式、尺寸、配色（与设计 token 一致）
- [ ] 2. get_api_doc（读完所有页）+ get_rules
- [ ] 3. run_script 制作/调整动画，迭代到符合设计意图（颜色用项目 token 对应 RGB）
- [ ] 4. 在 LottieFiles Creator 应用内手动导出 Lottie JSON 到 Vanmo/Resources/（脚本无法导出）
- [ ] 5. 同步到 Figma 设计稿（占位 + 标注）与 SwiftUI 代码
- [ ] 6. 与设计稿/预期逐项比对动效细节
```

### 选型原则

1. **先确认是否真需要 Lottie**：简单的状态切换、位移、缩放、透明度动画优先用 SwiftUI 原生（`withAnimation` / `.transition` / `matchedGeometryEffect`），更轻量、可维护。
2. **复杂矢量动效才上 Lottie**：多图层、路径变形、品牌化插画类动画再用 lottiefiles-creator。
3. **风格与设计系统一致**：动画配色、线宽、圆角等沿用项目 token 与图标风格，避免突兀。
4. **Figma 与代码用同一份动画**：设计稿里标注/嵌入的动效，与代码里落地的 Lottie JSON 必须是同一份产物。

### 融合到 Figma 设计稿（流程 B）

- Figma 设计文件本身不播放 Lottie，因此在设计稿中以**关键帧静帧 + 文字标注**表达动效：标注动画来源（同一 Lottie 产物）、触发时机、时长、循环方式、尺寸。
- 如需在 Figma 内预览，可借助 LottieFiles 的 Figma 插件嵌入动画预览，但最终交付仍以导出的 Lottie JSON 为准。

### 融合到 SwiftUI 项目（流程 A）

iOS 用 **lottie-ios**（Airbnb）渲染 Lottie JSON。

1. 依赖：本项目用 Swift Package Manager（已集成 Kingfisher / KSPlayer 等）。通过 SPM 添加 `https://github.com/airbnb/lottie-ios.git`（target 勾选 Vanmo），首次集成需提示我在 Xcode 中确认。
2. 资源：把导出的 `<name>.json` 放进 `Vanmo/Resources/`（与现有资源同级），确保已加入 app target 的 bundle。
3. SwiftUI 调用（lottie-ios 提供原生 `LottieView`）：

```swift
import Lottie

LottieView(animation: .named("loadingSpinner"))
    .playing(loopMode: .loop)
    .frame(width: 80, height: 80)
```

4. 命名与设计稿动效语义一致（如 `loadingSpinner`、`favoriteBurst`、`emptyBox`）；落地前确认 `Resources/` 下未重复。
5. 依赖尚未加好时，用 `#if canImport(Lottie)` 守卫封装组件，未集成时回退到系统等价控件（如 `ProgressView`），保证项目始终可编译：

```swift
#if canImport(Lottie)
import Lottie
#endif

struct LoadingIndicatorView: View {
    var body: some View {
        #if canImport(Lottie)
        LottieView(animation: .named("loadingSpinner")).playing(loopMode: .loop)
        #else
        ProgressView().tint(Color.vanmoPrimary)
        #endif
    }
}
```

> 真机调试若动画不播放/卡顿，按 `ios-device-debug-logs` 规则在本地加 `[Debug][Lottie]` 前缀的 `print`（动画名、是否找到资源、loopMode、尺寸）让我从 Xcode Console 复制，不要引入远程日志或额外观测 SDK。

## 验收标准

UI 改动完成的判定：与对应 Figma 节点逐项核对，布局结构、间距、字体、颜色、圆角、阴影、图标、动效与所有交互状态都与设计稿一致；新建组件已尽量复用项目 token；图标均来自 SF Symbols 或 better-icons（Iconify），且 Figma 与代码使用同一图标、风格统一、已正确落地（SF Symbol 或 `Assets.xcassets` 矢量 imageset）；动效（如有）由 lottiefiles-creator 制作，Figma 与代码使用同一 Lottie 产物并通过 lottie-ios 正确播放；无未还原的设计细节。

## 反模式（禁止）

- ❌ 没看设计稿就直接写/改 UI。
- ❌ 设计稿缺失却直接"自由发挥"出一套界面，而不先在 Figma 补图确认。
- ❌ 只还原主视觉，忽略选中 / 禁用 / 加载 / 空 / 错误等状态。
- ❌ 硬编码魔法数值，绕过既有设计 token 与共享组件。
- ❌ 凭空画图标，或从 better-icons 之外随意找图标资源。
- ❌ Figma 用一个图标、代码却换成另一个图标，导致设计与实现不一致。
- ❌ 一个界面里混用线性/填充等不同风格的图标集。
- ❌ SF Symbols 已有等价图标却仍引入外部 SVG，徒增维护成本。
- ❌ 手搓 Lottie JSON，或引入来路不明 / 与设计不符的动画文件。
- ❌ 不读 `get_api_doc` / `get_rules` 就写 Creator 脚本，导致 TypeError 或视觉错误。
- ❌ SwiftUI 原生动画就能搞定的简单动效，却硬上 Lottie。
- ❌ Figma 标注的动效与代码落地的 Lottie 产物不是同一份。

