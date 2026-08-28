---
name: figma-design-fidelity
description: Enforce that every UI change in the Vanmo iOS/macOS app strictly replicates the correct platform-specific Figma design source of truth, and that any missing screen is first designed in Figma before being coded. Use whenever the user asks to build, modify, or restyle any UI / 界面 / 页面 / 组件 / 视图 / SwiftUI View, mentions 设计稿 / Figma / 还原 / 复刻 / 高保真 / 图标 / icon / SF Symbol / 动效 / 动画 / loading 动画, or starts UI work where a design may or may not exist yet.
---

# Vanmo Figma 设计还原 Skill

> 核心约束（用户原话，必须遵守）：
> 该项目的设计稿在 Figma 上，所有设计 UI 的修改都要严格按照设计稿完整复刻，如果设计稿上没有设计图则需要现在 Figma 上生成设计图再实现代码。

## Figma 设计源

- 先判断本次 UI 修改目标平台：iOS 只使用 iOS 设计稿，macOS 只使用 macOS 设计稿；不要把一个平台的页面默认当作另一个平台的设计真相来源。
- 如果目标平台对应页面缺失，走下方「设计稿不存在」流程，先在对应平台的 Figma 文件中补设计。

### iOS 设计稿

- 项目：**Vanmo iOS**
- `fileKey`：`miM6YTQAnerz6SgkkYZMjo`
- 页面 PageName：
  - `MediaDetail`（媒体详情）：[https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=203-2](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=203-2)
  - `LibraryHome`（媒体库首页）：[https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=295-6](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=295-6)
  - `File`（文件浏览）：[https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=317-80](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=317-80)
  - `Favorites`（收藏列表）：[https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=322-192](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=322-192)
  - `Icons`（图标合集）：[https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=424-2](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=424-2)
  - `Download` (下载页面): [https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=455-3](https://www.figma.com/design/miM6YTQAnerz6SgkkYZMjo/Vanmo-Ios?node-id=455-3)

### macOS 设计稿

- 项目：**Vanmo macOS**
- `fileKey`：`O75W1XT1Q0btSrepDwEx39`
- 页面 PageName：
  - `LibraryHome`（媒体库首页）：`https://www.figma.com/design/O75W1XT1Q0btSrepDwEx39/Vanmo-MacOS?node-id=0-1`
  - `MediaDetail`（媒体库首页）：`https://www.figma.com/design/O75W1XT1Q0btSrepDwEx39/Vanmo-MacOS?node-id=7-1126`
  - `Player`（媒体库首页）：`https://www.figma.com/design/O75W1XT1Q0btSrepDwEx39/Vanmo-MacOS?node-id=7-1536`

任何 UI 改动开始前，先把对应页面/组件的 Figma 节点定位出来（节点 URL 形如 `...?node-id=1-23`，调用工具时把 `node-id` 的 `-` 转成 `:`）。

## 铁律

1. **Figma 是唯一设计真相来源**：UI 的布局、间距、字号、字重、颜色、圆角、阴影、图标、状态，全部以设计稿为准，不得凭空发挥或"差不多就行"。
2. **先有设计，后有代码**：实现任何 UI 前，必须已存在对应 Figma 设计图。
3. **缺图先在 Figma 上补**：如果设计稿里没有该界面/组件，先在 Figma 上生成设计图，确认后再写代码。
4. **完整复刻**：复刻要覆盖全部视觉细节与交互状态（默认 / 选中 / 禁用 / 加载 / 空 / 错误等），不要只还原"主视觉"。
5. **优先复用设计系统**：实现时优先映射到项目已有的 token / 组件（如 `Color+Vanmo`、共享组件），而不是硬编码新的魔法数值。

## 工作流程

### A. 设计稿已存在 → 高保真还原（Figma → 代码）

复制此清单并逐项推进：

```
还原进度：
- [ ] 1. 在 Figma 中定位目标节点，拿到 node-id
- [ ] 2. 读取设计上下文（get_design_context）+ 截图（get_screenshot）
- [ ] 3. 提取规格：布局/间距/字号字重/颜色/圆角/阴影/图标/各状态
- [ ] 4. 映射到项目已有 token 与共享组件，缺失再新增
- [ ] 5. 实现/修改 SwiftUI 代码
- [ ] 6. 与设计稿逐项比对，修正偏差直到完整复刻
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
- [ ] 3. 在 Figma 上生成设计图（use_figma / generate_figma_design），复用设计系统，而非凭空造组件
- [ ] 4. 把生成结果反馈给用户确认（必要时迭代）
- [ ] 5. 确认通过后，再回到流程 A 按设计稿实现代码
```

> 调用 `use_figma` 前必须先加载 `figma-use` skill；做整页/弹窗/多区块布局前加载 `figma-generate-design` skill。详见这些 skill 的强制前置要求。

## 验收标准

UI 改动完成的判定：与对应 Figma 节点逐项核对，布局结构、间距、字体、颜色、圆角、阴影、图标、动效与所有交互状态都与设计稿一致；新建组件已尽量复用项目 token；无未还原的设计细节。

## 反模式（禁止）

- ❌ 没看设计稿就直接写/改 UI。
- ❌ 设计稿缺失却直接"自由发挥"出一套界面，而不先在 Figma 补图确认。
- ❌ 只还原主视觉，忽略选中 / 禁用 / 加载 / 空 / 错误等状态。
- ❌ 硬编码魔法数值，绕过既有设计 token 与共享组件。
- ❌ 凭空画图标，或引入与设计稿不一致的图标资源。
- ❌ Figma 用一个图标、代码却换成另一个图标，导致设计与实现不一致。
- ❌ 一个界面里混用线性/填充等不同风格的图标集。
- ❌ SF Symbols 已有等价图标却仍引入外部 SVG，徒增维护成本。
