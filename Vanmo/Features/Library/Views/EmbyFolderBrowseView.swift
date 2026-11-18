import SwiftUI
import SwiftData
import VanmoCore

/// Emby/Jellyfin 容器条目（Folder / CollectionFolder / Season）的子级浏览页。
struct EmbyFolderBrowseView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let container: MediaItem

    @State private var children: [ServerMediaItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            CatAmberHalo(width: 180, height: 70, opacity: 0.22)
                .padding(.top, 12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                navHeader
                stateContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .task(id: container.serverId) {
            await loadChildren()
        }
    }

    private var navHeader: some View {
        HStack(spacing: 11) {
            CatBackButton { dismiss() }

            VStack(alignment: .leading, spacing: 1) {
                Text(container.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(L10n.tr("%d 项", children.count))
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
            }

            Spacer(minLength: 8)
            CatStretchingDivider()
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            LoadingView(L10n.tr("加载中..."))
        } else if let errorMessage {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: L10n.tr("无法加载内容"),
                message: errorMessage
            )
        } else if children.isEmpty {
            EmptyStateView(
                icon: container.mediaType.icon,
                title: L10n.tr("文件夹为空"),
                message: L10n.tr("此目录下没有可显示的项目")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(children, id: \.serverId) { child in
                        NavigationLink {
                            LibraryItemDestination(item: makeChildItem(child))
                        } label: {
                            EmbyChildListRow(serverItem: child)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { childContextMenu(child) }
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private func childContextMenu(_ child: ServerMediaItem) -> some View {
        if child.mediaType == .movie || child.mediaType == .tvEpisode {
            Button {
                appState.play(makeChildItem(child))
            } label: {
                Label(L10n.tr("播放"), systemImage: "play.fill")
            }
        }
    }

    private func loadChildren() async {
        guard let parentId = container.serverId else {
            errorMessage = L10n.tr("缺少服务器条目 ID")
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

/// 首页与文件夹浏览共用的导航目标。
struct LibraryItemDestination: View {
    let item: MediaItem

    var body: some View {
        switch item.mediaType {
        case .folder, .collectionFolder, .season, .boxSet:
            if item.serverId != nil {
                EmbyFolderBrowseView(container: item)
            } else {
                MediaDetailView(item: item)
            }
        default:
            MediaDetailView(item: item)
        }
    }
}

private struct EmbyChildListRow: View {
    let serverItem: ServerMediaItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: serverItem.mediaType.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CatDesign.accentAmber)
                .frame(width: 38, height: 38)
                .background(CatDesign.amberTintFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(CatDesign.strokeAmber, lineWidth: 0.75)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(serverItem.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(serverItem.mediaType.displayName)
                    if let year = serverItem.year {
                        Text("· \(year)")
                    }
                }
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textMuted)
            }

            Spacer(minLength: 8)

            if serverItem.mediaType.isBrowsable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textDim)
            }
        }
        .padding(12)
        .catGlassCard(cornerRadius: 18)
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
