import SwiftData
import SwiftUI
import VanmoCore

struct MacEmbyFolderBrowseView: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macTheme) private var theme

    let container: MediaItem

    @State private var children: [ServerMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            MacLibrarySublistHeader(
                title: container.title,
                subtitle: container.mediaType.displayName
            )

            Group {
                if isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if children.isEmpty {
                    Text("此目录下没有可显示的项目")
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(children, id: \.serverId) { child in
                                Button {
                                    openChild(child)
                                } label: {
                                    MacEmbyChildListRow(serverItem: child)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if child.mediaType == .movie || child.mediaType == .tvEpisode {
                                        Button("播放") {
                                            appState.play(makeChildItem(child))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(MacDesignTokens.Layout.contentPadding)
                    }
                }
            }
        }
        .background(theme.appBackground)
        .task(id: container.serverId) {
            await loadChildren()
        }
    }

    private func openChild(_ child: ServerMediaItem) {
        let item = makeChildItem(child)
        switch item.mediaType {
        case .folder, .collectionFolder, .season, .boxSet:
            if item.serverId != nil {
                appState.openEmbyFolderBrowse(container: item)
            } else {
                appState.openDetail(item)
            }
        default:
            appState.openDetail(item)
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
            if let snapshot = try? MediaServerConnectionResolver.snapshot(for: container, in: modelContext) {
                children = try await EmbyChildItemsFetcher.fetchChildren(parentId: parentId, connection: snapshot)
            } else {
                children = try await EmbyChildItemsFetcher.fetchChildren(parentId: parentId)
            }
        } catch {
            errorMessage = error.localizedDescription
            children = []
        }

        isLoading = false
    }

    private func makeChildItem(_ child: ServerMediaItem) -> MediaItem {
        let item = ServerMediaItemMapper.makeMediaItem(from: child)
        item.sourceConnectionId = container.sourceConnectionId
        return item
    }
}

private struct MacEmbyChildListRow: View {
    @Environment(\.macTheme) private var theme

    let serverItem: ServerMediaItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: serverItem.mediaType.icon)
                .font(.title3)
                .foregroundStyle(MacDesignTokens.accentBlue)
                .frame(width: 36, height: 36)
                .background(MacDesignTokens.accentBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(serverItem.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(serverItem.mediaType.displayName)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)

                    if let year = serverItem.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
            }

            Spacer()

            if serverItem.mediaType.isBrowsable {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.vertical, 8)
    }
}
