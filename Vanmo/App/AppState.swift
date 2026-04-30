import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .library
    @Published var isPlayerPresented = false
    @Published var currentPlayingItem: MediaItem?

    /// Settings tab 的导航路径。提到 `AppState` 中是为了在 `VanmoApp` 用
    /// `.id(theme)` 触发 `ContentView` 重建（用于刷新 vanmo* 颜色）时，
    /// 二级页面（如外观设置）的导航栈仍能保留，用户体验上不会被弹回根。
    @Published var settingsPath = NavigationPath()

    func play(_ item: MediaItem) {
        currentPlayingItem = item
        isPlayerPresented = true
    }

    func stopPlayback() {
        isPlayerPresented = false
        currentPlayingItem = nil
    }
}

/// Settings tab 内的导航路由。
enum SettingsRoute: Hashable {
    case appearance
}

enum AppTab: Int, CaseIterable {
    case library
    case connections
    case search
    case settings

    var title: String {
        switch self {
        case .library: return "媒体库"
        case .connections: return "连接"
        case .search: return "搜索"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .library: return "film"
        case .connections: return "externaldrive.connected.to.line.below"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }
}
