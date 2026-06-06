import SwiftUI
import SwiftData
import Kingfisher

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = LibraryViewModel()

    @State private var syncToastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            cinematicBackground
                .ignoresSafeArea()

            if let syncToastMessage {
                LibrarySyncToast(message: syncToastMessage)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
            ScrollView {
                if let message = connectionsViewModel.librarySyncMessage {
                    librarySyncStatusOverlay(message: message)
                        .zIndex(3)
                }
                if viewModel.isLibraryEmpty {
                    emptyState
                } else {
                    libraryContent
                }
            }

        }
        .navigationTitle("首页")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.vanmoCinematicBackground.opacity(0.72), for: .navigationBar)
        .task {
            viewModel.setModelContext(modelContext)
            await connectionsViewModel.loadSavedConnections()
            await viewModel.loadInitialSections(connections: connectionsViewModel.savedConnections)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaFavoriteDidChange)) { _ in
            Task {
                await connectionsViewModel.loadSavedConnections()
                await viewModel.refreshEmbyHome(connections: connectionsViewModel.savedConnections)
            }
        }
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await viewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
                showSyncToast("数据同步完成")
            }
        }
    }

    private var cinematicBackground: some View {
        Color.vanmoCinematicBackground
            .overlay(alignment: .top) {
                RadialGradient(
                    colors: [
                        Color.vanmoPrimary.opacity(0.22),
                        Color.vanmoCinematicBackground.opacity(0.0),
                    ],
                    center: .topLeading,
                    startRadius: 40,
                    endRadius: 360
                )
                .frame(height: 420)
            }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: VanmoCinema.sectionSpacing) {
            if !viewModel.recentlyPlayed.isEmpty {
                continueWatchingSection
            }

            if viewModel.totalFavoritesCount > 0 {
                favoritesStackedSection
            }

            if hasEmbyConnectionsConfigured {
                collectionFolderSections
            }

            scannedLibrarySections
        }
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private var hasEmbyConnectionsConfigured: Bool {
        connectionsViewModel.savedConnections.contains { connection in
            connection.type == .emby || connection.type == .jellyfin
        }
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private func usesServerCollectionAPI(_ connection: SavedConnection) -> Bool {
        connection.type == .emby || connection.type == .jellyfin
    }

    // MARK: - Collection Folder Grid

    @ViewBuilder
    private var collectionFolderSections: some View {
        if viewModel.isLoadingEmbyHome && viewModel.serverCollectionFolders.isEmpty {
            CollectionFolderLoadingSection()
        } else {
            ForEach(viewModel.orderedEmbyConnections) { connection in
                let folders = viewModel.homeVisibleFolders(for: connection.id)
                if !folders.isEmpty {
                    collectionFolderSection(serverName: connection.name, folders: folders, connection: connection)
                }
            }

            if let error = viewModel.embyHomeError, viewModel.serverCollectionFolders.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, VanmoCinema.horizontalPadding)
            }
        }
    }

    @ViewBuilder
    private var scannedLibrarySections: some View {
        ForEach(viewModel.orderedScannedConnections) { connection in
            let folders = viewModel.homeVisibleScannedFolders(for: connection.id)
            if !folders.isEmpty {
                collectionFolderSection(serverName: connection.name, folders: folders, connection: connection)
            }
        }
    }

    private func collectionFolderSection(
        serverName: String,
        folders: [CollectionFolder],
        connection: SavedConnection
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            serverSectionHeader(serverName: serverName, folderCount: folders.count)

            ForEach(folders) { folder in
                folderRow(folder: folder, connection: connection)
            }
        }
    }

    private func serverSectionHeader(serverName: String, folderCount: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vanmoCinematicSurfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.vanmoCinematicBorder, lineWidth: 1)
                    }

                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.vanmoCinematicAccent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(serverName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("\(folderCount) 个媒体库")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 12)

            Text("\(folderCount)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.66))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.vanmoCinematicSurfaceElevated.opacity(0.78), in: Capsule())
        }
        .padding(.horizontal, VanmoCinema.horizontalPadding)
    }

    private func folderRow(folder: CollectionFolder, connection: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(folder.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                folderTypePill(folder.collectionType)

                Spacer(minLength: 8)

                NavigationLink {
                    folderDestination(folder: folder, connection: connection)
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.white.opacity(0.68))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.vanmoCinematicSurfaceElevated.opacity(0.78), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, VanmoCinema.horizontalPadding)

            folderPreviewContent(folder: folder, connection: connection)
        }
    }

    @ViewBuilder
    private func folderDestination(
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        if usesServerCollectionAPI(connection) {
            CollectionFolderListView(folder: folder, connection: connection)
        } else {
            ScannedLibraryListView(connection: connection, collectionType: folder.collectionType)
        }
    }

    @ViewBuilder
    private func folderPreviewContent(
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        let previewItems = viewModel.previewItems(for: folder)
        let isLoaded = viewModel.isFolderPreviewLoaded(folder.id)

        if !isLoaded {
            folderPreviewSkeletonRow
        } else if !previewItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(previewItems) { item in
                        NavigationLink {
                            previewDestination(item: item, folder: folder, connection: connection)
                        } label: {
                            PosterCard(
                                title: item.displayTitle,
                                posterURL: item.posterURL,
                                subtitle: folderPreviewSubtitle(item),
                                rating: item.rating,
                                progress: item.playbackProgress > 0 ? item.playbackProgress : nil,
                                showShadow: false
                            )
                            .frame(width: isRegularWidth ? 120 : 112)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, VanmoCinema.horizontalPadding)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func previewDestination(
        item: MediaItem,
        folder: CollectionFolder,
        connection: SavedConnection
    ) -> some View {
        if !usesServerCollectionAPI(connection), folder.collectionType == .tvshows {
            ScannedShowDetailView(connection: connection, showTitle: item.showTitle ?? item.title)
        } else {
            LibraryItemDestination(item: item)
        }
    }

    private var folderPreviewSkeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    FolderPreviewPosterPlaceholder()
                }
            }
                .padding(.horizontal, VanmoCinema.horizontalPadding)
            .padding(.bottom, 4)
        }
        .scrollClipDisabled()
        .redacted(reason: .placeholder)
    }

    private func folderTypePill(_ type: EmbyCollectionType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.caption2)
            Text(type.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Color.vanmoPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.vanmoPrimary.opacity(0.18), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.vanmoPrimary.opacity(0.18), lineWidth: 1)
        }
    }

    private func folderPreviewSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    // MARK: - Continue Watching

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HomeSectionHeader(
                title: "继续观看",
                subtitle: "从上次离开的地方继续",
                symbol: "play.rectangle.fill"
            )

            if let latestItem = viewModel.recentlyPlayed.first {
                VStack(spacing: 12) {
                    ContinueWatchingHeroCard(
                        item: latestItem,
                        heroHeight: isRegularWidth ? 270 : 218
                    ) {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        appState.play(latestItem)
                    }

                    let historyItems = Array(viewModel.recentlyPlayed.dropFirst())
                    if !historyItems.isEmpty {
                        continueWatchingHistoryCard(historyItems)
                    }
                }
                .padding(.horizontal, VanmoCinema.horizontalPadding)
            }
        }
    }

    private func continueWatchingHistoryCard(_ items: [MediaItem]) -> some View {
        FavoritesStackedCard(
            entries: items.prefix(3).map {
                FavoritesStackedCard.FavoriteEntry(
                    title: $0.displayTitle,
                    subtitle: $0.mediaType.displayName,
                    posterURL: $0.backdropURL ?? $0.posterURL
                )
            },
            totalCount: items.count,
            movieCount: 0,
            tvShowCount: 0,
            title: "继续观看",
            countUnit: "部历史",
            badges: [
                .init(text: "上次观看", icon: "clock.fill"),
                .init(text: "历史记录", icon: "rectangle.stack.fill"),
            ],
            badgeIcon: "clock.fill",
            badgeColors: [
                Color.vanmoPrimary,
                Color.blue.opacity(0.9),
            ],
            accessibilityLabel: "继续观看，还有 \(items.count) 部历史"
        )
    }

    // MARK: - Favorites

    private var favoritesStackedSection: some View {
        NavigationLink {
            FavoritesListView()
        } label: {
            FavoritesStackedCard(
                entries: viewModel.favorites.prefix(3).map {
                    FavoritesStackedCard.FavoriteEntry(
                        title: $0.displayTitle,
                        subtitle: $0.mediaType.displayName,
                        posterURL: $0.posterURL
                    )
                },
                totalCount: viewModel.totalFavoritesCount,
                movieCount: viewModel.favoriteMovieCount,
                tvShowCount: viewModel.favoriteTVShowCount
            )
        }
        .buttonStyle(FavoritesCardButtonStyle())
        .padding(.horizontal)
    }

    private func librarySyncStatusOverlay(message: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SyncActivityIndicator()
                    .frame(width: 22, height: 22)

                Text(message)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 140, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
//        .padding(.top, 8)
//        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在同步数据")
        .accessibilityValue(message)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.vanmoCinematicSurfaceElevated)
                    .frame(width: 76, height: 76)

                Image(systemName: "film.stack")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.vanmoCinematicAccent)
            }

            VStack(spacing: 8) {
                Text("准备好搭建你的影院")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("连接网络共享或添加本地文件，Vanmo 会把海报、进度和详情整理成媒体库。")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            Button {
                appState.selectedTab = .connections
            } label: {
                Label("添加媒体源", systemImage: "plus")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.vanmoCinematicAccent, in: Capsule())
                    .foregroundStyle(.black.opacity(0.86))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
    }

    private func showSyncToast(_ message: String) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            syncToastMessage = message
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard syncToastMessage == message else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                syncToastMessage = nil
            }
        }
    }
}

private struct HomeGlassCardStyle: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.22),
                                .white.opacity(0.05),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: VanmoCinema.cardShadowColor, radius: 22, x: 0, y: 14)
    }
}

private struct HomeSectionHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.vanmoCinematicAccent)
                .frame(width: 30, height: 30)
                .background(Color.vanmoCinematicAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.vanmoCinematicAccent.opacity(0.18), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, VanmoCinema.horizontalPadding)
    }
}

private struct FolderPreviewPosterPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: VanmoCinema.posterCornerRadius)
                .fill(Color.vanmoCinematicSurfaceElevated)
                .aspectRatio(2 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.16))
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.10))
                    .frame(width: 58, height: 8)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 42)
        }
        .padding(6)
        .background(Color.vanmoCinematicSurface.opacity(0.68), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.vanmoCinematicBorder, lineWidth: 1)
        }
        .frame(width: 112)
    }
}

private struct ContinueWatchingHeroCard: View {
    let item: MediaItem
    let heroHeight: CGFloat
    let onTap: () -> Void

    private var progress: Double {
        min(max(item.playbackProgress, 0), 1)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                backdrop

                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(0.64),
                        Color.vanmoCinematicBackground.opacity(0.96),
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 10) {
                    Label("继续播放", systemImage: "play.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(Color.vanmoCinematicAccent.opacity(0.92), in: Capsule())
                        .foregroundStyle(.black.opacity(0.86))
                        .padding(.bottom, 2)

                    Text(item.displayTitle)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 7) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.white.opacity(0.20))
                                Capsule()
                                    .fill(Color.vanmoCinematicAccent)
                                    .frame(width: geometry.size.width * progress)
                            }
                        }
                        .frame(height: 5)

                        HStack(spacing: 8) {
                            Text(item.lastPlaybackPosition.shortDuration)
                            Text("·")
                            Text("共 \(item.duration.shortDuration)")
                        }
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipShape(RoundedRectangle(cornerRadius: VanmoCinema.cardCornerRadius))
            .modifier(HomeGlassCardStyle(cornerRadius: VanmoCinema.cardCornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: VanmoCinema.cardCornerRadius))
            .hoverEffect(.lift)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayTitle)，继续播放")
        .accessibilityValue("进度 \(Int(progress * 100))%")
    }

    private var backdrop: some View {
        KFImage(item.backdropURL ?? item.posterURL)
            .placeholder {
                ZStack {
                    Color.vanmoCinematicSurfaceElevated
                    Image(systemName: item.mediaType.icon)
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.36))
                }
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }
}

private struct CollectionFolderLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vanmoCinematicSurfaceElevated)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.16))
                        .frame(width: 120, height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.10))
                        .frame(width: 86, height: 10)
                }

                Spacer()
            }
            .padding(.horizontal, VanmoCinema.horizontalPadding)

            ForEach(0..<3, id: \.self) { _ in
                CollectionFolderLoadingRow()
            }
        }
        .redacted(reason: .placeholder)
    }
}

private struct CollectionFolderLoadingRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.16))
                    .frame(width: 120, height: 16)

                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.10))
                    .frame(width: 56, height: 22)

                Spacer()

                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.10))
                    .frame(width: 72, height: 28)
            }
            .padding(.horizontal, VanmoCinema.horizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        FolderPreviewPosterPlaceholder()
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        }
    }
}

private struct SyncActivityIndicator: View {
    private let cycleDuration = 1.05

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let rotation = (elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration) * 360

            ZStack {
                Circle()
                    .stroke(
                        Color.vanmoPrimary.opacity(0.18),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )

                Circle()
                    .trim(from: 0.12, to: 0.88)
                    .stroke(
                        Color.vanmoPrimary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation))

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.vanmoPrimary)
                    .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.85))
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

private struct LibrarySyncToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.vanmoCinematicAccent)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.vanmoCinematicSurfaceElevated.opacity(0.92), in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.vanmoCinematicAccent.opacity(0.28),
                            .white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.vanmoCinematicAccent.opacity(0.1), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

private struct SectionPlaceholderCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.vanmoCinematicSurfaceElevated)
                .aspectRatio(2 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.16))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.10))
                    .frame(width: 48, height: 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(isAnimating ? 0.48 : 1)
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

private struct SectionPlaceholderRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.vanmoCinematicSurfaceElevated)
                .frame(width: 60, height: 90)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.16))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.12))
                    .frame(width: 140, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.08))
                    .frame(width: 88, height: 10)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .opacity(isAnimating ? 0.48 : 1)
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: isAnimating)
        .onAppear { isAnimating = true }
    }
}

#Preview {
    NavigationStack {
        LibraryView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}
