---
name: ipad-adaptation
description: Guide the agent to incrementally adapt the Vanmo iOS app for iPad, covering size-class-aware layouts, NavigationSplitView/sidebar, multi-column grids, multitasking (Split View / Stage Manager), pointer & keyboard support, and orientation handling, with one feature module per iteration ending in tests, commit, and push. Use when the user asks to adapt or optimize the app for iPad; mentions iPad 适配、大屏适配、分屏、Split View、Stage Manager、横屏、Sidebar、NavigationSplitView、size class、universal app、iPad 多列布局、iPad 键盘快捷键、iPad 指针 / 悬停; or asks to "逐个页面适配 iPad".
---

# Vanmo iPad 适配 Skill

引导代理以「逐个 Feature 模块」的方式把 Vanmo 适配到 iPad，每一轮都走「现状检测 → 设计 → 实现 → 测试 → commit → push → 暂停等待」的闭环。严禁一次会话里跨多个模块批量改 UI。

## 模块清单（按推进顺序）

| # | 模块 | 关键文件 | 重点 |
|---|------|----------|------|
| 1 | App 壳（Tab/根布局） | `App/ContentView.swift`、`App/VanmoApp.swift` | iPad 上的 sidebar / NavigationSplitView 抉择 |
| 2 | Library 媒体库 | `Features/Library/Views/*` | 多列网格、Hero 卡片、SecondFloor、详情页 |
| 3 | Browser/Connections | `Features/Browser/Views/*` | 列表 + 详情双栏、Add 表单 popover |
| 4 | Search | `Features/Search/Views/*` | 结果网格、键盘搜索、`.searchable` 行为 |
| 5 | Settings | `Features/Settings/Views/*` | 双栏分类页、Form 宽度收敛 |
| 6 | Player | `Features/Player/Views/*` | 横竖屏、控件密度、键盘/外接控制 |
| 7 | Shared 组件 | `Shared/Components/*` | `PosterCard`、`BackdropHeader`、`EmptyStateView` 的尺寸适配 |
| 8 | 多任务与生命周期 | `App/VanmoApp.swift`、`Resources/Info.plist` | Split View、Stage Manager、状态保留、键盘快捷键 |

> 在沟通中按编号引用模块，例如「正在做 #2 Library」。

## 工作模式：单模块闭环

每次会话只推进一个模块。开始前确认目标编号，结束前 commit + push 并停下来等用户决定下一个。

```
[选择模块 N]
  └── 1. 现状检测
  └── 2. 设计与确认
  └── 3. 实现
  └── 4. 测试 Gate（至少 iPhone + 一种 iPad 横竖屏）
  └── 5. Git Gate（commit + push）
  └── 6. 暂停 → 报告 → 等用户确认 → 才进入 N+1
```

## 1. 现状检测（必做）

动手前完成下列检测并写在回复里：

1. 用 Grep 在 `Vanmo/` 内统计目标模块当前的「iPhone-only 信号」：
   - `horizontalSizeClass` 是否已用、用在哪些 View
   - `UIDevice.current.userInterfaceIdiom`、`isIPad`、`@Environment(\.verticalSizeClass)`
   - 写死的 `frame(width:)` / `frame(maxWidth: 414)` / `padding(.horizontal, 16)` 等 iPhone 视觉常量
   - `TabView`、`NavigationStack`、`NavigationSplitView`、`fullScreenCover`、`.sheet` 用法
   - `LazyVStack` / `List` / `LazyVGrid` 的占比
2. 跑一遍 `xcodebuild` 编译目标，确认基线无报错（见 §4）。
3. 给出三选一结论：**完全没适配 / 部分适配（缺哪些）/ 已基本完成需要补强**。
4. 列出本模块在 iPad 上当前会出现哪些可视/交互问题（例如「列表只占左半屏」、「Hero 卡过宽」、「TabView 在 iPad 显示成 sidebar 但 sidebar 顶部没标题」）。

## 2. 设计与确认

实现前先写一份本模块的「适配方案表」：

| 决策点 | 选项 | 选择 | 理由 |
|---|---|---|---|
| 顶层导航 | NavigationStack vs NavigationSplitView | … | … |
| 列表→详情 | push vs 双栏 detail | … | … |
| 网格列数 | 固定 vs `GridItem(.adaptive(minimum:))` | … | … |
| 模态呈现 | `.sheet` vs `.popover` vs `.fullScreenCover` | … | … |
| 安全区/边距 | iPhone 16 vs iPad 24/32 | … | … |

约束：

- **优先保留现有 iPhone 体验**：iPad 适配不能让 iPhone 上出现回归；如果方案会改动 iPhone 的视觉/交互，**停下来用 AskQuestion 确认**。
- **iOS 17+ API 优先**：项目最低 iOS 17，可使用 `NavigationSplitView`、`@Observable`、`ContentUnavailableView`、`presentationDetents`、`scrollTargetBehavior` 等。
- **Universal app**：项目 `TARGETED_DEVICE_FAMILY = "1,2"` 已配置，禁止改成 iPad-only 或 iPhone-only。
- **不引入新依赖**：iPad 适配本身不应新增第三方包；如确需引入，先在回复里列出包名/版本/许可并停下确认。
- **不破坏播放链路**：`Core/Player/Prefetch/*`、`PlayerEngine`、`KSPlayerEngine` 不属于 UI 适配范围，禁止顺手重构。

如果存在多个合理方案（例如根布局是用 `TabView` + iPad 自动 sidebar，还是显式 `NavigationSplitView` 重写），**用 AskQuestion 让用户选**，不要替用户拍板。

## 3. 实现规范

### 3.1 size class 与设备判断

- 优先用 `@Environment(\.horizontalSizeClass)`，少用 `UIDevice.current.userInterfaceIdiom`。
- 把「是否走宽屏布局」收敛成单一 computed property，避免散落：

```swift
@Environment(\.horizontalSizeClass) private var hSizeClass

private var isRegularWidth: Bool { hSizeClass == .regular }
```

- iPad 竖屏 + Split View 1/3 时 `hSizeClass == .compact`，**必须把这个场景当作 iPhone 来兼容**，不要假设「iPad 一定是 regular」。
- 真要判断设备本体（例如 Plex/Emby header 里的 `X-Plex-Device`），保留现有 `UIDevice.current.model`，这是协议层需要的元数据，不是 UI 适配。

### 3.2 自适应布局

- 列表/卡片优先用 `LazyVGrid` + 自适应列：

```swift
private var columns: [GridItem] {
    [GridItem(.adaptive(minimum: isRegularWidth ? 180 : 110), spacing: 16)]
}
```

- 容器最大宽度限制，避免 iPad 横屏文本撑到 1366：

```swift
.frame(maxWidth: 760, alignment: .leading)   // 长文本/表单
.frame(maxWidth: .infinity)                   // 网格/海报墙
```

- 间距用 `dynamicSpacing`：iPhone 16、iPad 24/32；不要直接 `padding(16)` 一把梭。
- `Form` 在 iPad 上自带「居中收敛」，无需手动包 `ScrollView`。

### 3.3 导航结构

| 模块 | 推荐结构 |
|---|---|
| 根容器 | iPhone：`TabView`；iPad 视用户决策可保留 `TabView`（iOS 17+ 自动 sidebar）或换 `NavigationSplitView` |
| Library / Browser 列表→详情 | iPad regular：双栏 `NavigationSplitView(sidebar:detail:)`；compact：fallback 到 `NavigationStack` push |
| 设置 | iPad regular：`NavigationSplitView` 左分类右内容；compact：`NavigationStack` |

切换结构时用同一个根 View 内部分支，**不要在外层 `if` 切换 `NavigationStack` / `NavigationSplitView`**（会引发状态丢失）。推荐用 `ViewThatFits` 或在 split view 内根据 size class 调整 `columnVisibility`。

### 3.4 模态与浮层

| 场景 | iPhone | iPad |
|---|---|---|
| 添加连接、轨道选择 | `.sheet` 全宽 | `.sheet` + `.presentationDetents([.medium, .large])` 或 `.popover` |
| 播放器轨道/章节 | `.sheet` medium | iPad 横屏建议 `.popover`，从控件锚定 |
| 速度/比例选择 | 自定义浮层（PlayerView 现状） | 锁定到对应按钮的 `popover(attachmentAnchor:)` |
| 强制全屏 | `.fullScreenCover` | 同上，但在 Stage Manager 下要测试不会拉伸 |

`.sheet` 在 iPad 默认 form sheet 居中，不要再手动 `frame(width:)` 写死。

### 3.5 输入与辅助

iPad 模块完成时，按需补这些（不要求一次全部到位，但要在 commit message 里说明覆盖到哪一档）：

- 键盘快捷键：用 `keyboardShortcut(_:modifiers:)` 给「播放/暂停」「快进 10s」「下一集」等加快捷键，文档化在该模块的 PR 描述里。
- 指针悬停：列表/卡片加 `.hoverEffect(.lift)` 或 `.contentShape` + `.onHover`。
- 拖拽：海报/列表项可考虑 `.draggable` / `.dropDestination`，但这是 enhancement，不是必要项。
- Focus / `@FocusState`：表单页支持 Tab 键跳转。

### 3.6 多任务与方向

- iPad 默认四方向都开（`Info.plist` 的 `UISupportedInterfaceOrientations~ipad` 已配置），保持现状，不要改成单方向。
- Split View 1/3 / 1/2 / 2/3 必须能正常显示（按 §3.1 当 compact 兼容）。
- Stage Manager 自由窗口下，`UIScreen.main.bounds` 不可信，必须用 `GeometryReader` 或 size class 决策。
- 旋转时不要丢失播放进度、列表滚动位置、表单输入；必要时把状态从 View 提升到 ViewModel。

## 4. 测试 Gate（不通过禁止提交）

每个模块都要给出可复现的验证证据，至少满足以下三档**全部通过**：

### 4.1 编译

```bash
xcodebuild build \
  -project Vanmo.xcodeproj \
  -scheme Vanmo \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```

编译通过是最低门槛，不算测试通过。任何编译警告 / SwiftLint 报错当场修，不留给下一个模块。

### 4.2 多设备运行

至少在以下三档模拟器上跑当前模块：

1. **iPhone 15 / 16**（Compact x Regular）—— 防回归基线
2. **iPad (10th gen)** 或 **iPad mini**（Regular x Regular，竖屏 + 横屏）
3. **iPad Pro 12.9"**（Regular x Regular，横屏 + Split View 1/2）

可以用：

```bash
xcrun simctl list devices available | rg -i 'iPhone|iPad'
xcodebuild -project Vanmo.xcodeproj -scheme Vanmo \
  -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' \
  build
```

### 4.3 视觉证据

按模块附上必查截图（贴在回复里或描述清楚状态）：

- iPhone 竖屏（基线，对比未回归）
- iPad 竖屏全屏
- iPad 横屏全屏
- iPad 横屏 Split View 1/2（与另一 app 并排）
- 如涉及 Player：横屏播放控件 + 字幕显示一张

测试失败时禁止 `git add`，回到第 3 步修复。

## 5. Git Gate（commit + push）

测试 Gate 通过后按 `git-workflow` skill 完成 commit & push：

1. `git status` + `git diff` 复核，只包含本模块相关变更；与 iPad 适配无关的重构必须留到独立提交。
2. 提交信息使用 Conventional Commits，scope 为模块名：

```
feat(ipad): adapt <module> for iPad regular size class

- 切换到 NavigationSplitView / 多列网格 / popover ...
- 涵盖 iPad mini / iPad Pro 12.9 横竖屏
- 不影响 iPhone 现有体验

Module: #2 Library
```

   常用 scope：`ipad`（默认）、可叠加细分 `ipad-library`、`ipad-player`。

3. 推送到当前分支：

```bash
git push origin <current-branch>
```

   - 默认推送当前分支，**禁止 `--force`**。
   - 如当前分支没有远程跟踪，使用 `git push -u origin <branch>`。

4. 推送成功后立即在回复里给出：模块编号、提交 hash（`git log -1 --oneline`）、改动文件数、覆盖到的设备清单、键盘快捷键 / 悬停 / 多任务覆盖度。

## 6. 暂停与交接

push 完成后**必须停下来**：

- 不要自动开始下一个模块，即使用户最初列了多个。
- 用 AskQuestion 或简短文字询问：「#N 已完成并 push，是否进入 #N+1？或调整下一个目标？」
- 用户明确回答后才能开始新一轮闭环。

## 安全与红线

- 一次提交只对应一个模块；禁止把多个模块的 iPad 改造塞进同一次 commit。
- 测试不通过（任意一档设备）禁止 commit，更禁止 push。
- 不允许：`git commit --amend` 已推送的提交、`git push --force`、`git reset --hard`。
- 禁止改动 `Core/Player`、`Core/Network` 协议层、`Core/Storage` 的业务逻辑，只允许 UI 层调整；这些层有独立 skill（`infuse-protocol-support`、播放器相关）。
- 禁止把 universal app 改成 iPhone-only 或 iPad-only（不要动 `TARGETED_DEVICE_FAMILY`）。
- 禁止删除 `LSRequiresIPhoneOS`、`UIRequiredDeviceCapabilities` 等已有 Info.plist key，除非用户明确要求。
- 禁止引入与 iPad 适配无关的 SDK；UI 适配应纯 SwiftUI/UIKit。
- iPad 适配过程中**严禁**修改任何凭据存储、网络协议鉴权流程。

## 推荐起步顺序（可被用户覆盖）

如果用户没指定先做哪个，按「ROI ↑、风险 ↓」推荐：

1. #1 App 壳（先把 iPad 上整体导航形态定下来）
2. #2 Library（视觉收益最大）
3. #7 Shared 组件（让后续模块复用收敛后的卡片/Header）
4. #3 Browser/Connections
5. #4 Search
6. #5 Settings
7. #6 Player（最复杂，依赖前面所有模块的基础组件）
8. #8 多任务与生命周期（收尾，加键盘快捷键、Split View 体验、状态保留）

只是建议；若用户指定顺序，**完全按用户的来**。

## 参考代码片段

### Adaptive 双栏

```swift
struct LibraryRoot: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var selection: MediaItem?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(hSizeClass == .regular ? .all : .detailOnly)) {
            LibraryView(selection: $selection)
        } detail: {
            if let item = selection {
                MediaDetailView(item: item)
            } else {
                ContentUnavailableView("选择一项", systemImage: "rectangle.stack")
            }
        }
    }
}
```

### Adaptive 网格

```swift
private var posterColumns: [GridItem] {
    let minWidth: CGFloat = isRegularWidth ? 160 : 104
    return [GridItem(.adaptive(minimum: minWidth), spacing: 16)]
}

LazyVGrid(columns: posterColumns, spacing: 20) {
    ForEach(items) { PosterCard(item: $0) }
}
.padding(.horizontal, isRegularWidth ? 24 : 16)
```

### iPad popover、iPhone sheet

```swift
.modifier(AdaptivePresentation(isPresented: $showPicker) { picker })

struct AdaptivePresentation<C: View>: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Binding var isPresented: Bool
    let content: () -> C

    func body(content base: Content) -> some View {
        if hSizeClass == .regular {
            base.popover(isPresented: $isPresented) { content() }
        } else {
            base.sheet(isPresented: $isPresented) {
                content().presentationDetents([.medium, .large])
            }
        }
    }
}
```
