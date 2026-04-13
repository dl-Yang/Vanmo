---
name: media-detail-ui
description: 媒体详情页三层 Z 轴布局重构指南：底层主色背景、中间层海报、顶层媒体信息，海报与背景之间做渐变过渡。触发场景：用户提到"详情页改版""详情页布局""主色背景""海报渐变过渡"或媒体详情页的 UI 开发任务。
---

# 媒体详情页 — 三层 Z 轴布局

## 概览

将 `MediaDetailView` 的 header 从当前"背景大图 + 小海报 + 信息叠加"改为 **三层 Z 轴** 布局：

| Z 层（由下到上） | 内容 | 说明 |
|------------------|------|------|
| 底层（Layer 0） | 主色背景 | 提取海报主色，平铺整个背景区域 |
| 中间层（Layer 1） | 海报 | 居中大尺寸展示，与底层通过渐变过渡融合 |
| 顶层（Layer 2） | 媒体信息 | 标题、年份、时长、评分、播放按钮等 |

**设计目标**：海报不再是附属小缩略图，而是视觉主体；背景由海报主色渲染，营造沉浸式氛围；海报边缘自然渐隐到背景色，无硬切割感。

---

## 一、整体结构

文件：`Vanmo/Features/Library/Views/MediaDetailView.swift`

将 `headerSection` 重构为三层 `ZStack`：

```swift
private var headerSection: some View {
    ZStack(alignment: .bottom) {
        // Layer 0: 主色背景
        dominantColorBackground

        // Layer 1: 海报 + 渐变过渡
        posterLayer

        // Layer 2: 媒体信息
        mediaInfoOverlay
    }
    .frame(height: 520)
    .clipped()
    .task {
        dominantColor = await DominantColorExtractor.cachedColor(
            for: item.posterURL
        )
    }
}
```

新增 State：

```swift
@State private var dominantColor: Color = .black.opacity(0.9)
```

---

## 二、底层 — 主色背景（Layer 0）

用 `dominantColor` 铺满整个 header 区域，叠加微弱径向渐变增加层次：

```swift
private var dominantColorBackground: some View {
    ZStack {
        dominantColor
            .ignoresSafeArea()

        // 从中心向外的轻微径向暗角，增加纵深
        RadialGradient(
            colors: [dominantColor, dominantColor.opacity(0.7)],
            center: .center,
            startRadius: 50,
            endRadius: 400
        )
        .ignoresSafeArea()
    }
    .animation(.easeInOut(duration: 0.6), value: dominantColor)
}
```

### 颜色提取

复用已有的 `DominantColorExtractor`（位于 `Vanmo/Shared/Utilities/DominantColorExtractor.swift`），使用带缓存的 `cachedColor(for:)` 方法避免重复计算。

---

## 三、中间层 — 海报 + 渐变过渡（Layer 1）

海报居中展示，四周边缘用渐变遮罩使其自然融入底层背景色。

```swift
private var posterLayer: some View {
    AsyncImage(url: item.posterURL) { phase in
        switch phase {
        case .success(let image):
            image.resizable().aspectRatio(contentMode: .fit)
        default:
            Rectangle().fill(Color.vanmoSurface)
                .overlay {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
        }
    }
    .frame(maxWidth: 240)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .mask(posterEdgeFadeMask)
    .padding(.bottom, 100)
}
```

### 渐变过渡遮罩

关键：用 `mask` 让海报的底部和顶部边缘渐隐到透明，与背景色自然融合。

```swift
private var posterEdgeFadeMask: some View {
    VStack(spacing: 0) {
        // 顶部渐入
        LinearGradient(
            colors: [.clear, .white],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 40)

        // 中间完全不透明
        Rectangle().fill(.white)

        // 底部渐出（更长的渐变，营造海报向下溶解到背景的效果）
        LinearGradient(
            colors: [.white, .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 80)
    }
}
```

> 也可叠加额外的渐变层覆盖在海报之上（而非 mask），用 `dominantColor` 作为渐变端点色，效果更可控：

```swift
// 海报底部叠加的渐变，从透明到主色
LinearGradient(
    colors: [.clear, dominantColor],
    startPoint: .init(x: 0.5, y: 0.6),
    endPoint: .bottom
)
```

**两种方案可以组合使用**：mask 处理海报本身的透明度，叠加渐变处理颜色融合。

---

## 四、顶层 — 媒体信息（Layer 2）

在 `ZStack` 最上方放置文字信息，位于 header 底部区域：

```swift
private var mediaInfoOverlay: some View {
    VStack(alignment: .leading, spacing: 8) {
        Spacer()

        Text(item.title)
            .font(.title2.bold())
            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

        HStack(spacing: 8) {
            if let year = item.year {
                Text("\(year)")
            }
            if item.duration > 0 {
                Text(item.duration.shortDuration)
            }
            Text(item.mediaType.displayName)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)

        if let rating = item.rating {
            RatingBadge(rating)
        }

        playButton
    }
    .padding()
}
```

信息层文字都添加 `shadow` 保证在任何主色背景下的可读性。

---

## 五、BackdropHeader 处理

重构后 `headerSection` **不再使用** `BackdropHeader` 组件（该组件是为背景大图设计的）。新布局的背景由主色填充，不再需要背景图片。

如果希望保留背景图作为额外质感（如模糊背景图 + 主色叠加），可选方案：

```swift
// Layer 0 内叠加模糊背景图
AsyncImage(url: item.backdropURL ?? item.posterURL) { phase in
    if case .success(let img) = phase {
        img.resizable().aspectRatio(contentMode: .fill)
            .blur(radius: 30)
            .overlay(dominantColor.opacity(0.7))
    }
}
.frame(height: 520)
.clipped()
.ignoresSafeArea()
```

---

## 六、info 区域与 header 衔接

`infoSection` 的顶部也需要与主色背景融合，避免断层：

```swift
VStack(spacing: 0) {
    headerSection

    // header → info 区域过渡
    LinearGradient(
        colors: [dominantColor, Color.vanmoBackground],
        startPoint: .top,
        endPoint: .bottom
    )
    .frame(height: 60)
    .animation(.easeInOut(duration: 0.6), value: dominantColor)

    infoSection
}
```

---

## 文件变更清单

| 操作 | 文件路径 |
|------|----------|
| 修改 | `Vanmo/Features/Library/Views/MediaDetailView.swift` — 重构 `headerSection` 为三层 Z 轴布局 |
| 复用 | `Vanmo/Shared/Utilities/DominantColorExtractor.swift` — 已有，无需修改 |
| 可选修改 | `Vanmo/Shared/Components/BackdropHeader.swift` — 若不再被其他页面使用可考虑移除 |

## 实施检查清单

```
Task Progress:
- [ ] 1. MediaDetailView 添加 dominantColor State
- [ ] 2. 重构 headerSection 为 ZStack 三层布局
- [ ] 3. 实现底层主色背景（含径向渐变层次）
- [ ] 4. 实现中间层海报（居中大尺寸 + 边缘渐变遮罩）
- [ ] 5. 实现海报与背景的渐变过渡（mask + 叠加渐变组合）
- [ ] 6. 实现顶层媒体信息覆盖层
- [ ] 7. 处理 header → info 区域的颜色过渡
- [ ] 8. 移除对 BackdropHeader 的依赖（或保留模糊背景方案）
- [ ] 9. 验证主色提取异步加载 + 颜色切换动画
- [ ] 10. 编译检查 + Preview 验证
```

## 注意事项

- `DominantColorExtractor.cachedColor(for:)` 必须在异步上下文调用（`.task {}` 或 `Task {}`）
- 海报 URL 可能为 nil，`dominantColor` 需有深色默认值保证无数据时也有良好视觉
- 渐变遮罩的 `height` 数值需根据海报实际尺寸微调，建议用 `GeometryReader` 取动态值
- 文字始终添加 `shadow` 保证在浅色主色背景上的可读性
- `dominantColor` 变化时用 `.animation(.easeInOut)` 平滑过渡，避免颜色突变
