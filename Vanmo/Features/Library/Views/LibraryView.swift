import SwiftUI
import SwiftData
import Kingfisher

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = LibraryViewModel()

    @State private var showSecondFloor = false
    @State private var syncToastMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
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
            .background(Color.vanmoBackground)

        }
        .navigationTitle("首页")
        .task {
            viewModel.setModelContext(modelContext)
            await connectionsViewModel.loadSavedConnections()
            await viewModel.loadInitialSections(connections: connectionsViewModel.savedConnections)
        }
        .refreshable {
            await connectionsViewModel.loadSavedConnections()
            await viewModel.refreshEmbyHome(connections: connectionsViewModel.savedConnections)
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
        .fullScreenCover(isPresented: compactSecondFloorBinding) {
            SecondFloorView(
                isPresented: $showSecondFloor,
                recentlyPlayed: viewModel.recentlyPlayed
            )
        }
        .sheet(isPresented: regularSecondFloorBinding) {
            SecondFloorView(
                isPresented: $showSecondFloor,
                recentlyPlayed: viewModel.recentlyPlayed
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if !viewModel.recentlyPlayed.isEmpty {
                continueWatchingSection
            }

            if viewModel.totalFavoritesCount > 0 {
                favoritesStackedSection
            }

            if hasEmbyConnectionsConfigured {
                collectionFolderSections
            }
        }
        .padding(.vertical)
    }

    private var hasEmbyConnectionsConfigured: Bool {
        connectionsViewModel.savedConnections.contains { connection in
            connection.type == .emby || connection.type == .jellyfin
        }
    }

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var compactSecondFloorBinding: Binding<Bool> {
        Binding(
            get: { showSecondFloor && !isRegularWidth },
            set: { newValue in
                if !newValue {
                    showSecondFloor = false
                }
            }
        )
    }

    private var regularSecondFloorBinding: Binding<Bool> {
        Binding(
            get: { showSecondFloor && isRegularWidth },
            set: { newValue in
                if !newValue {
                    showSecondFloor = false
                }
            }
        )
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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
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
                    .fill(Color.vanmoSurface)

                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.vanmoPrimary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(serverName)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(folderCount) 个媒体库")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("\(folderCount)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.vanmoSurface, in: Capsule())
        }
        .padding(.horizontal)
    }

    private func folderRow(folder: CollectionFolder, connection: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(folder.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                folderTypePill(folder.collectionType)

                Spacer(minLength: 8)

                NavigationLink {
                    CollectionFolderListView(folder: folder, connection: connection)
                } label: {
                    HStack(spacing: 4) {
                        Text("查看全部")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.vanmoSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            folderPreviewContent(folder: folder)
        }
    }

    @ViewBuilder
    private func folderPreviewContent(folder: CollectionFolder) -> some View {
        let previewItems = viewModel.previewItems(for: folder)
        let isLoaded = viewModel.isFolderPreviewLoaded(folder.id)

        if !isLoaded {
            folderPreviewSkeletonRow
        } else if !previewItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(previewItems) { item in
                        NavigationLink {
                            LibraryItemDestination(item: item)
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
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            .scrollClipDisabled()
        }
    }

    private var folderPreviewSkeletonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    FolderPreviewPosterPlaceholder()
                }
            }
            .padding(.horizontal)
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
        .background(Color.vanmoPrimary.opacity(0.12), in: Capsule())
    }

    private func folderPreviewSubtitle(_ item: MediaItem) -> String? {
        if let year = item.year {
            return "\(item.mediaType.displayName) · \(year)"
        }
        return item.mediaType.displayName
    }

    // MARK: - Second Floor Entry

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("继续观看")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text("点卡片可继续播放，轻拉可进入二楼")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    presentSecondFloor()
                } label: {
                    Label("二楼", systemImage: "sparkles")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.vanmoSurface, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: isRegularWidth ? 16 : 12) {
                    ForEach(viewModel.recentlyPlayed) { item in
                        ContinueWatchingHeroCard(
                            item: item,
                            cardWidth: isRegularWidth ? 360 : 276
                        ) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            appState.play(item)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            .simultaneousGesture(secondFloorUnlockGesture)
        }
    }

    private var secondFloorUnlockGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard value.translation.height > 96 else { return }
                guard abs(value.translation.width) < 90 else { return }
                presentSecondFloor()
            }
    }

    private func presentSecondFloor() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        showSecondFloor = true
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
                    .foregroundStyle(.secondary)
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
        EmptyStateView(
            icon: "film.stack",
            title: "媒体库为空",
            message: "连接网络共享或添加本地文件以开始浏览你的媒体"
        ) {
            appState.selectedTab = .connections
        }
        .frame(minHeight: 500)
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
            .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
            .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
    }
}

private struct FolderPreviewPosterPlaceholder: View {
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
            .background(Color.vanmoSurface.opacity(0.58))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 112)
    }
}

private struct ContinueWatchingHeroCard: View {
    let item: MediaItem
    let cardWidth: CGFloat
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
                        .black.opacity(0.72),
                        .black.opacity(0.9),
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .foregroundStyle(.white)

                    ProgressView(value: progress)
                        .tint(Color.vanmoPrimary)

                    HStack(spacing: 8) {
                        Text(item.lastPlaybackPosition.shortDuration)
                        Text("·")
                        Text("共 \(item.duration.shortDuration)")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                }
                .padding(12)
            }
            .frame(width: cardWidth, height: cardWidth * 0.56)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .modifier(HomeGlassCardStyle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
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
                    Color.vanmoSurface
                    Image(systemName: item.mediaType.icon)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .fade(duration: 0.2)
            .resizable()
            .scaledToFill()
    }
}

private struct CollectionFolderLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.vanmoSurface)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.vanmoSurface)
                        .frame(width: 120, height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.vanmoSurface.opacity(0.72))
                        .frame(width: 86, height: 10)
                }

                Spacer()
            }
            .padding(.horizontal)

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
                    .fill(Color.vanmoSurface)
                    .frame(width: 120, height: 16)

                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.vanmoSurface.opacity(0.72))
                    .frame(width: 56, height: 22)

                Spacer()

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.vanmoSurface.opacity(0.72))
                    .frame(width: 72, height: 28)
            }
            .padding(.horizontal)

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
                .foregroundStyle(Color.vanmoPrimary)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.vanmoPrimary.opacity(0.28),
                            .white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.vanmoPrimary.opacity(0.1), radius: 12, y: 5)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
    }
}

private struct SectionPlaceholderCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.vanmoSurface)
                .aspectRatio(2 / 3, contentMode: .fit)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface)
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.75))
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
                .fill(Color.vanmoSurface)
                .frame(width: 60, height: 90)

            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface)
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.8))
                    .frame(width: 140, height: 10)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.vanmoSurface.opacity(0.65))
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
