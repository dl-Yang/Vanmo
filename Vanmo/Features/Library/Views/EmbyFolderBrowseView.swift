import SwiftUI

/// Emby/Jellyfin 容器条目（Folder / CollectionFolder / Season）的子级浏览页。
struct EmbyFolderBrowseView: View {
    @EnvironmentObject private var appState: AppState

    let container: MediaItem

    @State private var children: [ServerMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "无法加载内容",
                    message: errorMessage
                )
            } else if children.isEmpty {
                EmptyStateView(
                    icon: container.mediaType.icon,
                    title: "文件夹为空",
                    message: "此目录下没有可显示的项目"
                )
            } else {
                List(children, id: \.serverId) { child in
                    NavigationLink {
                        LibraryItemDestination(item: child.makeMediaItem())
                    } label: {
                        EmbyChildListRow(serverItem: child)
                    }
                    .contextMenu {
                        childContextMenu(child)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color.vanmoBackground)
        .navigationTitle(container.title)
        .navigationBarTitleDisplayMode(.large)
        .task(id: container.serverId) {
            await loadChildren()
        }
    }

    @ViewBuilder
    private func childContextMenu(_ child: ServerMediaItem) -> some View {
        if child.mediaType == .movie || child.mediaType == .tvEpisode {
            Button {
                appState.play(child.makeMediaItem())
            } label: {
                Label("播放", systemImage: "play.fill")
            }
        }
    }

    private func loadChildren() async {
        guard let parentId = container.serverId else {
            errorMessage = "缺少服务器条目 ID"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            children = try await EmbyChildItemsFetcher.fetchChildren(parentId: parentId)
        } catch {
            errorMessage = error.localizedDescription
            children = []
        }

        isLoading = false
    }
}

/// 首页与文件夹浏览共用的导航目标。
struct LibraryItemDestination: View {
    let item: MediaItem

    var body: some View {
        if item.mediaType.isBrowsable, item.serverId != nil {
            EmbyFolderBrowseView(container: item)
        } else {
            MediaDetailView(item: item)
        }
    }
}

private struct EmbyChildListRow: View {
    let serverItem: ServerMediaItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: serverItem.mediaType.icon)
                .font(.title3)
                .foregroundStyle(Color.vanmoPrimary)
                .frame(width: 36, height: 36)
                .background(Color.vanmoPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(serverItem.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(serverItem.mediaType.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let year = serverItem.year {
                        Text("\(year)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if serverItem.mediaType.isBrowsable {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        EmbyFolderBrowseView(
            container: MediaItem(
                title: "电影库",
                fileURL: URL(string: "vanmo://emby-container/preview")!,
                mediaType: .collectionFolder
            )
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
