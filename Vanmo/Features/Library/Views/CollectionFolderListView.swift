import SwiftUI
import Kingfisher

/// CollectionFolder 二级列表页：展示媒体库内的 Movie / Series / Video。
struct CollectionFolderListView: View {
    @EnvironmentObject private var appState: AppState

    let folder: CollectionFolder
    let connection: SavedConnection

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var startIndex = 0
    @State private var totalRecordCount = 0
    @State private var errorMessage: String?
    @State private var loadMoreErrorMessage: String?

    private let pageSize = 50
    private let gridColumns = [
        GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 14)
    ]

    var body: some View {
        Group {
            if isLoading {
                CollectionFolderListLoadingView(folder: folder, connectionName: connection.name)
            } else if let errorMessage {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "无法加载内容",
                    message: errorMessage
                )
            } else if items.isEmpty {
                EmptyStateView(
                    icon: folder.collectionType.icon,
                    title: "媒体库为空",
                    message: "此媒体库下没有可显示的项目"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        CollectionFolderListHeader(
                            folder: folder,
                            connectionName: connection.name,
                            loadedCount: items.count,
                            totalCount: totalRecordCount,
                            movieCount: movieCount,
                            seriesCount: seriesCount
                        )
                        .padding(.horizontal)

                        mediaGrid

                        loadStateFooter
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollClipDisabled()
            }
        }
        .background(Color.vanmoBackground)
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: folder.id) {
            await loadInitialPage()
        }
    }

    private var mediaGrid: some View {
        LazyVGrid(
            columns: gridColumns,
            spacing: 18
        ) {
            ForEach(items) { item in
                NavigationLink {
                    LibraryItemDestination(item: item)
                } label: {
                    PosterCard(
                        title: item.displayTitle,
                        posterURL: item.posterURL,
                        subtitle: listItemSubtitle(item),
                        rating: item.rating,
                        progress: item.playbackProgress > 0 ? item.playbackProgress : nil
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    listItemContextMenu(item)
                }
                .onAppear {
                    Task { await loadNextPageIfNeeded(currentItem: item) }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var loadStateFooter: some View {
        if loadMoreErrorMessage != nil {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("加载中断")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if isLoadingMore {
            HStack(spacing: 10) {
                ProgressView()

                Text("继续加载...")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else if !hasMore {
            Text(loadedSummaryText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    private var movieCount: Int {
        items.filter { $0.mediaType == .movie }.count
    }

    private var seriesCount: Int {
        items.filter { $0.mediaType == .tvShow }.count
    }

    private var loadedSummaryText: String {
        if totalRecordCount > 0 {
            return "已加载全部 \(totalRecordCount) 项"
        }
        return "已加载全部"
    }

    @ViewBuilder
    private func listItemContextMenu(_ item: MediaItem) -> some View {
        if item.mediaType == .movie || item.mediaType == .tvEpisode {
            Button {
                appState.play(item)
            } label: {
                Label("播放", systemImage: "play.fill")
            }
        }
    }

    private func listItemSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    private func loadInitialPage() async {
        isLoading = true
        errorMessage = nil
        loadMoreErrorMessage = nil
        items = []
        startIndex = 0
        totalRecordCount = 0
        hasMore = true

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                collectionType: folder.collectionType,
                startIndex: 0,
                pageSize: pageSize
            )
            items = page.items.map { $0.makeMediaItem() }
            startIndex = page.items.count
            totalRecordCount = page.totalRecordCount
            hasMore = startIndex < page.totalRecordCount
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadNextPageIfNeeded(currentItem item: MediaItem) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        let threshold = 5
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard index >= items.count - threshold else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }

        do {
            let page = try await CollectionFolderItemsFetcher.fetchPage(
                connection: connection,
                parentId: folder.id,
                collectionType: folder.collectionType,
                startIndex: startIndex,
                pageSize: pageSize
            )
            let newItems = page.items.map { $0.makeMediaItem() }
            let existingIDs = Set(items.map(\.id))
            items.append(contentsOf: newItems.filter { !existingIDs.contains($0.id) })
            startIndex += page.items.count
            totalRecordCount = page.totalRecordCount
            hasMore = !page.items.isEmpty && startIndex < page.totalRecordCount
        } catch {
            loadMoreErrorMessage = error.localizedDescription
            hasMore = false
        }
    }
}

private struct CollectionFolderListHeader: View {
    let folder: CollectionFolder
    let connectionName: String
    let loadedCount: Int
    let totalCount: Int
    let movieCount: Int
    let seriesCount: Int

    private var progressText: String {
        if totalCount > 0 {
            return "已加载 \(loadedCount) / \(totalCount)"
        }
        return "已加载 \(loadedCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                artwork

                VStack(alignment: .leading, spacing: 7) {
                    Text(folder.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.caption2)
                            .fontWeight(.semibold)

                        Text(connectionName)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        CollectionFolderListPill(
                            text: folder.collectionType.displayName,
                            icon: folder.collectionType.icon,
                            tint: Color.vanmoPrimary
                        )

                        CollectionFolderListPill(
                            text: progressText,
                            icon: "square.grid.2x2",
                            tint: Color.secondary
                        )
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                CollectionFolderListStat(value: "\(loadedCount)", label: "条目", icon: "square.grid.2x2")
                CollectionFolderListStat(value: "\(movieCount)", label: "电影", icon: "film")
                CollectionFolderListStat(value: "\(seriesCount)", label: "剧集", icon: "tv")
            }
        }
        .padding(16)
        .background(Color.vanmoSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.name)，\(folder.collectionType.displayName)，\(progressText)")
    }

    private var artwork: some View {
        ZStack {
            KFImage(folder.posterURL)
                .placeholder {
                    placeholderArtwork
                }
                .fade(duration: 0.22)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 96)
                .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.5),
                ],
                startPoint: .center,
                endPoint: .bottom
            )

            Image(systemName: folder.collectionType.icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
        }
        .frame(width: 76, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
    }

    private var placeholderArtwork: some View {
        LinearGradient(
            colors: [
                Color.vanmoPrimary.opacity(0.72),
                Color.vanmoSurface,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: folder.collectionType.icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white.opacity(0.26))
        }
    }
}

private struct CollectionFolderListPill: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .fontWeight(.semibold)

            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct CollectionFolderListStat: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(Color.vanmoPrimary)
                .frame(width: 24, height: 24)
                .background(Color.vanmoPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(Color.vanmoBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CollectionFolderListLoadingView: View {
    let folder: CollectionFolder
    let connectionName: String

    private let gridColumns = [
        GridItem(.adaptive(minimum: 112, maximum: 160), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CollectionFolderListHeader(
                    folder: folder,
                    connectionName: connectionName,
                    loadedCount: 0,
                    totalCount: 0,
                    movieCount: 0,
                    seriesCount: 0
                )
                .padding(.horizontal)

                LazyVGrid(
                    columns: gridColumns,
                    spacing: 18
                ) {
                    ForEach(0..<8, id: \.self) { _ in
                        CollectionFolderPosterPlaceholder()
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollClipDisabled()
        .redacted(reason: .placeholder)
    }
}

private struct CollectionFolderPosterPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.vanmoSurface)
                .aspectRatio(2 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface)
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.72))
                    .frame(width: 58, height: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 44)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        CollectionFolderListView(
            folder: CollectionFolder(
                id: "preview",
                name: "电影 - 华语",
                collectionType: .movies,
                posterURL: nil,
                serverConnectionId: UUID(),
                serverConnectionName: "Emby"
            ),
            connection: SavedConnection(
                name: "Emby",
                type: .emby,
                host: "192.168.1.1",
                port: 8096
            )
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
