# 封面图片滑动后不再加载

## 状态：已修复

## 现象

媒体库页面中，影剧 item 的封面在滑动到屏幕外后就不会再加载回来。如果滑动速度较快，大量 item 的封面都不会显示，只显示占位符。

## 根因分析

项目全部使用 SwiftUI 原生 `AsyncImage` 加载封面图片，在 `LazyVStack` / `LazyHStack` / `LazyVGrid` 等懒加载容器中存在三个严重问题：

1. **无持久缓存**：`AsyncImage` 依赖 URLSession 默认 HTTP 缓存，容量有限且受服务端响应头控制，不可靠
2. **View 回收导致状态丢失**：Lazy 容器在 cell 滑出可见区域时会销毁对应 View，`AsyncImage` 的加载状态随之丢失；滑回时需要从零开始重新发起网络请求
3. **快速滑动导致请求被取消**：`.task` 随 View 销毁而取消，正在进行的网络请求被中断并进入 `.failure` 状态，且不会自动重试

## 修复方案

引入 **Kingfisher** (SPM) 替代所有 `AsyncImage`，使用 `KFImage` 组件：

- 内存 + 磁盘两级缓存，已下载图片不会重复请求
- 同一 URL 下载请求自动合并，避免重复网络开销
- Lazy 容器中 View 重建时从缓存瞬时加载，无闪烁
- `.fade(duration: 0.25)` 提供平滑过渡动画
- `.placeholder { }` 在加载中和失败时展示占位视图

同时删除了项目中未被使用的自实现缓存代码：`ImageCacheManager.swift`、`CachedAsyncImage.swift`。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `Shared/Components/PosterCard.swift` | `AsyncImage` → `KFImage` |
| `Shared/Components/BackdropHeader.swift` | `AsyncImage` → `KFImage` |
| `Features/Library/Views/MediaListRow.swift` | `AsyncImage` → `KFImage` |
| `Features/Library/Views/SecondFloorItemView.swift` | `AsyncImage` → `KFImage` |
| `Features/Library/Views/MediaDetailView.swift` | `AsyncImage` → `KFImage` |
| `Features/Search/Views/SearchView.swift` | `AsyncImage` → `KFImage` |
| `Core/Storage/ImageCacheManager.swift` | 已删除 |
| `Shared/Components/CachedAsyncImage.swift` | 已删除 |
