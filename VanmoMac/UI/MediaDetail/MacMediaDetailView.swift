import SwiftUI
import SwiftData
import VanmoCore

struct MacMediaDetailView: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macTheme) private var theme
    @AppStorage("metadata.autoDownload") private var metadataAutoDownload = true

    let item: MediaItem

    @StateObject private var store = MacMediaDetailStore()
    @State private var mediaPurgeHandlerId: UUID?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isContentReady {
                        heroSection
                        contentSection
                    } else {
                        skeletonView
                    }
                }
            }

            backButton
        }
        .background(theme.appBackground)
        .task(id: detailItemKey) {
            await store.load(
                item: item,
                modelContext: modelContext,
                autoDownloadMetadata: metadataAutoDownload
            )
        }
        .onAppear {
            guard mediaPurgeHandlerId == nil else { return }
            mediaPurgeHandlerId = appState.registerMediaPurgeHandler { _ in
                store.invalidate()
            }
        }
        .onDisappear {
            if let mediaPurgeHandlerId {
                appState.unregisterMediaPurgeHandler(mediaPurgeHandlerId)
                self.mediaPurgeHandlerId = nil
            }
        }
        .alert("收藏失败", isPresented: favoriteErrorBinding) {
            Button("确定") {}
        } message: {
            Text(store.favoriteErrorMessage ?? "")
        }
        .alert("刷新失败", isPresented: refreshErrorBinding) {
            Button("确定") {}
        } message: {
            Text(store.refreshErrorMessage ?? "")
        }
    }

    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(theme.secondaryButtonBackground)
                .frame(height: MacDesignTokens.Layout.heroHeight)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 24) {
                skeletonBar(width: 320, height: 32)

                VStack(alignment: .leading, spacing: 10) {
                    skeletonBar(height: 16)
                    skeletonBar(height: 16)
                    skeletonBar(width: 240, height: 16)
                }

                skeletonBar(width: 180, height: 24)
            }
            .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
            .padding(.top, 32)
        }
    }

    private func skeletonBar(width: CGFloat? = nil, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.secondaryButtonBackground)
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .frame(height: height)
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            MacRemoteImage(url: store.content?.backdropURL ?? item.backdropURL ?? item.posterURL)
                .frame(height: MacDesignTokens.Layout.heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    theme.appBackground.opacity(0),
                    theme.appBackground.opacity(0.6),
                    theme.appBackground,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: MacDesignTokens.Layout.heroLinearHeight)

            VStack(alignment: .leading, spacing: 16) {
                MacMediaDetailTitleLogoView(
                    title: displayTitle,
                    logoURL: store.content?.logoURL ?? item.logoURL
                )

                metadataRow
                actionButtons
            }
            .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
            .padding(.bottom, 24)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 12) {
            if let rating = item.rating, rating > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(MacDesignTokens.ratingRed)
                        .font(.system(size: 14))
                    Text("\(Int(rating * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MacDesignTokens.ratingRed)
                }
            }

            if let year = item.year {
                metadataDot
                Text(String(year))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            if item.mediaType == .tvShow {
                metadataDot
                metadataChip("TV Show")
                metadataDot
                Text(episodeCountText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            let genres = displayGenres
            if !genres.isEmpty {
                metadataDot
                HStack(spacing: 8) {
                    ForEach(genres.prefix(3), id: \.self) { genre in
                        metadataChip(genre)
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                let startPosition = UserDefaults.standard.bool(forKey: "playback.resumePlayback")
                    ? item.lastPlaybackPosition
                    : 0
                appState.play(item, from: startPosition)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(MacDesignTokens.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.playButton))
            }
            .buttonStyle(.plain)

            favoriteButton
            watchedButton
            moreMenu
        }
        .padding(.top, 8)
    }

    private var favoriteButton: some View {
        Button {
            Task { await store.toggleFavorite(for: item, modelContext: modelContext) }
        } label: {
            ZStack {
                if store.isUpdatingFavorite {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: store.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(store.isFavorite ? .red : theme.primaryText)
                }
            }
            .frame(width: 40, height: 40)
            .background(theme.secondaryButtonBackground)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.isUpdatingFavorite)
        .help(store.isFavorite ? "取消收藏" : "收藏")
    }

    private var watchedButton: some View {
        Button {
            Task { await store.toggleWatched(for: item, modelContext: modelContext) }
        } label: {
            ZStack {
                if store.isUpdatingWatched {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: item.isWatched ? "checkmark.circle.fill" : "checkmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.isWatched ? MacDesignTokens.accentBlue : theme.primaryText)
                }
            }
            .frame(width: 40, height: 40)
            .background(theme.secondaryButtonBackground)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(store.isUpdatingWatched)
        .help(item.isWatched ? "标记未看" : "标记已看")
    }

    private var moreMenu: some View {
        Menu {
            Button {
                Task { await store.refreshMetadata(for: item, modelContext: modelContext, force: true) }
            } label: {
                Label("刷新元数据", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshingMetadata)

            Button {
                Task { await store.toggleWatched(for: item, modelContext: modelContext) }
            } label: {
                Label(item.isWatched ? "标记未看" : "标记已看", systemImage: "checkmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .frame(width: 40, height: 40)
                .background(theme.secondaryButtonBackground)
                .clipShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .help("更多")
    }

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            if let overview = displayOverview, !overview.isEmpty {
                Text(overview)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.secondaryText)
                    .lineSpacing(6)
                    .frame(maxWidth: 896, alignment: .leading)
            }

            episodesSection
            collectionsSection
            castSection
        }
        .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }

    @ViewBuilder
    private var episodesSection: some View {
        if item.mediaType == .tvShow {
            VStack(alignment: .leading, spacing: 16) {
                
                HStack{
                    Text("剧集")
                        .font(MacDesignTokens.Typography.detailSectionTitle)
                        .foregroundStyle(theme.primaryText)
                    
                    if store.seasonNumbers.count > 1 {
                        Picker("", selection: Binding(
                            get: { store.selectedSeason ?? store.seasonNumbers.first ?? 1 },
                            set: { season in
                                Task {
                                    await store.selectSeason(season, item: item, modelContext: modelContext)
                                }
                            }
                        )) {
                            ForEach(store.seasonNumbers, id: \.self) { season in
                                Text("第 \(season) 季").tag(season)
                            }
                        }
                        .pickerStyle(.automatic)
                    }
                }

                if store.isLoadingEpisodes && store.currentSeasonEpisodes.isEmpty {
                    LoadingIndicatorView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
//                    ProgressView()
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                        .padding(.vertical, 24)
                } else if store.currentSeasonEpisodes.isEmpty {
                    Text("暂无季集数据")
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .center, spacing: 16) {
                            ForEach(store.currentSeasonEpisodes) { episode in
                                episodeCard(episode)
                                    .onAppear {
                                        Task {
                                            await loadMoreEpisodesIfNeeded(current: episode)
                                        }
                                    }
                            }

                            if store.hasMoreEpisodes || store.isLoadingMoreEpisodes {
                                LoadingIndicatorView()
                                    .frame(width: 44, height: 112)
                                    .onAppear {
                                        Task {
                                            await store.loadMoreEpisodes(item: item, modelContext: modelContext)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal,15)
                    }
                    .frame(height: 172)
                }
            }
        }
    }

    private func episodeCard(_ episode: EpisodeInfo) -> some View {
        Button {
            let episodeItem = store.makeEpisodeItem(from: episode, show: item)
            appState.play(episodeItem)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let backdropURL = episode.backdropURL {
                        MacRemoteImage(url: backdropURL)
                    } else {
                        theme.secondaryButtonBackground
                    }
                }
                .frame(width: 200, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 4)

                Text(episode.title.isEmpty ? "第 \(episode.episodeNumber) 集" : "\(episode.episodeNumber) \(episode.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)
                    .frame(width: 200, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadMoreEpisodesIfNeeded(current episode: EpisodeInfo) async {
        guard store.hasMoreEpisodes, !store.isLoadingMoreEpisodes, !store.isLoadingEpisodes else { return }
        let episodes = store.currentSeasonEpisodes
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }) else { return }
        guard index >= episodes.count - 4 else { return }
        await store.loadMoreEpisodes(item: item, modelContext: modelContext)
    }

    @ViewBuilder
    private var collectionsSection: some View {
        let collections = store.content?.collections ?? []
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("Collections")
                    .font(MacDesignTokens.Typography.detailSectionTitle)
                    .foregroundStyle(theme.primaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(collections, id: \.serverId) { collection in
                            Button {
                                let collectionItem = store.makeCollectionItem(
                                    collection,
                                    sourceConnectionId: item.sourceConnectionId
                                )
                                appState.openDetail(collectionItem)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    MacRemoteImage(url: collection.posterURL)
                                        .frame(width: 120, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Text(collection.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(2)
                                        .frame(width: 120, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var castSection: some View {
        Group {
            let members = castMembers
            if !members.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Cast & Crew")
                        .font(MacDesignTokens.Typography.detailSectionTitle)
                        .foregroundStyle(theme.primaryText)
                        .padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 24) {
                            ForEach(members) { member in
                                VStack(spacing: 12) {
                                    MacRemoteImage(url: member.profileURL)
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())

                                    Text(member.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .multilineTextAlignment(.center)

                                    if let role = member.role, !role.isEmpty {
                                        Text(role)
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.cardSubtitle)
                                            .multilineTextAlignment(.center)
                                            .frame(width: 112)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            appState.closeDetail()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left")
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(theme.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 12)
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.chipText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.chipBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip)
                    .stroke(theme.chipBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip))
    }

    private var metadataDot: some View {
        Text("•")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.secondaryText)
    }

    private var displayTitle: String {
        item.showTitle ?? item.title
    }

    private var detailItemKey: String {
        if let serverId = item.serverId {
            return "server:\(serverId)"
        }
        return "local:\(item.id.uuidString)"
    }

    private var isContentReady: Bool {
        !store.isLoading && store.content != nil
    }

    private var displayOverview: String? {
        store.content?.enrichedOverview ?? item.overview
    }

    private var displayGenres: [String] {
        let enriched = store.content?.enrichedGenres ?? []
        return enriched.isEmpty ? item.genres : enriched
    }

    private var episodeCountText: String {
        let count = store.episodeTotalCount
        if count == 0 {
            return "Episodes"
        }
        return "本季 \(count) 集"
    }

    private var castMembers: [CastMemberDisplay] {
        if let members = store.content?.castMembers, !members.isEmpty {
            return members
        }
        return item.cast.prefix(5).map { name in
            CastMemberDisplay(id: name, name: name, role: nil, profileURL: nil)
        }
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding {
            store.favoriteErrorMessage != nil
        } set: { isPresented in
            if !isPresented { store.favoriteErrorMessage = nil }
        }
    }

    private var refreshErrorBinding: Binding<Bool> {
        Binding {
            store.refreshErrorMessage != nil
        } set: { isPresented in
            if !isPresented { store.refreshErrorMessage = nil }
        }
    }
}

#Preview {
    MacMediaDetailView(item: MacMediaDetailPreviewItem.make())
        .environmentObject(MacAppState())
        .macTheme(.dark)
        .frame(width: 1214, height: 836)
}

private struct MacMediaDetailTitleLogoView: View {
    let title: String
    let logoURL: URL?

    var body: some View {
        MediaTitleLogoView(
            title: title,
            logoURL: logoURL,
            titleFont: MacDesignTokens.Typography.detailHeroTitle,
            maxLogoHeight: 88,
            contentAlignment: .leading
        )
        .frame(maxWidth: 720, alignment: .leading)
    }
}

private enum MacMediaDetailPreviewItem {
    static func make() -> MediaItem {
        let item = MediaItem(
            title: "Preview Title",
            fileURL: URL(fileURLWithPath: "/tmp/preview.mkv"),
            mediaType: .movie,
            fileSize: 0,
            duration: 7200
        )
        item.overview = "Preview overview for media detail layout."
        item.year = 2024
        item.rating = 0.92
        item.genres = ["Drama", "History"]
        return item
    }
}
