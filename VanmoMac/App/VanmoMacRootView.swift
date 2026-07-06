import SwiftUI
import VanmoCore

struct VanmoMacRootView: View {
    @EnvironmentObject private var cloudSyncCoordinator: CloudSyncCoordinator
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: .constant("library")) {
                Label("媒体库", systemImage: "play.rectangle.on.rectangle")
                    .tag("library")
                Label("浏览", systemImage: "folder")
                    .tag("browser")
                Label("搜索", systemImage: "magnifyingglass")
                    .tag("search")
                Label("设置", systemImage: "gearshape")
                    .tag("settings")
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            ContentUnavailableView(
                "Vanmo for Mac",
                systemImage: "desktopcomputer",
                description: Text("桌面端 UI 将从零构建。VanmoCore 已接入，可共享 SwiftData 与 CloudKit 同步。")
            )
        }
    }
}

#Preview {
    VanmoMacRootView()
        .environmentObject(CloudSyncCoordinator.shared)
}
