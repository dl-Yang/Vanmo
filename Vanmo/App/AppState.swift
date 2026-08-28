import SwiftUI
import Combine
import VanmoCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .library
    @Published var isPlayerPresented = false
    @Published var currentPlayingItem: MediaItem?

    /// Settings tab 的导航路径。提到 `AppState` 中是为了在 `VanmoApp` 用
    /// `.id(theme)` 触发 `ContentView` 重建（用于刷新 vanmo* 颜色）时，
    /// 二级页面（如外观设置）的导航栈仍能保留，用户体验上不会被弹回根。
    @Published var settingsPath = NavigationPath()

    /// 收藏变化信号（每次 +1）。由常驻的 `ContentView` 转发 `.mediaFavoriteDidChange`
    /// 通知而来，避免 LibraryView 未挂载期间通知丢失；各页面订阅它做轻量刷新。
    @Published private(set) var favoriteChangeCount = 0

    /// 下载列表点选任务后待打开的媒体详情请求。由下载页消费并 present。
    @Published private(set) var pendingDownloadDetailRequest: DownloadRequest?

    func notifyFavoriteDidChange() {
        favoriteChangeCount += 1
    }

    func requestDownloadDetail(for request: DownloadRequest) {
        pendingDownloadDetailRequest = request
    }

    func consumeDownloadDetailRequest() {
        pendingDownloadDetailRequest = nil
    }

    func play(_ item: MediaItem) {
        currentPlayingItem = item
        isPlayerPresented = true
#if DEBUG
        print("[Debug][Player] present mediaType=\(item.mediaType.rawValue) isFile=\(item.fileURL.isFileURL) ext=\(item.fileURL.pathExtension.lowercased())")
#endif
    }

    func stopPlayback() {
        isPlayerPresented = false
        currentPlayingItem = nil
    }
}

/// Settings tab 内的导航路由。
enum SettingsRoute: Hashable {
    case appearance
    case downloads
}

enum AppTab: Int, CaseIterable {
    case library
    case connections
    case search
    case settings

    var title: String {
        switch self {
        case .library: return "媒体库"
        case .connections: return "文件"
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
