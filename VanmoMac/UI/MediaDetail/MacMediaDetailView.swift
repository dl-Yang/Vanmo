import SwiftUI
import SwiftData
import VanmoCore

struct MacMediaDetailView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macTheme) private var theme
    @AppStorage("metadata.autoDownload") private var metadataAutoDownload = true

    let item: MediaItem
    let focusedEpisode: MacEpisodeDetailLocator?

    @StateObject private var store = MacMediaDetailStore()
    @State private var mediaPurgeHandlerId: UUID?
    @State private var isDownloadPickerPresented = false
    @State private var selectedDownloadEpisodes: [String: EpisodeInfo] = [:]
    @State private var downloadErrorMessage: String?
    @State private var isEnqueueingDownload = false

    init(item: MediaItem, focusedEpisode: MacEpisodeDetailLocator? = nil) {
        self.item = item
        self.focusedEpisode = focusedEpisode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                observedHeroSection
                contentSection
            }
        }
        .background(theme.appBackground)
        .task(id: detailItemKey) {
            await store.load(
                item: item,
                modelContext: modelContext,
                autoDownloadMetadata: metadataAutoDownload
            )
#if DEBUG
            store.installDebugHeroWalkEpisodesIfNeeded(for: item)
            if DownloadHeroWalkFixtures.shouldAutoEnqueue {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if item.mediaType == .tvShow {
                    selectedDownloadEpisodes = Dictionary(
                        uniqueKeysWithValues: store.seasonEpisodes.map { ($0.id, $0) }
                    )
                    enqueueSelectedEpisodes()
                } else {
                    beginDownload()
                }
            }
#endif
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
        .alert(L10n.tr("收藏失败"), isPresented: favoriteErrorBinding) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(store.favoriteErrorMessage ?? "")
        }
        .modifier(MacMediaDetailRefreshErrorPresenter(state: store.actionState))
        .alert(L10n.tr("下载失败"), isPresented: Binding(
            get: { downloadErrorMessage != nil },
            set: { if !$0 { downloadErrorMessage = nil } }
        )) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(downloadErrorMessage ?? "")
        }
        .sheet(isPresented: $isDownloadPickerPresented) {
            MacMediaDetailObservedObject(state: store.episodeState) { episodeState in
                MacEpisodeDownloadPicker(
                    episodes: episodeState.episodes,
                    seasonNumbers: episodeState.seasons.map(\.seasonNumber),
                    selectedSeason: episodeState.selectedSeason,
                    selectedEpisodes: $selectedDownloadEpisodes,
                    isLoading: episodeState.isLoading || episodeState.isLoadingMore,
                    isConfirming: isEnqueueingDownload,
                    onSelectSeason: { season in
                        Task {
                            await store.selectSeason(season, item: item, modelContext: modelContext)
                            await loadAllEpisodesForDownload()
                        }
                    },
                    onConfirm: enqueueSelectedEpisodes
                )
                .macTheme(theme)
            }
        }
    }

    private var observedHeroSection: some View {
        MacMediaDetailObservedObject(state: store.summaryState) { summaryState in
            MacMediaDetailObservedObject(state: store.episodeState) { episodeState in
                heroSection(summaryState: summaryState, episodeState: episodeState)
            }
        }
    }

    private func heroSection(
        summaryState: MacMediaDetailSummaryState,
        episodeState: MacMediaDetailEpisodeState
    ) -> some View {
        ZStack(alignment: .topLeading) {
            // 全宽剧照背景 + 渐隐遮罩
            ZStack(alignment: .topLeading) {
                MacRemoteImage(
                    url: summaryState.content?.backdropURL ?? item.backdropURL ?? item.posterURL
                )
                .frame(height: MacDesignTokens.Layout.heroHeight)
                .frame(maxWidth: .infinity)
                .clipped()
                .opacity(theme.isDark ? 0.56 : 0.38)

                LinearGradient(
                    stops: [
                        .init(color: theme.appBackground.opacity(0.24), location: 0),
                        .init(color: theme.appBackground.opacity(0.62), location: 0.48),
                        .init(color: theme.appBackground, location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: MacDesignTokens.Layout.heroHeight + 10)

                LinearGradient(
                    colors: [
                        theme.appBackground.opacity(0.78),
                        theme.appBackground.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 640, height: MacDesignTokens.Layout.heroHeight + 10)
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 20) {
                detailTopNavBar
                splitHeroHeader(summaryState: summaryState, episodeState: episodeState)
            }
            .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
            .padding(.top, 18)
        }
    }

    private var detailTopNavBar: some View {
        HStack(spacing: 12) {
            Button {
                appState.closeDetail()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 34, height: 34)
                    .background(theme.surfaceGlass, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.strokeGlass, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(L10n.tr("返回上一步"))

            Text(breadcrumbTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
    }

    private var breadcrumbTitle: String {
        var parts = [L10n.tr("媒体库")]
        if let genre = item.genres.first, !genre.isEmpty {
            parts.append(genre)
        } else {
            parts.append(item.mediaType.displayName)
        }
        parts.append(displayTitle)
        return parts.joined(separator: "  ›  ")
    }

    private func splitHeroHeader(
        summaryState: MacMediaDetailSummaryState,
        episodeState: MacMediaDetailEpisodeState
    ) -> some View {
        HStack(alignment: .top, spacing: 28) {
            MacRemoteImage(url: item.posterURL ?? summaryState.content?.backdropURL ?? item.backdropURL)
                .frame(width: 182, height: 268)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(theme.strokeGlass, lineWidth: 1)
                }
                .shadow(
                    color: Color.black.opacity(theme.isDark ? 0.6 : 0.16),
                    radius: 18,
                    y: 10
                )

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    MacMediaDetailTitleLogoView(
                        title: displayTitle,
                        logoURL: summaryState.content?.logoURL ?? item.logoURL
                    )

                    if let tagline = heroTagline(episodeState: episodeState) {
                        Text(tagline)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                metadataPillsRow(summaryState: summaryState, episodeState: episodeState)

                if let overview = displayOverview(summaryState: summaryState), !overview.isEmpty {
                    Text(overview)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.secondaryText)
                        .lineSpacing(5)
                        .frame(maxWidth: 680, alignment: .leading)
                        .lineLimit(4)
                }

                actionButtonsRow(episodeState: episodeState)
            }
            .padding(.top, 6)
        }
    }

    private func heroTagline(episodeState: MacMediaDetailEpisodeState) -> String? {
        var parts: [String] = []
        if item.mediaType == .tvShow {
            let season = episodeState.selectedSeason ?? episodeState.seasons.first?.seasonNumber ?? 1
            parts.append(LocalizedFormat.seasonLabel(season))
            if episodeState.totalCount > 0 {
                parts.append(L10n.tr("%d 集", episodeState.totalCount))
            }
        } else if let genres = item.genres.prefix(2) as ArraySlice<String>?, !genres.isEmpty {
            parts.append(genres.joined(separator: " / "))
        }
        if let connId = item.sourceConnectionId,
           let conn = connectionsViewModel.savedConnections.first(where: { $0.id == connId }) {
            parts.append(conn.name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func metadataPillsRow(
        summaryState: MacMediaDetailSummaryState,
        episodeState: MacMediaDetailEpisodeState
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let rating = item.rating, rating > 0 {
                    let score = rating <= 1.0 ? rating * 10.0 : rating
                    Text(String(format: "★ %.1f", score))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(theme.accentAmber)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(theme.amberTintFill, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.85)
                        }
                }

                if let year = item.year {
                    metadataChip(String(year))
                }

                if item.duration > 0 {
                    let durationLabel = item.mediaType == .tvShow
                        ? L10n.tr("%@ / 集", MacFormatters.formatDuration(item.duration))
                        : MacFormatters.formatDuration(item.duration)
                    metadataChip(durationLabel)
                }

                if let height = item.videoHeight {
                    if height >= 2000 {
                        metadataChip("4K")
                    } else if height >= 1000 {
                        metadataChip("1080p")
                    }
                }

                if let dr = item.dynamicRange, !dr.isEmpty {
                    metadataChip(dr.uppercased())
                }

                ForEach(displayGenres(summaryState: summaryState).prefix(2), id: \.self) { genre in
                    metadataChip(genre)
                }

                if item.isWatched {
                    metadataChip(L10n.tr("已看"))
                }
            }
        }
    }

    private func actionButtonsRow(episodeState: MacMediaDetailEpisodeState) -> some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 12) {
                playButton(episodeState: episodeState)
                favoriteButton
                downloadButton
                observedMoreMenu
            }
            .padding(.leading, 34)
            .padding(.top, 14)

            Image("MacCatPerchingPlay")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 66)
                .offset(x: -4, y: -1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func playButton(episodeState: MacMediaDetailEpisodeState) -> some View {
        let isPlayDisabled = item.mediaType == .tvShow && store.nextEpisodeToPlay == nil
        return Button {
            if item.mediaType == .tvShow {
                guard let episode = store.nextEpisodeToPlay else { return }
                let episodeItem = store.makeEpisodeItem(from: episode, show: item)
                appState.play(episodeItem)
            } else {
                let startPosition = UserDefaults.standard.bool(forKey: "playback.resumePlayback")
                    ? item.lastPlaybackPosition
                    : 0
                appState.play(item, from: startPosition)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accentAmber)

                Text(L10n.tr("立即播放"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.accentAmber)

                if item.mediaType == .tvShow, let next = store.nextEpisodeToPlay ?? episodeState.episodes.first {
                    Text(String(format: "S%02d E%02d", next.seasonNumber, next.episodeNumber))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                }
            }
            .padding(.leading, 30)
            .padding(.trailing, 22)
            .frame(height: 46)
            .background(theme.amberTintStrong, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.strokeAmber, lineWidth: 1.2)
            }
            .shadow(color: MacDesignTokens.glowAmber.opacity(0.16), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isPlayDisabled)
        .opacity(isPlayDisabled ? 0.72 : 1)
    }

    private var favoriteButton: some View {
        let isFav = store.isFavorite
        return Button {
            Task { await store.toggleFavorite(for: item, modelContext: modelContext) }
        } label: {
            Group {
                if store.isUpdatingFavorite {
                    ProgressView().controlSize(.small)
                } else {
                    Image("MacCatPawStamp")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(isFav ? theme.accentAmber : theme.secondaryText)
                }
            }
            .frame(width: 46, height: 46)
            .background(
                isFav ? theme.amberTintFill : theme.surfaceGlass,
                in: Circle()
            )
            .overlay {
                Circle()
                    .strokeBorder(isFav ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.9)
            }
        }
        .buttonStyle(.plain)
        .disabled(store.isUpdatingFavorite)
        .help(isFav ? L10n.tr("取消收藏") : L10n.tr("收藏"))
    }

    private var downloadButton: some View {
        Button(action: beginDownload) {
            HStack(spacing: 8) {
                MacDownloadProgressButtonContent(
                    task: displayedDownloadTask,
                    isEnqueueing: isEnqueueingDownload,
                    idleColor: theme.primaryText,
                    accentColor: theme.accentAmber,
                    trackColor: theme.progressTrack,
                    successColor: theme.successGreen
                )

                Text(downloadButtonLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }
            .padding(.leading, 16)
            .padding(.trailing, 18)
            .frame(height: 46)
            .background(theme.surfaceGlass, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(
                        displayedDownloadTask?.status == .downloading ? theme.strokeAmber : theme.strokeGlass,
                        lineWidth: 0.9
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(isDownloadButtonDisabled)
        .help(item.mediaType == .tvShow ? L10n.tr("选择剧集下载") : L10n.tr("下载"))
        .macDownloadHeroFrame("source")
        .accessibilityIdentifier("download.detail.button")
    }

    private var downloadButtonLabel: String {
        guard item.mediaType != .tvShow, let task = displayedDownloadTask else {
            return L10n.tr("下载")
        }
        switch task.status {
        case .queued: return L10n.tr("等待中")
        case .downloading:
            return task.totalBytes > 0 ? "\(Int(task.progress * 100))%" : L10n.tr("下载中")
        case .paused: return L10n.tr("已暂停")
        case .completed: return L10n.tr("已下载")
        case .failed: return L10n.tr("下载")
        }
    }

    private var observedMoreMenu: some View {
        MacMediaDetailObservedObject(state: store.actionState) { actionState in
            moreMenu(actionState: actionState)
        }
    }

    private func moreMenu(actionState: MacMediaDetailActionState) -> some View {
        Menu {
            Button {
                Task { await store.toggleWatched(for: item, modelContext: modelContext) }
            } label: {
                Label(
                    item.isWatched ? L10n.tr("标记未看") : L10n.tr("标记已看"),
                    systemImage: item.isWatched ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            .disabled(store.isUpdatingWatched)

            Button {
                Task { await store.refreshMetadata(for: item, modelContext: modelContext, force: true) }
            } label: {
                Label(L10n.tr("刷新元数据"), systemImage: "arrow.clockwise")
            }
            .disabled(actionState.isRefreshingMetadata)
        } label: {
            Image("MacMoreDots")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(theme.primaryText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 46, height: 46)
        .background(theme.surfaceGlass, in: Circle())
        .overlay {
            Circle()
                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
        }
        .fixedSize()
        .help(L10n.tr("更多"))
    }

    // MARK: - Content Sections

    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 26) {
            observedEpisodesSection
            observedCollectionsSection
            observedCastSection
        }
        .padding(.horizontal, MacDesignTokens.Layout.detailContentPadding)
        .padding(.top, 24)
        .padding(.bottom, 48)
    }

    private var observedEpisodesSection: some View {
        MacMediaDetailObservedObject(state: store.episodeState) { episodeState in
            episodesSection(episodeState: episodeState)
        }
    }

    @ViewBuilder
    private func episodesSection(episodeState: MacMediaDetailEpisodeState) -> some View {
        if item.mediaType == .tvShow {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(L10n.tr("剧集"))
                        .font(MacDesignTokens.Typography.detailSectionTitle)
                        .foregroundStyle(theme.primaryText)

                    if !episodeState.seasons.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(episodeState.seasons) { season in
                                    let selectedSeason = episodeState.selectedSeason ?? episodeState.seasons.first?.seasonNumber ?? 1
                                    let isSelected = season.seasonNumber == selectedSeason
                                    Button {
                                        Task {
                                            await store.selectSeason(season.seasonNumber, item: item, modelContext: modelContext)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(LocalizedFormat.seasonLabel(season.seasonNumber))
                                            if isSelected {
                                                Text("▾")
                                                    .font(.system(size: 10))
                                            }
                                        }
                                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                                        .padding(.horizontal, 12)
                                        .frame(height: 28)
                                        .background(
                                            isSelected ? theme.amberTintFill : theme.surfacePill,
                                            in: Capsule()
                                        )
                                        .overlay {
                                            if isSelected {
                                                Capsule()
                                                    .strokeBorder(theme.strokeAmber, lineWidth: 0.85)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 10) {
                        Image("MacStretchingCat")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 14)
                            .foregroundStyle(theme.secondaryText.opacity(0.75))

                        if episodeState.totalCount > 0 {
                            Text(L10n.tr("%d 集", episodeState.totalCount))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                }

                if episodeState.isLoading && episodeState.episodes.isEmpty {
                    LoadingIndicatorView()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else if episodeState.episodes.isEmpty {
                    Text(L10n.tr("暂无季集数据"))
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 18) {
                                ForEach(episodeState.episodes) { episode in
                                    episodeCard(episode)
                                        .id(episode.id)
                                        .onAppear {
                                            Task {
                                                await loadMoreEpisodesIfNeeded(current: episode)
                                            }
                                        }
                                }

                                if episodeState.hasMore || episodeState.isLoadingMore {
                                    LoadingIndicatorView()
                                        .frame(width: 44, height: 118)
                                        .onAppear {
                                            Task {
                                                await store.loadMoreEpisodes(item: item, modelContext: modelContext)
                                            }
                                        }
                                }
                            }
                        }
                        .task(id: focusedEpisode) {
                            await focusRequestedEpisode(using: proxy)
                        }
                    }
                }
            }
        }
    }

    private func episodeCard(_ episode: EpisodeInfo) -> some View {
        let isFocused = isFocusedEpisode(episode)
        let isNextToPlay = store.nextEpisodeToPlay?.id == episode.id
        let isHighlighted = isFocused || isNextToPlay

        return Button {
            let episodeItem = store.makeEpisodeItem(from: episode, show: item)
            appState.play(episodeItem)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    if let backdropURL = episode.backdropURL {
                        MacRemoteImage(url: backdropURL)
                    } else {
                        theme.surfaceGlass
                    }

                    LinearGradient(
                        colors: [Color.clear, MacDesignTokens.catSilhouette.opacity(0.91)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 64)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    VStack {
                        HStack {
                            Text(String(format: "E%02d", episode.episodeNumber))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
                                .overlay {
                                    Capsule()
                                        .strokeBorder(MacDesignTokens.Cinema.strokeGlass, lineWidth: 0.75)
                                }

                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(width: 210, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isHighlighted ? theme.strokeAmber : theme.strokeGlass,
                            lineWidth: isHighlighted ? 1.15 : 0.9
                        )
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(episode.title.isEmpty ? LocalizedFormat.episodeLabel(episode.episodeNumber) : episode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(episodeSubtitle(episode))
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(isHighlighted ? theme.accentAmber : theme.secondaryText)
                        .lineLimit(1)
                }
                .frame(width: 210, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private func episodeSubtitle(_ episode: EpisodeInfo) -> String {
        if episode.duration > 0 {
            return MacFormatters.formatDuration(episode.duration)
        }
        return LocalizedFormat.episodeLabel(episode.episodeNumber)
    }

    private func loadMoreEpisodesIfNeeded(current episode: EpisodeInfo) async {
        guard store.hasMoreEpisodes, !store.isLoadingMoreEpisodes, !store.isLoadingEpisodes else { return }
        let episodes = store.currentSeasonEpisodes
        guard let index = episodes.firstIndex(where: { $0.id == episode.id }) else { return }
        guard index >= episodes.count - 4 else { return }
        await store.loadMoreEpisodes(item: item, modelContext: modelContext)
    }

    private func focusRequestedEpisode(using proxy: ScrollViewProxy) async {
        guard let focusedEpisode, item.mediaType == .tvShow else { return }
        if store.selectedSeason != focusedEpisode.seasonNumber {
            await store.selectSeason(
                focusedEpisode.seasonNumber,
                item: item,
                modelContext: modelContext
            )
        }

        var remainingPages = 100
        while focusedEpisodeID == nil, store.hasMoreEpisodes, remainingPages > 0 {
            await store.loadMoreEpisodes(item: item, modelContext: modelContext)
            remainingPages -= 1
        }
        guard let focusedEpisodeID else { return }
        await Task.yield()
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(focusedEpisodeID, anchor: .center)
        }
    }

    private var focusedEpisodeID: String? {
        store.currentSeasonEpisodes.first(where: isFocusedEpisode)?.id
    }

    private func isFocusedEpisode(_ episode: EpisodeInfo) -> Bool {
        guard let focusedEpisode else { return false }
        if let serverID = focusedEpisode.serverID {
            return episode.id == serverID
        }
        return episode.seasonNumber == focusedEpisode.seasonNumber
            && episode.episodeNumber == focusedEpisode.episodeNumber
    }

    @ViewBuilder
    private var observedCollectionsSection: some View {
        MacMediaDetailObservedObject(state: store.collectionState) { collectionState in
            collectionsSection(collections: collectionState.items)
        }
    }

    @ViewBuilder
    private func collectionsSection(collections: [ServerMediaItem]) -> some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MacCatSectionHeaderRow(
                    title: L10n.tr("合集"),
                    showsStretchingCat: false
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(collections, id: \.serverId) { collection in
                            MacPosterCard(
                                title: collection.title,
                                subtitle: collection.year.map(String.init) ?? collection.mediaType.displayName,
                                posterURL: collection.posterURL,
                                width: 132,
                                height: 192
                            ) {
                                let collectionItem = store.makeCollectionItem(
                                    collection,
                                    sourceConnectionId: item.sourceConnectionId
                                )
                                appState.openDetail(collectionItem)
                            }
                        }
                    }
                }
            }
        }
    }

    private var observedCastSection: some View {
        MacMediaDetailObservedObject(state: store.castState) { castState in
            castSection(members: castState.members)
        }
    }

    private func castSection(members: [CastMemberDisplay]) -> some View {
        Group {
            if !members.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.tr("演职人员"))
                        .font(MacDesignTokens.Typography.detailSectionTitle)
                        .foregroundStyle(theme.primaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 22) {
                            ForEach(members) { member in
                                VStack(spacing: 8) {
                                    MacRemoteImage(url: member.profileURL)
                                        .frame(width: 78, height: 78)
                                        .clipShape(Circle())
                                        .overlay {
                                            Circle()
                                                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                                        }

                                    Text(member.name)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(theme.primaryText)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(1)
                                        .frame(width: 96)

                                    if let role = member.role, !role.isEmpty {
                                        Text(role)
                                            .font(.system(size: 11))
                                            .foregroundStyle(theme.secondaryText)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(1)
                                            .frame(width: 96)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.chipText)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(theme.chipBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.chipBorder, lineWidth: 0.8)
            }
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

    private var displayedDownloadTask: DownloadTaskSnapshot? {
        let related = downloadManager.tasks.filter { isRelatedDownloadRequest($0.request) }
        if let downloading = related.first(where: { $0.status == .downloading }) {
            return downloading
        }
        if let queued = related
            .filter({ $0.status == .queued })
            .min(by: { $0.createdAt < $1.createdAt }) {
            return queued
        }
        if let paused = related
            .filter({ $0.status == .paused })
            .min(by: { $0.createdAt < $1.createdAt }) {
            return paused
        }
        guard !related.isEmpty, related.allSatisfy({ $0.status == .completed }) else {
            return nil
        }
        return related.max(by: { $0.updatedAt < $1.updatedAt })
    }

    private var isDownloadButtonDisabled: Bool {
        guard !isEnqueueingDownload else { return true }
        guard item.mediaType != .tvShow, let task = displayedDownloadTask else { return false }
        return task.status == .queued || task.status == .downloading || task.status == .paused
    }

    private func isRelatedDownloadRequest(_ request: DownloadRequest) -> Bool {
        guard request.sourceConnectionId == item.sourceConnectionId else { return false }
        if item.mediaType == .tvShow {
            let seriesID = item.serverId ?? item.seriesId
            return request.mediaType == .tvEpisode
                && (request.sourceMediaItemID == item.id
                    || (seriesID != nil && request.seriesServerID == seriesID)
                    || (request.seriesServerID == nil && request.showTitle == displayTitle))
        }
        if request.sourceMediaItemID == item.id {
            return true
        }
        if let serverID = item.serverId, request.sourceServerID == serverID {
            return true
        }
        if let sourceURL = request.sourceFileURL {
            return sourceURL.standardizedFileURL == item.fileURL.standardizedFileURL
        }
        let expectedPath = request.connectionType == .plex
            ? item.fileURL.path
            : (item.serverId ?? item.fileURL.path)
        return request.remotePath == expectedPath
    }

    private func displayOverview(summaryState: MacMediaDetailSummaryState) -> String? {
        summaryState.content?.enrichedOverview ?? item.overview
    }

    private func displayGenres(summaryState: MacMediaDetailSummaryState) -> [String] {
        let enriched = summaryState.content?.enrichedGenres ?? []
        return enriched.isEmpty ? item.genres : enriched
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding {
            store.favoriteErrorMessage != nil
        } set: { isPresented in
            if !isPresented { store.favoriteErrorMessage = nil }
        }
    }

    private func beginDownload() {
        guard !isEnqueueingDownload else { return }
        if item.mediaType == .tvShow {
            guard !isDownloadPickerPresented else { return }
            selectedDownloadEpisodes.removeAll()
            isDownloadPickerPresented = true
            Task { await loadAllEpisodesForDownload() }
        } else {
            isEnqueueingDownload = true
            Task {
                defer { isEnqueueingDownload = false }
                do {
                    let request = try DownloadRequestFactory.make(
                        from: item,
                        connectionType: try sourceConnectionType()
                    )
                    try await downloadManager.enqueue(request)
                    MacDownloadHeroController.request(
                        title: DownloadActivityPresentation.title(for: request),
                        posterURL: request.postUrl ?? item.posterURL
                    )
#if DEBUG
                    VanmoLogger.library.info("[Debug][Downloads] enqueued source=detail mediaType=\(item.mediaType.rawValue, privacy: .public) connection=\(request.connectionType?.rawValue ?? "none", privacy: .public)")
#endif
                } catch {
                    downloadErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func loadAllEpisodesForDownload() async {
        var remainingPages = 100
        while store.hasMoreEpisodes, remainingPages > 0 {
            await store.loadMoreEpisodes(item: item, modelContext: modelContext)
            remainingPages -= 1
        }
    }

    private func enqueueSelectedEpisodes() {
        let episodes = selectedDownloadEpisodes.values.sorted {
            ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber)
        }
        guard !episodes.isEmpty, !isEnqueueingDownload else { return }
        isEnqueueingDownload = true
        Task {
            defer { isEnqueueingDownload = false }
            do {
                let connectionType = try sourceConnectionType()
                let requests = try episodes.map {
                    try DownloadRequestFactory.make(
                        from: $0,
                        show: item,
                        connectionType: connectionType
                    )
                }
                try await downloadManager.enqueue(requests)
                if let first = requests.first {
                    MacDownloadHeroController.request(
                        title: DownloadActivityPresentation.title(for: first),
                        posterURL: first.postUrl ?? item.posterURL
                    )
                }
#if DEBUG
                VanmoLogger.library.info("[Debug][Downloads] enqueued source=detail-episodes count=\(requests.count, privacy: .public) connection=\(connectionType?.rawValue ?? "none", privacy: .public)")
#endif
                isDownloadPickerPresented = false
                selectedDownloadEpisodes.removeAll()
            } catch {
                downloadErrorMessage = error.localizedDescription
            }
        }
    }

    private func sourceConnectionType() throws -> ConnectionType? {
        guard let connectionId = item.sourceConnectionId else { return nil }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        return try modelContext.fetch(descriptor).first?.type
    }
}

private struct MacMediaDetailRefreshErrorPresenter: ViewModifier {
    @ObservedObject var state: MacMediaDetailActionState

    private var isPresented: Binding<Bool> {
        Binding {
            state.refreshErrorMessage != nil
        } set: { value in
            if !value {
                state.refreshErrorMessage = nil
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .alert(L10n.tr("刷新失败"), isPresented: isPresented) {
                Button(L10n.tr("确定")) {}
            } message: {
                Text(state.refreshErrorMessage ?? "")
            }
    }
}

private struct MacMediaDetailObservedObject<State: ObservableObject, Content: View>: View {
    @ObservedObject var state: State
    private let content: (State) -> Content

    init(
        state: State,
        @ViewBuilder content: @escaping (State) -> Content
    ) {
        self.state = state
        self.content = content
    }

    var body: some View {
        content(state)
    }
}

private struct MacDownloadProgressButtonContent: View {
    let task: DownloadTaskSnapshot?
    let isEnqueueing: Bool
    let idleColor: Color
    let accentColor: Color
    let trackColor: Color
    let successColor: Color

    var body: some View {
        Group {
            if let task {
                taskContent(task)
            } else if isEnqueueing {
                indicator(progress: nil, color: accentColor)
            } else {
                Image("MacDownloadsTray")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(idleColor)
            }
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func taskContent(_ task: DownloadTaskSnapshot) -> some View {
        switch task.status {
        case .queued:
            indicator(progress: nil, color: accentColor)
        case .downloading:
            indicator(
                progress: task.totalBytes > 0 ? task.progress : nil,
                color: accentColor
            )
        case .paused:
            indicator(
                progress: task.progress,
                color: accentColor,
                symbol: "pause.fill"
            )
        case .completed:
            indicator(progress: 1, color: successColor, symbol: "checkmark")
        case .failed:
            Image("MacDownloadsTray")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(idleColor)
        }
    }

    private func indicator(
        progress: Double?,
        color: Color,
        symbol: String? = nil
    ) -> some View {
        MacCircularDownloadIndicator(
            progress: progress,
            color: color,
            trackColor: trackColor,
            symbol: symbol
        )
    }
}

private struct MacCircularDownloadIndicator: View {
    let progress: Double?
    let color: Color
    let trackColor: Color
    let symbol: String?
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 2)
            progressArc
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 20, height: 20)
        .onAppear(perform: startAnimatingIfNeeded)
        .onChange(of: progress == nil) { _, _ in
            startAnimatingIfNeeded()
        }
    }

    @ViewBuilder
    private var progressArc: some View {
        if let progress {
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        } else {
            Circle()
                .trim(from: 0.05, to: 0.32)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(rotation - 90))
        }
    }

    private func startAnimatingIfNeeded() {
        guard progress == nil else { return }
        rotation = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct MacEpisodeDownloadPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macTheme) private var theme

    let episodes: [EpisodeInfo]
    let seasonNumbers: [Int]
    let selectedSeason: Int?
    @Binding var selectedEpisodes: [String: EpisodeInfo]
    let isLoading: Bool
    let isConfirming: Bool
    let onSelectSeason: (Int) -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.tr("选择下载剧集"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Picker(L10n.tr("季"), selection: Binding(
                    get: { selectedSeason ?? seasonNumbers.first ?? 1 },
                    set: onSelectSeason
                )) {
                    ForEach(seasonNumbers, id: \.self) { season in
                        Text(LocalizedFormat.seasonLabel(season)).tag(season)
                    }
                }
                .frame(width: 120)
                .disabled(isConfirming)
            }
            .padding()

            HStack {
                Button(allCurrentSeasonSelected ? L10n.tr("取消全选本季") : L10n.tr("全选本季")) {
                    toggleCurrentSeason()
                }
                .buttonStyle(MacCatGlassButtonStyle(height: 30, horizontalPadding: 12))
                .disabled(isConfirming)
                Spacer()
                if isLoading || isConfirming { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                ForEach(Array(episodes.enumerated()), id: \.offset) { _, episode in
                    let isSelected = selectedEpisodes[episode.id] != nil
                    Button {
                        toggle(episode)
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                            Text("\(LocalizedFormat.episodeLabel(episode.episodeNumber)) · \(episode.title)")
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            if episode.duration > 0 {
                                Text(MacFormatters.formatDuration(episode.duration))
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .disabled(isConfirming)
                }
            }
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button(L10n.tr("取消")) { dismiss() }
                    .buttonStyle(MacCatGlassButtonStyle(height: 34, horizontalPadding: 16))
                    .disabled(isConfirming)

                Button(confirmButtonTitle, action: onConfirm)
                    .buttonStyle(MacCatAmberButtonStyle(height: 34, horizontalPadding: 18))
                    .disabled(selectedEpisodes.isEmpty || isLoading || isConfirming)
            }
            .padding()
        }
        .background(theme.surfacePanel)
        .frame(minWidth: 520, minHeight: 480)
    }

    private var allCurrentSeasonSelected: Bool {
        !episodes.isEmpty && episodes.allSatisfy { selectedEpisodes[$0.id] != nil }
    }

    private var confirmButtonTitle: String {
        isConfirming ? L10n.tr("正在加入…") : L10n.tr("下载 %d 集", selectedEpisodes.count)
    }

    private func toggle(_ episode: EpisodeInfo) {
        if selectedEpisodes[episode.id] == nil {
            selectedEpisodes[episode.id] = episode
        } else {
            selectedEpisodes.removeValue(forKey: episode.id)
        }
    }

    private func toggleCurrentSeason() {
        if allCurrentSeasonSelected {
            episodes.forEach { selectedEpisodes.removeValue(forKey: $0.id) }
        } else {
            episodes.forEach { selectedEpisodes[$0.id] = $0 }
        }
    }
}

private struct MacMediaDetailTitleLogoView: View {
    let title: String
    let logoURL: URL?

    var body: some View {
        MediaTitleLogoView(
            title: title,
            logoURL: logoURL,
            titleFont: MacDesignTokens.Typography.detailHeroTitle,
            maxLogoHeight: 82,
            contentAlignment: .leading
        )
        .frame(maxWidth: 720, alignment: .leading)
    }
}

#Preview("Detail Dark") {
    MacMediaDetailView(item: MacMediaDetailPreviewItem.make())
        .environmentObject(MacAppState())
        .environmentObject(MacConnectionsViewModel())
        .environmentObject(DownloadManager.shared)
        .macTheme(.dark)
        .frame(width: 1199, height: 900)
}

#Preview("Detail Light") {
    MacMediaDetailView(item: MacMediaDetailPreviewItem.make())
        .environmentObject(MacAppState())
        .environmentObject(MacConnectionsViewModel())
        .environmentObject(DownloadManager.shared)
        .macTheme(.light)
        .frame(width: 1199, height: 900)
}

private enum MacMediaDetailPreviewItem {
    static func make() -> MediaItem {
        let item = MediaItem(
            title: "DUNE: PROPHECY",
            fileURL: URL(fileURLWithPath: "/tmp/preview.mkv"),
            mediaType: .tvShow,
            fileSize: 0,
            duration: 3480
        )
        item.overview = "Ten thousand years before the ascension of Paul Atreides, two Harkonnen sisters combat forces that threaten the future of humankind and establish the fabled sect known as the Bene Gesserit."
        item.year = 2024
        item.rating = 0.87
        item.genres = ["Sci-Fi"]
        item.videoHeight = 2160
        item.dynamicRange = "Dolby Vision"
        return item
    }
}
