---
name: media-library-ui
description: 媒体库功能页面的 UI 开发指南，涵盖"继续观看"二楼交互、分页器布局、海报主色提取动态背景、卡片阴影等。触发场景：用户提到"继续观看""二楼""分页器""主色提取""卡片阴影"或媒体库首页的 UI 开发任务。
---

# 媒体库 UI 开发指南

## 概览

本 skill 指导媒体库首页中以下 UI 特性的实现：

| 特性 | 说明 |
|------|------|
| 二楼交互 | "继续观看"区域采用类似微信下拉"二楼"的特殊布局 |
| 分页器 | 二楼内部使用分页器展示近期观看影剧及进度 |
| 动态背景 | 选中影剧时提取海报主色，背景跟随变化 |
| 卡片阴影 | 其他版块的影剧 item 卡片添加阴影 |

---

## 一、继续观看 — "二楼"交互

### 1.1 设计意图

"继续观看"不再与其他版块使用相同的横向滚动条，而是采用下拉触发的"二楼"沉浸式页面，使其在视觉上具有特殊地位。

### 1.2 交互流程

```
媒体库首页（正常状态）
    │
    ├─ 下拉超过阈值（≥120pt） → 进入二楼（继续观看页面）
    │                              ├─ 分页器展示影剧
    │                              ├─ 上滑或点击关闭 → 返回首页
    │                              └─ 点击影剧 → 进入详情/继续播放
    │
    └─ 正常滚动 → 浏览其他版块（最近添加、分类筛选等）
```

### 1.3 实现方案

文件：`Vanmo/Features/Library/Views/SecondFloorView.swift`（新建）

核心组件结构：

```swift
struct SecondFloorView: View {
    @Binding var isPresented: Bool
    let recentlyPlayed: [MediaItem]
    @State private var selectedIndex: Int = 0
    @State private var dominantColor: Color = .clear

    var body: some View {
        ZStack {
            // 动态背景层
            dominantColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: dominantColor)

            VStack(spacing: 0) {
                // 顶部拖拽指示条
                dragIndicator

                // 分页器内容
                secondFloorPager
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
```

#### 下拉触发机制

在 `LibraryView` 中使用 `GeometryReader` + `ScrollView` 偏移量检测：

```swift
// LibraryView 内
@State private var showSecondFloor = false
@State private var pullOffset: CGFloat = 0

// 在 ScrollView 外层包裹手势检测
.onChange(of: pullOffset) { _, newValue in
    if newValue > 120 && !showSecondFloor {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showSecondFloor = true
        }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
```

也可使用 `PreferenceKey` 采集 `ScrollView` 的内容偏移，当检测到顶部过度下拉时触发。

#### 关闭二楼

- **上滑手势**：`DragGesture` 上滑超过阈值关闭
- **关闭按钮**：顶部提供显式关闭入口
- **返回首页后重置**：`showSecondFloor = false`

### 1.4 集成到 LibraryView

文件：`Vanmo/Features/Library/Views/LibraryView.swift`

```swift
// libraryContent 中移除旧的 "继续观看" mediaSection
// 替换为二楼入口提示

// 在 LibraryView body 中叠加二楼
.fullScreenCover(isPresented: $showSecondFloor) {
    SecondFloorView(
        isPresented: $showSecondFloor,
        recentlyPlayed: viewModel.recentlyPlayed
    )
}
```

可选方案：也可不使用 `fullScreenCover`，而是 `ZStack` + `offset` 方式自行管理二楼的出入场动画，这样更灵活。

---

## 二、分页器布局

### 2.1 设计

二楼内部影剧使用 **水平分页器** 展示，每页一部影剧，居中显示：

- 海报大图（占页面主要区域）
- 影剧标题 + 年份
- 播放进度条 + 已观看时长/总时长
- "继续播放"按钮

### 2.2 实现

使用 `TabView` + `.tabViewStyle(.page)` 或自定义 `ScrollView` + `scrollTargetLayout`：

```swift
// SecondFloorView 内
private var secondFloorPager: some View {
    TabView(selection: $selectedIndex) {
        ForEach(Array(recentlyPlayed.enumerated()), id: \.element.id) { index, item in
            SecondFloorItemView(item: item)
                .tag(index)
        }
    }
    .tabViewStyle(.page(indexDisplayMode: .automatic))
    .onChange(of: selectedIndex) { _, newIndex in
        guard newIndex < recentlyPlayed.count else { return }
        extractDominantColor(from: recentlyPlayed[newIndex])
    }
}
```

**iOS 17+ 替代方案**：使用 `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` + `.scrollPosition(id:)` 实现更精细的分页控制。

### 2.3 单页内容视图

文件：`Vanmo/Features/Library/Views/SecondFloorItemView.swift`（新建）

```swift
struct SecondFloorItemView: View {
    let item: MediaItem

    var body: some View {
        VStack(spacing: 20) {
            // 海报（大尺寸，圆角 16pt）
            posterImage

            // 标题 + 年份
            VStack(spacing: 4) {
                Text(item.title)
                    .font(.title2.bold())
                if let year = item.year {
                    Text(year)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // 进度
            if let progress = item.playbackProgress, progress > 0 {
                ProgressView(value: progress)
                    .tint(.white)
                playbackTimeLabel
            }

            // 继续播放按钮
            Button("继续播放") { /* appState.play(item) */ }
                .buttonStyle(.borderedProminent)
                .tint(.white.opacity(0.2))
        }
        .padding(.horizontal, 40)
    }
}
```

### 2.4 页面指示器

`TabView` + `.page` 自带点状指示器。如需自定义样式，可叠加 `HStack` + `Circle` 自绘：

```swift
HStack(spacing: 8) {
    ForEach(0..<recentlyPlayed.count, id: \.self) { i in
        Circle()
            .fill(i == selectedIndex ? Color.white : Color.white.opacity(0.3))
            .frame(width: i == selectedIndex ? 8 : 6)
            .animation(.easeInOut(duration: 0.2), value: selectedIndex)
    }
}
```

---

## 三、海报主色提取 + 动态背景

### 3.1 颜色提取工具

文件：`Vanmo/Shared/Utilities/DominantColorExtractor.swift`（新建）

使用 Core Image 的 `CIAreaAverage` 滤镜从海报图片中提取主色调：

```swift
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

enum DominantColorExtractor {
    private static let context = CIContext()

    /// 从 UIImage 提取主色
    static func extractDominantColor(from image: UIImage) -> Color? {
        guard let ciImage = CIImage(image: image) else { return nil }

        let extent = ciImage.extent
        // 取图片中下部 1/3 区域（海报重点区域，避免大面积白色天空等干扰）
        let cropRect = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: extent.width,
            height: extent.height / 3
        )

        let filter = CIFilter.areaAverage()
        filter.inputImage = ciImage.cropped(to: cropRect)
        filter.extent = cropRect

        guard let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let color = Color(
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )

        // 降低亮度使其适合作为背景
        return color.opacity(0.85)
    }

    /// 从 URL 异步加载并提取主色
    static func extractDominantColor(from url: URL?) async -> Color {
        guard let url else { return .black.opacity(0.9) }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let uiImage = UIImage(data: data) else { return .black.opacity(0.9) }
            return extractDominantColor(from: uiImage) ?? .black.opacity(0.9)
        } catch {
            return .black.opacity(0.9)
        }
    }
}
```

### 3.2 在二楼中使用

```swift
// SecondFloorView 内
private func extractDominantColor(from item: MediaItem) {
    Task {
        let color = await DominantColorExtractor.extractDominantColor(from: item.posterURL)
        withAnimation(.easeInOut(duration: 0.5)) {
            dominantColor = color
        }
    }
}
```

首次进入时自动提取第一个影剧的主色：

```swift
.onAppear {
    if let first = recentlyPlayed.first {
        extractDominantColor(from: first)
    }
}
```

### 3.3 背景渲染

背景不只是纯色平铺，而是带渐变层次：

```swift
ZStack {
    dominantColor.ignoresSafeArea()

    LinearGradient(
        colors: [dominantColor, dominantColor.opacity(0.6), .black.opacity(0.9)],
        startPoint: .top,
        endPoint: .bottom
    )
    .ignoresSafeArea()

    // 可叠加 .ultraThinMaterial 模糊质感
}
```

### 3.4 颜色缓存

为避免重复网络请求和 CPU 计算，使用 `NSCache` 缓存已提取的颜色：

```swift
// DominantColorExtractor 内
private static let cache = NSCache<NSString, UIColor>()

static func cachedColor(for url: URL?) async -> Color {
    guard let url else { return .black.opacity(0.9) }
    let key = url.absoluteString as NSString
    if let cached = cache.object(forKey: key) {
        return Color(cached)
    }
    let color = await extractDominantColor(from: url)
    // 存入缓存（需转为 UIColor）
    // ...
    return color
}
```

---

## 四、卡片阴影

### 4.1 适用范围

除二楼内的影剧卡片外，其他所有版块（最近添加、地区分类、类型筛选、人物筛选）中的 `PosterCard` 均添加阴影。

### 4.2 实现

文件：`Vanmo/Shared/Components/PosterCard.swift`

在 `PosterCard` 中添加 `showShadow` 参数（默认 `true`）：

```swift
struct PosterCard: View {
    // ... 已有属性
    var showShadow: Bool = true

    var body: some View {
        // ... 已有布局
        .shadow(
            color: showShadow ? .black.opacity(0.25) : .clear,
            radius: showShadow ? 8 : 0,
            x: 0,
            y: showShadow ? 4 : 0
        )
    }
}
```

二楼内使用 `PosterCard(showShadow: false)` 关闭阴影（二楼已有动态背景，阴影会显得多余）。

### 4.3 阴影参数建议

| 场景 | color | radius | y |
|------|-------|--------|---|
| 深色背景卡片 | `.black.opacity(0.25)` | 8 | 4 |
| 浅色背景卡片 | `.black.opacity(0.15)` | 6 | 3 |

由于 Vanmo 以深色为主，推荐第一组参数。

---

## 文件清单

| 操作 | 文件路径 |
|------|----------|
| 新建 | `Vanmo/Features/Library/Views/SecondFloorView.swift` |
| 新建 | `Vanmo/Features/Library/Views/SecondFloorItemView.swift` |
| 新建 | `Vanmo/Shared/Utilities/DominantColorExtractor.swift` |
| 修改 | `Vanmo/Features/Library/Views/LibraryView.swift` — 移除旧"继续观看"区段，集成二楼入口 |
| 修改 | `Vanmo/Shared/Components/PosterCard.swift` — 添加 `showShadow` + 阴影 |

## 实施检查清单

```
Task Progress:
- [ ] 1. 创建 DominantColorExtractor 工具
- [ ] 2. 创建 SecondFloorItemView 单页视图
- [ ] 3. 创建 SecondFloorView（二楼主视图 + 分页器 + 动态背景）
- [ ] 4. LibraryView 集成下拉触发二楼
- [ ] 5. LibraryView 移除旧的"继续观看"横向区段
- [ ] 6. PosterCard 添加阴影参数
- [ ] 7. 验证二楼进出动画流畅
- [ ] 8. 验证主色提取与背景切换效果
- [ ] 9. 编译检查
```

## 注意事项

- `CIAreaAverage` 在主线程执行会卡顿，务必在 `Task {}` 异步调用
- 海报 URL 可能为 nil（无元数据时），需给 `dominantColor` 一个深色默认值
- 二楼动画使用 `.spring()` 提供物理弹性手感
- `TabView(.page)` 在 item 数量动态变化时可能有已知 bug，建议固定数组或使用 `ScrollView` + `.scrollTargetBehavior(.paging)` 替代
- 下拉检测需避免与 `ScrollView` 自身回弹冲突，仅在内容已到顶部时响应下拉
- 颜色提取使用缩略图 URL（如 TMDb `w300`）而非原图，减少网络和计算开销
