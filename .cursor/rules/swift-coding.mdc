---
name: swift-coding
description: Vanmo Swift 编码规范。适用于所有 Swift 代码文件的编写和审查。
globs:
  - "**/*.swift"
---

# Swift 编码规范

## 基本规则

1. **Swift 版本**：Swift 5.9+，充分利用最新语言特性
2. **并发**：优先使用 async/await，避免回调地狱
3. **错误处理**：使用 typed throws 或自定义 Error enum，不要 `try!` 或 `try?` 忽略错误
4. **可选值**：优先 `guard let` 和 `if let`，避免强制解包 `!`
5. **访问控制**：默认 `private`，按需开放为 `internal` / `public`

## 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 类/结构体/枚举 | UpperCamelCase | `MediaLibrary`, `PlayerState` |
| 函数/变量 | lowerCamelCase | `loadMedia()`, `currentTime` |
| 协议 | UpperCamelCase + 形容词/名词 | `Playable`, `MediaProviding` |
| 常量 | lowerCamelCase | `maxRetryCount` |
| 泛型 | 单个大写字母或描述性名称 | `T`, `Element` |

## SwiftUI 规范

1. **View 拆分**：单个 View 的 `body` 不超过 40 行，超出则拆分为子 View
2. **状态管理**：
   - `@State` — View 私有简单状态
   - `@StateObject` — View 拥有的 ObservableObject
   - `@ObservedObject` — 外部传入的 ObservableObject
   - `@EnvironmentObject` — 全局共享对象
   - `@Observable` (iOS 17+) — 优先使用 Observation 框架
3. **Preview**：每个 View 都要提供 `#Preview` 预览
4. **Modifier 顺序**：按功能分组，视觉 → 布局 → 交互 → 无障碍

## 异步代码规范

```swift
// 使用 async/await
func fetchMetadata(for title: String) async throws -> MediaMetadata {
    let url = TMDbAPI.searchURL(query: title)
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(MediaMetadata.self, from: data)
}

// 使用 Actor 保护共享状态
actor PlaybackStateManager {
    private var playbackPositions: [UUID: TimeInterval] = [:]

    func updatePosition(for id: UUID, position: TimeInterval) {
        playbackPositions[id] = position
    }

    func position(for id: UUID) -> TimeInterval {
        playbackPositions[id] ?? 0
    }
}
```

## 文件组织

每个 Swift 文件按以下顺序组织：

1. Import 语句
2. 协议/委托定义
3. 主类型定义
4. Extension（按功能分组，使用 `// MARK: -`）
5. Preview Provider（仅 View 文件）
