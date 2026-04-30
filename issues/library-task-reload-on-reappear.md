# 媒体库返回/切 tab 触发重新加载导致刷新与白屏

## 状态：已修复

## 现象

1. **Bug 1**：从【媒体详情】页面返回【媒体库】首页时，首页会触发一次刷新（顶部 section 与卡片有可见的重新渲染）。
2. **Bug 2**：从【媒体库】切到其它任意 tab 后再切回，页面会瞬间白屏，需要手动滑动 ScrollView 触发滚动后内容才显示出来，看起来像是滚动状态出现问题。

## 根因分析

`LibraryView` 使用 SwiftUI `.task` modifier 加载数据：

```swift
.task {
    viewModel.setModelContext(modelContext)
    await viewModel.loadInitialSections()
}
```

SwiftUI `.task` 默认绑定 view 生命周期 —— 每次 view 从屏幕上移除（push 详情页 / 切 tab）再回来时，task 都会被取消并重新启动。这就直接导致：

1. 每次回到 `LibraryView`，`loadInitialSections()` 都会被重新调用。
2. `loadInitialSections()` 入口立即调用 `resetPagedItems()`，将已经加载的 `loadedItems` 数组**瞬间清空**。
3. 之后异步从 SwiftData 重新加载约耗时 76~102 ms，期间 ScrollView 内容为空，配合 `pagedSection` 的 `.transition(.opacity.combined(with: .move(edge: .top)))`，引起肉眼可见的"刷新"和"白屏闪现"。
4. ScrollView 因 contentSize 突变和 LazyVStack 子视图重建，滚动状态出现异常，需要用户手动触发滚动事件才能恢复正常布局。

## 调试方法

通过在 `LibraryView` 的 `.task`、`onAppear`、`onDisappear`、`loadInitialSections`、`resetPagedItems` 中插入运行时日志埋点，记录每次进入/离开 view 时的 `loadedItems.count` 与状态字段。日志清晰显示：

- 首次启动：`task entered → resetPagedItems → loadInitialSections exit (loadedItemsAfter=35)`
- 从详情页返回 / 切 tab 回来：再次出现 `task entered → resetPagedItems (loadedItemsBefore=35)` → 35 项被清零再重新加载

证实 `.task` 在 view 重新出现时会被重启并重跑 `loadInitialSections()`，是两个 bug 的共同根因。

## 修复方案

在 `LibraryViewModel` 中加入 `hasLoadedInitial` 守卫，确保 `loadInitialSections()` 只在首次成功加载时执行，后续 view 重新出现时直接 `return`：

```swift
private var hasLoadedInitial = false

func loadInitialSections() async {
    guard let context = modelContext else { return }
    guard !hasLoadedInitial else { return }
    isLoading = true
    defer { isLoading = false }

    resetPagedItems()
    // ...异步加载...
    do {
        // ...
        try await loadFirstPage()
        isLibraryEmpty = ...
        hasLoadedInitial = true
    } catch { ... }
}
```

排序、筛选、分类切换走的是独立的 `reloadPagedItems()`，不受影响，依旧能正常重载。

修复后日志验证：从详情页返回 / 切 tab 回来共 9 次，每次都正确进入 `skipped (already initialized)` 分支，`resetPagedItems` 整个会话只被调用 1 次（首次启动），数据不再被无谓清空，刷新与白屏现象消失。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `Vanmo/Features/Library/ViewModels/LibraryViewModel.swift` | 新增 `hasLoadedInitial` 标志位与入口守卫 |
