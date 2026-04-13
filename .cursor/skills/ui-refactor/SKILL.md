---
name: ui-refactor
description: 指导 Vanmo 项目的 UI 重构，包括媒体库模块的地区/类型/导演演员三维分类筛选体系、浏览模块改造为连接模块、以及形成独立于 Infuse 的自有设计风格。触发场景：用户提到"UI 重构""媒体库改版""分类筛选""连接模块"或要求重新设计首页。
---

# Vanmo UI 重构指南

## 设计理念

Vanmo 不是 Infuse 的仿品，而是具有自身设计语言的视频播放器。重构目标：

- **信息密度优先**：相比 Infuse 的大图沉浸，Vanmo 更注重一屏内展示更多有效信息
- **结构化浏览**：通过地区 + 类型 + 人物三维筛选体系，让用户快速定位想看的内容
- **精致而克制**：卡片设计精美但不过度装饰，评分、年份等关键信息一目了然
- **深色为主，强调内容**：深色背景下海报自然成为视觉焦点

## 重构范围

| 模块 | 改动 |
|------|------|
| 媒体库（首页） | 全面重构分类/筛选/卡片 |
| 浏览 → 连接 | 移除文件浏览，简化为连接管理 |
| 搜索 | 不变 |
| 设置 | 不变 |

---

## 第一部分：数据层改造

### 1.1 MediaItem 新增字段

文件：`Vanmo/Features/Library/Models/MediaItem.swift`

```swift
// 在现有属性后新增
var originCountry: [String]   // 来源国家/地区，如 ["CN"]、["US"]、["KR", "US"]
```

`init` 中补充默认值 `self.originCountry = []`。

### 1.2 TMDb 模型补充国家字段

文件：`Vanmo/Core/Metadata/TMDbModels.swift`

TMDb API 的 movie detail 返回 `production_countries`，TV detail 返回 `origin_country`。需在对应模型中解码：

```swift
// TMDbMovieDetail 新增
let productionCountries: [TMDbCountry]?

// TMDbTVDetail 新增
let originCountry: [String]?

// 新增国家结构体
struct TMDbCountry: Decodable {
    let iso31661: String   // "CN", "US" 等
    let name: String       // "China", "United States of America"
}
```

注意：`JSONDecoder` 已配置 `convertFromSnakeCase`，所以 `iso31661` 会自动匹配 JSON 中的 `iso_3166_1`。需验证此映射是否正确，若不正确则使用 `CodingKeys` 手动指定。

### 1.3 MetadataService 回写国家

文件：`Vanmo/Core/Metadata/MetadataService.swift`

`MetadataResult` 新增 `originCountry: [String]`。

电影：从 `TMDbMovieDetail.productionCountries` 取 `iso31661` 数组。
电视剧：直接取 `TMDbTVDetail.originCountry`。

`applyMetadata` 中补充：`item.originCountry = result.originCountry`。

### 1.4 国家代码映射工具

创建 `Vanmo/Shared/Utilities/CountryMapper.swift`，提供 ISO 3166-1 → 中文显示名映射：

```swift
enum CountryMapper {
    static func displayName(for code: String) -> String {
        let map: [String: String] = [
            "CN": "中国", "US": "美国", "GB": "英国", "JP": "日本",
            "KR": "韩国", "FR": "法国", "DE": "德国", "IN": "印度",
            "IT": "意大利", "ES": "西班牙", "CA": "加拿大", "AU": "澳大利亚",
            "TW": "中国台湾", "HK": "中国香港", "RU": "俄罗斯", "TH": "泰国",
        ]
        return map[code.uppercased()] ?? code
    }

    static func regionGroup(for codes: [String]) -> String {
        guard let first = codes.first else { return "其他" }
        return displayName(for: first)
    }
}
```

---

## 第二部分：媒体库模块 UI 重构

### 2.1 三维筛选体系

文件：`Vanmo/Features/Library/ViewModels/LibraryViewModel.swift`

#### 筛选模式枚举

```swift
enum LibraryFilterMode: String, CaseIterable {
    case region    // 按地区（默认）
    case genre     // 按类型
    case person    // 按导演/演员
}
```

#### 地区分类（默认模式）

按 `originCountry` 首位国家 + `mediaType` 二维分组：

```swift
struct RegionSection: Identifiable {
    let id: String           // "CN-movie", "US-tvShow" 等
    let regionName: String   // "中国"
    let mediaType: MediaType // .movie / .tvShow
    let items: [MediaItem]

    var displayTitle: String {
        "\(regionName) · \(mediaType.displayName)"
    }
}
```

ViewModel 计算属性 `regionSections` 按国家+类型生成分组，组内按评分或添加时间排序。空分组不展示。

#### 类型筛选（genre 模式）

```swift
@Published var selectedGenres: Set<String> = []
```

从所有 `MediaItem.genres` 中提取去重的类型列表。支持多选，多选时取交集（同时满足所有选中类型）或并集（满足任一类型，推荐并集）。

常见类型参考：动作、喜剧、爱情、惊悚、悬疑、恐怖、科幻、历史、纪录片、动画、犯罪、奇幻、战争、冒险、剧情、家庭、音乐。

#### 人物筛选（person 模式）

```swift
@Published var selectedPerson: String? = nil
```

从所有 `MediaItem.director` 和 `MediaItem.cast` 中提取人物列表（去重），展示出现频率最高的前 50 个。用户选择某人后，过滤该人参与的所有媒体。

### 2.2 LibraryView 布局重构

文件：`Vanmo/Features/Library/Views/LibraryView.swift`

#### 顶部区域

- 导航标题保持 "Vanmo"
- 工具栏右侧保留排序菜单 + 视图切换

#### 筛选模式切换栏

在内容顶部放置 `Picker` 或分段控件，三个选项：地区 | 类型 | 人物。使用 `.segmented` 风格或自定义胶囊切换器。

#### 地区模式布局

每个 `RegionSection` 渲染为一个横向滚动条（类似现有 `mediaSection`），标题如"中国 · 电影"。各 section 纵向排列，用 `LazyVStack`。若某地区条目少于 4 个，可合入"其他"分组。

#### 类型模式布局

顶部展示类型胶囊（可横向滚动），支持多选（选中高亮）。下方为筛选结果的网格/列表。

#### 人物模式布局

顶部展示搜索框 + 热门人物横向滚动。选中某人后展示其参与作品的网格/列表。人物胶囊可展示头像（若有 TMDb profilePath）。

### 2.3 媒体卡片升级

文件：`Vanmo/Shared/Components/PosterCard.swift`

当前 `PosterCard` 仅显示海报 + 标题 + 可选副标题 + 进度条。升级为：

```swift
struct PosterCard: View {
    let title: String
    let posterURL: URL?
    let subtitle: String?      // 年份
    let rating: Double?        // 评分（新增）
    let progress: Double?
    let originCountry: String? // 国家标签（新增，可选）
}
```

设计要点：
- 右上角半透明评分徽章（金色星标 + 评分数字），使用 `RatingBadge` 组件
- 左下角可选的国家小标签（半透明圆角背景）
- 底部信息区使用 `.ultraThinMaterial`，显示标题和年份
- 海报 `aspectRatio(2/3)` 保持不变
- 圆角 `12pt`，微阴影
- 悬停/按下时有细微缩放动画反馈

### 2.4 新增筛选器视图

创建 `Vanmo/Features/Library/Views/GenreFilterView.swift`：

```swift
struct GenreFilterView: View {
    let allGenres: [String]
    @Binding var selectedGenres: Set<String>
    // 横向滚动多选胶囊
}
```

创建 `Vanmo/Features/Library/Views/PersonFilterView.swift`：

```swift
struct PersonFilterView: View {
    let persons: [PersonInfo]    // name + optional profileURL + count
    @Binding var selectedPerson: String?
    // 搜索框 + 热门人物 grid
}
```

---

## 第三部分：连接模块改造

### 3.1 Tab 重命名

文件：`Vanmo/App/AppState.swift`

```swift
enum AppTab: Int, CaseIterable {
    case library
    case connections  // 原 browse
    case search
    case settings

    var title: String {
        switch self {
        case .library: return "媒体库"
        case .connections: return "连接"   // 原"浏览"
        case .search: return "搜索"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .library: return "film"
        case .connections: return "externaldrive.connected.to.line.below"  // 原 folder
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}
```

同步修改 `ContentView.swift` 中 `.tag(AppTab.browse)` → `.tag(AppTab.connections)`。

### 3.2 简化 BrowserView → ConnectionsView

重命名 `BrowserView.swift` → `ConnectionsView.swift`（或保留文件名但重命名结构体）。

移除 `fileListView`、`RemoteFileRow`、`handleFileTap` 等文件浏览相关代码。

保留：
- 已保存连接列表（`savedConnections`）
- 支持的协议类型列表 + 添加连接入口
- `AddConnectionView` sheet

改造连接行为——点击已保存连接时：
1. 调用 `viewModel.connect(to: connection)` 建立连接
2. 连接成功后触发 `MediaScanner` 扫描该连接的媒体文件
3. 自动切换到媒体库 Tab：`appState.selectedTab = .library`
4. 不再在此 Tab 打开文件浏览器

### 3.3 BrowserViewModel 简化

文件：`Vanmo/Features/Browser/ViewModels/BrowserViewModel.swift`

移除目录浏览相关状态和方法（`currentFiles`、`currentPath`、`navigateTo`、`navigateBack` 等）。

保留或新增：
- `savedConnections` 列表管理
- `connect(to:)` —— 连接后触发扫描并返回成功/失败
- `addConnection` / `deleteConnection`
- 扫描功能可委托给 `MediaScanner` actor

### 3.4 ConnectionsView UI 设计

布局：
- 顶部区域：标题"连接"
- 已保存连接 Section：每行显示协议图标 + 名称 + 主机 + 连接状态指示器
- 底部 Section：可用协议列表（SMB、FTP、WebDAV 等），点击打开 `AddConnectionView`
- 无连接时：`EmptyStateView` 提示添加连接

连接状态：
- 未连接：灰色圆点
- 连接中：旋转 `ProgressView`
- 已连接：绿色圆点
- 连接失败：红色圆点

---

## 改造检查清单

按以下顺序执行，每步完成后验证编译通过：

```
Task Progress:
- [ ] 1. MediaItem 新增 originCountry 字段
- [ ] 2. TMDbModels 新增国家相关解码
- [ ] 3. MetadataService 回写国家信息
- [ ] 4. 创建 CountryMapper 工具
- [ ] 5. 新增 LibraryFilterMode 和筛选逻辑到 ViewModel
- [ ] 6. 创建 GenreFilterView 和 PersonFilterView
- [ ] 7. 重构 LibraryView 布局（三模式切换）
- [ ] 8. 升级 PosterCard 组件（评分、国家标签）
- [ ] 9. AppTab 重命名 browse → connections
- [ ] 10. 重构 BrowserView → ConnectionsView
- [ ] 11. 简化 BrowserViewModel
- [ ] 12. 更新 ContentView Tab 引用
- [ ] 13. 验证搜索/设置模块未受影响
- [ ] 14. 全量编译检查
```

## 注意事项

- SwiftData `@Model` 新增属性需提供默认值，否则需要数据迁移
- `originCountry` 使用 ISO 3166-1 alpha-2 代码（如 "CN"、"US"），显示时通过 `CountryMapper` 转换
- TMDb API `language=zh-CN` 已配置，genre 名称会返回中文
- 筛选器的 UI 交互要流畅，使用 `withAnimation(.spring())` 过渡
- 保持现有 `#Preview` 可用，新增视图也要提供 Preview
