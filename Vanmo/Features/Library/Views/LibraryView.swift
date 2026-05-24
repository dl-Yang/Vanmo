import SwiftUI
import SwiftData
import Kingfisher

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
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
        .onChange(of: connectionsViewModel.librarySyncCompletionID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await viewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
                showSyncToast("数据同步完成")
            }
        }
        .fullScreenCover(isPresented: $showSecondFloor) {
            SecondFloorView(
                isPresented: $showSecondFloor,
                recentlyPlayed: viewModel.recentlyPlayed
            )
        }
    }

    // MARK: - Library Content

    private var libraryContent: some View {
        LazyVStack(alignment: .leading, spacing: 28) {
            if !viewModel.recentlyPlayed.isEmpty {
                secondFloorEntryHint
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

    // MARK: - Collection Folder Grid

    @ViewBuilder
    private var collectionFolderSections: some View {
        if viewModel.isLoadingEmbyHome && viewModel.serverCollectionFolders.isEmpty {
            CollectionFolderLoadingSection()
        } else {
            ForEach(viewModel.orderedEmbyConnections) { connection in
                if let folders = viewModel.serverCollectionFolders[connection.id], !folders.isEmpty {
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
        VStack(alignment: .leading, spacing: 14) {
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

                    Text("\(folders.count) 个媒体库")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Text("\(folders.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.vanmoSurface, in: Capsule())
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(folders) { folder in
                        NavigationLink {
                            CollectionFolderListView(folder: folder, connection: connection)
                        } label: {
                            CollectionFolderHomeCard(folder: folder)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 26)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: - Second Floor Entry

    private var secondFloorEntryHint: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            showSecondFloor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.vanmoPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("继续观看")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("\(viewModel.recentlyPlayed.count) 部影片有播放记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.vanmoSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }

    // MARK: - Favorites

    private var favoritesStackedSection: some View {
        NavigationLink {
            FavoritesListView()
        } label: {
            FavoritesStackedCard(
                posterURLs: viewModel.favorites.prefix(5).map(\.posterURL),
                totalCount: viewModel.totalFavoritesCount,
                movieCount: viewModel.favoriteMovieCount,
                tvShowCount: viewModel.favoriteTVShowCount
            )
        }
        .buttonStyle(.plain)
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

private struct CollectionFolderHomeCard: View {
    let folder: CollectionFolder

    private let cardWidth: CGFloat = 172
    private let artworkHeight: CGFloat = 104

    private var accent: Color {
        switch folder.collectionType {
        case .movies:
            return Color.orange
        case .tvshows:
            return Color.cyan
        case .playlists:
            return Color.green
        }
    }

    private var secondaryAccent: Color {
        switch folder.collectionType {
        case .movies:
            return Color.red
        case .tvshows:
            return Color.indigo
        case .playlists:
            return Color.teal
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            artwork

            VStack(alignment: .leading, spacing: 7) {
                Text(folder.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(height: 38, alignment: .topLeading)

                HStack(spacing: 6) {
                    Image(systemName: folder.collectionType.icon)
                        .font(.caption2)
                        .fontWeight(.semibold)

                    Text(folder.collectionType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: cardWidth, height: 190, alignment: .topLeading)
        .background(Color.vanmoSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folder.name)，\(folder.collectionType.displayName)媒体库")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.62),
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .frame(width: cardWidth - 20, height: artworkHeight)
        .overlay(alignment: .bottomLeading) {
            coverTypeTag
                .padding(9)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var coverTypeTag: some View {
        HStack(spacing: 8) {
            Image(systemName: folder.collectionType.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            Text(folder.collectionType.displayName)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .frame(maxWidth: cardWidth - 38, alignment: .leading)
    }

    private var placeholderArtwork: some View {
        ZStack {
            LinearGradient(
                colors: [
                    accent.opacity(0.76),
                    secondaryAccent.opacity(0.5),
                    Color.vanmoPrimary.opacity(0.34),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: folder.collectionType.icon)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.white.opacity(0.22))
                .offset(x: 42, y: -18)

            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .offset(x: -42, y: 24)
        }
    }
}

private struct CollectionFolderLoadingSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        CollectionFolderLoadingCard()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 26)
            }
            .scrollClipDisabled()
        }
        .redacted(reason: .placeholder)
    }
}

private struct CollectionFolderLoadingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.vanmoSurface)
                .frame(height: 104)

            RoundedRectangle(cornerRadius: 5)
                .fill(Color.vanmoSurface)
                .frame(height: 13)

            RoundedRectangle(cornerRadius: 5)
                .fill(Color.vanmoSurface.opacity(0.72))
                .frame(width: 86, height: 11)
        }
        .padding(10)
        .frame(width: 172, height: 190, alignment: .topLeading)
        .background(Color.vanmoSurface.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 18))
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
