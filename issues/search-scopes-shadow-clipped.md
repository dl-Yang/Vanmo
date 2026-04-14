# 搜索范围阴影被遮挡

## 状态：已修复

## 现象

在搜索页中，`searchScopes` 底部有阴影效果，但阴影底边会被搜索结果区域轻微盖住，视觉上像“被切掉一条边”。

## 根因

系统 `searchScopes` 容器高度和阴影可见区域不可控，阴影在底部容易被自身裁剪。单纯给条目加 `padding` 会改变内部布局，但无法稳定扩大外层可渲染区域。

## 修复

改为使用自定义分段控件替代系统 `searchScopes`，直接控制高度与阴影空间：

- 移除 `.searchScopes(...)`
- 在搜索结果区域上方增加 `scopePicker`（`Picker + .segmented`）
- 明确设置控件高度：`.frame(height: 36)`
- 外层增加上下内边距与阴影：`.padding(.top, 8) + .padding(.bottom, 10) + .shadow(...)`

这样阴影不会再被裁剪，同时保留原有筛选功能。

## 涉及文件

- `Vanmo/Features/Search/Views/SearchView.swift`
