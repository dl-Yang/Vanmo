# PosterCard 尺寸不一致

## 状态：部分修复（组件层已修复，网格固定尺寸待收敛）

## 现象

媒体库页面中，部分影剧 item 的封面比底部标题信息区域更宽，且不同卡片的总高度不一致，导致网格布局错乱。

## 根因

三个问题叠加：

1. `KFImage` 在 `.fill` 模式下会放大图片填充，缺少稳定容器约束时容易出现右侧溢出
2. 底部 `titleOverlay` 高度随标题行数变化（单行 vs 两行），导致同一行卡片总高度不同
3. `LibraryView` 的网格使用 `GridItem(.adaptive(minimum: 110, maximum: 160))`，列宽会随屏幕与剩余空间变化，不是严格固定宽度

## 修复方案

### 海报区域：固定容器再填充

- `KFImage`: 使用 `.scaledToFill()` 仅负责填充
- 外层容器：`.frame(maxWidth: .infinity)` + `.aspectRatio(2 / 3, contentMode: .fit)` + `.clipped()`
- 结果：图片溢出被裁剪，不再出现右边超出和圆角视觉丢失

### 标题区域：固定高度

- `titleOverlay`: `.frame(height: 44)` — 固定 44pt，无论标题单行还是两行

组件层当前结果：`PosterCard` 内部比例与标题高度已稳定，单卡片不再右溢出。

## 待处理（下一步）

要实现“媒体库里所有 item 宽高严格固定”，还需要将网格列定义从自适应改为固定列宽（例如 `GridItem(.fixed(130), spacing: 12)`），适用于：

- `genreGrid`
- `personGrid`

## 涉及文件

- `Vanmo/Shared/Components/PosterCard.swift`
- `Vanmo/Features/Library/Views/LibraryView.swift`（待继续修改）
