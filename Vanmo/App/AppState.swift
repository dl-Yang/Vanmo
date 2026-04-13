import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .library
    @Published var isPlayerPresented = false
    @Published var currentPlayingItem: MediaItem?

    func play(_ item: MediaItem) {
        currentPlayingItem = item
        isPlayerPresented = true
    }

    func stopPlayback() {
        isPlayerPresented = false
        currentPlayingItem = nil
    }
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
