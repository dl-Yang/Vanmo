import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("metadata.autoDownload") private var metadataAutoDownload = true

    let item: MediaItem

    @State private var isUpdatingFavorite = false
    @State private var isUpdatingWatched = false
    @State private var favoriteErrorMessage: String?
    @State private var watchedErrorMessage: String?
    @State private var isSynopsisExpanded = false
    @State private var isDownloadPickerPresented = false
    @State private var selectedDownloadEpisodes: [String: EpisodeInfo] = [:]
    @State private var downloadErrorMessage: String?
    @State private var isEnqueueingDownload = false
    @State private var scrollOffset: CGFloat = 0
    @State private var topSafeAreaInset: CGFloat = 0
    @StateObject private var store = MediaDetailStore()

    var body: some View {
        detailLayout
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .task(id: metadataTaskID) {
            await loadDetailContent()
        }
#if DEBUG
        .task(id: "\(item.id)-hero-auto-movie") {
            guard DownloadHeroWalkFixtures.shouldAutoEnqueue, item.mediaType != .tvShow else { return }
            await enqueueDebugHeroWalkIfNeeded()
        }
#endif
        .onChange(of: appState.isPlayerPresented) { _, isPresented in
            if !isPresented {
                store.syncLocalPlaybackStates(for: item, in: modelContext)
            }
        }
        .alert(L10n.tr("收藏失败"), isPresented: favoriteErrorBinding) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(favoriteErrorMessage ?? "")
        }
        .alert(L10n.tr("标记失败"), isPresented: watchedErrorBinding) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(watchedErrorMessage ?? "")
        }
        .modifier(MediaDetailRefreshErrorPresenter(state: store.actionState))
        .sheet(isPresented: $isDownloadPickerPresented) {
            episodeDownloadSheet
        }
        .alert(L10n.tr("下载失败"), isPresented: downloadErrorBinding) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(downloadErrorMessage ?? "")
        }
        .overlay {
            if isSynopsisExpanded {
                synopsisModalOverlay
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: isSynopsisExpanded)
    }

    // MARK: - Subviews

    /// The root stays inside the safe area so `safeAreaInsets` stays readable;
    /// only the backdrop, scroll view, and top bar extend under the status bar.
    private var detailLayout: some View {
        let heroTopAnchor = topSafeAreaInset > 0 ? topSafeAreaInset + 4 : 58
        let heroContentTopPadding = max(286, heroTopAnchor + 228)

        return ZStack(alignment: .top) {
            // Overlay keeps the stretching hero out of the ZStack's size calculation.
            CatDesign.bgObsidian
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    observedHeroBackdrop
                        .ignoresSafeArea(edges: .top)
                }

            ScrollView(.vertical, showsIndicators: false) {
                detailContentStack
                    .padding(.top, heroContentTopPadding)
                    .padding(.bottom, 34)
                    .containerRelativeFrame(.horizontal, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named("mediaDetailScroll")).minY
                    } action: { offset in
                        scrollOffset = offset
                    }
            }
            .coordinateSpace(name: "mediaDetailScroll")
            .ignoresSafeArea(edges: .top)

            floatingTopBar(topPadding: heroTopAnchor)
                .ignoresSafeArea(edges: .top)
                .zIndex(2)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            topSafeAreaInset = inset
        }
    }

    private var observedHeroBackdrop: some View {
        MediaDetailObservedObject(state: store.summaryState) { summaryState in
            MediaDetailHeroBackdrop(
                backdropURLs: resolvedHeroBackdrops(from: summaryState),
                fallbackPosterURL: summaryState.content?.posterURL ?? item.posterURL,
                scrollOffset: scrollOffset
            )
            .allowsHitTesting(false)
        }
    }

    private var detailContentStack: some View {
        VStack(alignment: .leading, spacing: 22) {
            heroTitleAndActionsBlock
            observedSynopsis
            if item.mediaType == .tvShow {
                observedEpisodes
            }
            observedCast
            observedCollections
            observedTechnicalSpecs
        }
    }

    private var heroTitleAndActionsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            observedTitleAndMeta
            observedPanelActions(play: handlePrimaryPlayTap)
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    private var observedTitleAndMeta: some View {
        MediaDetailObservedObject(state: store.summaryState) { summaryState in
            MediaDetailObservedObject(state: store.episodeState) { episodeState in
                MediaDetailObservedObject(state: store.technicalState) { technicalState in
                    MediaDetailTitleAndMetaBlock(
                        title: displayTitle,
                        logoURL: summaryState.content?.logoURL ?? item.logoURL,
                        metaText: heroMetaText(summaryState: summaryState, episodeState: episodeState),
                        badges: capabilityTags(summaryState: summaryState, technicalState: technicalState)
                    )
                }
            }
        }
    }

    private func floatingTopBar(topPadding: CGFloat) -> some View {
        let scrollProgress = min(max((-scrollOffset - 24) / 70, 0), 1)
        return HStack {
            topBackButton
            Spacer()
            observedMoreMenuButton
        }
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
        .padding(.bottom, 14)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: CatDesign.bgObsidian.opacity(0.96), location: 0.0),
                    .init(color: CatDesign.bgObsidian.opacity(0.92), location: 0.72),
                    .init(color: CatDesign.bgObsidian.opacity(0), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topPadding + 78)
            .opacity(scrollProgress)
            .allowsHitTesting(false)
        }
    }

    private var topBackButton: some View {
        Button {
            dismiss()
        } label: {
            Image("CatLGBack")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(topBarIconColor)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
                .detailLiquidGlass(in: Circle(), colorScheme: colorScheme)
        }
        
        .buttonStyle(DetailNavigationButtonStyle())
        .accessibilityLabel(L10n.tr("返回"))
    }

    private var observedMoreMenuButton: some View {
        MediaDetailObservedObject(state: store.actionState) { actionState in
            MediaDetailObservedObject(state: store.summaryState) { summaryState in
                Menu {
                    Button {
                        Task { await toggleWatched() }
                    } label: {
                        Label(
                            item.isWatched ? L10n.tr("标记未看") : L10n.tr("标记已看"),
                            systemImage: item.isWatched ? "checkmark.circle.fill" : "checkmark.circle"
                        )
                    }
                    .disabled(isUpdatingWatched)

                    if store.supportsMetadataRefresh(for: item, in: modelContext) {
                        Button {
                            Task {
                                await store.refreshMetadata(for: item, modelContext: modelContext, force: true)
                            }
                        } label: {
                            Label(L10n.tr("刷新元数据"), systemImage: "arrow.clockwise")
                        }
                        .disabled(actionState.isRefreshingMetadata)
                    }

                    ShareLink(item: shareSummaryText(from: summaryState)) {
                        Label(L10n.tr("分享"), systemImage: "square.and.arrow.up")
                    }
                } label: {
                    ZStack {
                        if actionState.isRefreshingMetadata || isUpdatingWatched {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(CatDesign.accentAmber)
                                .scaleEffect(0.72)
                        } else {
                            Image("CatLGMoreDots")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(topBarIconColor)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .detailLiquidGlass(in: Circle(), colorScheme: colorScheme)
                    .contentShape(Circle())
                }
                .accessibilityLabel(L10n.tr("更多"))
            }
        }
    }

    private var observedSynopsis: some View {
        MediaDetailObservedObject(state: store.summaryState) { summaryState in
            MediaDetailSynopsisCard(
                overview: displayOverview(from: summaryState)
            ) {
                isSynopsisExpanded = true
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
        }
    }

    private var observedEpisodes: some View {
        MediaDetailObservedObject(state: store.episodeState) { episodeState in
            MediaDetailEpisodesSection(
                episodes: episodeState.episodes,
                seasonNumbers: episodeState.seasons.map(\.seasonNumber),
                selectedSeason: Binding(
                    get: { episodeState.selectedSeason },
                    set: { season in
                        guard let season else { return }
                        Task {
                            await store.selectSeason(season, item: item, modelContext: modelContext)
                        }
                    }
                ),
                isLoadingEpisodes: episodeState.isLoading,
                isLoadingMore: episodeState.isLoadingMore,
                hasMoreEpisodes: episodeState.hasMore,
                onPlay: playEpisode,
                onLoadMore: {
                    Task {
                        await store.loadMoreEpisodes(item: item, modelContext: modelContext)
                    }
                }
            )
        }
    }

    private var observedCast: some View {
        MediaDetailObservedObject(state: store.castState) { castState in
            MediaDetailCastSection(members: castState.members)
        }
    }

    private var observedCollections: some View {
        MediaDetailObservedObject(state: store.collectionState) { collectionState in
            MediaDetailCollectionsSection(
                collections: collectionState.items,
                makeItem: makeCollectionItem
            )
        }
    }

    private var observedTechnicalSpecs: some View {
        MediaDetailObservedObject(state: store.technicalState) { technicalState in
            let chips = MediaCapabilityTags.mediaSpecificationChips(
                videoCodec: technicalState.videoCodec ?? item.videoCodec,
                bitDepth: technicalState.videoBitDepth,
                audioTracks: technicalState.audioTracks.isEmpty ? item.audioTracks : technicalState.audioTracks,
                bitRate: technicalState.bitRate,
                fileSize: item.fileSize,
                duration: item.duration
            )
            MediaDetailSpecsFooter(chips: chips)
        }
    }

    private func observedPanelActions(play: @escaping () -> Void) -> some View {
        MediaDetailPrimaryActionRow(
            isTVShow: item.mediaType == .tvShow,
            playButtonTitle: playButtonTitle,
            isFavorite: item.isFavorite,
            isUpdatingFavorite: isUpdatingFavorite,
            isRelatedDownload: isRelatedDownloadRequest,
            isEnqueueingDownload: isEnqueueingDownload,
            play: play,
            toggleFavorite: { Task { await setFavorite(!item.isFavorite) } },
            download: handleDownloadButtonTap
        )
    }

    private var episodeDownloadSheet: some View {
        MediaDetailObservedObject(state: store.episodeState) { episodeState in
            EpisodeDownloadPicker(
                episodes: episodeState.episodes,
                seasonNumbers: episodeState.seasons.map(\.seasonNumber),
                selectedSeason: episodeState.selectedSeason,
                selectedEpisodes: $selectedDownloadEpisodes,
                isLoading: episodeState.isLoading || episodeState.isLoadingMore,
                onSelectSeason: { season in
                    Task {
                        await store.selectSeason(season, item: item, modelContext: modelContext)
                        await loadAllEpisodesForDownload()
                    }
                },
                onConfirm: enqueueSelectedEpisodes
            )
        }
    }

    private var synopsisModalOverlay: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { isSynopsisExpanded = false }
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L10n.tr("简介"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)

                    Spacer()

                    Button { isSynopsisExpanded = false } label: {
                        Image("CatClearCircle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 20)

                ScrollView {
                    MediaDetailObservedObject(state: store.summaryState) { summaryState in
                        Text(displayOverview(from: summaryState) ?? L10n.tr("暂无简介"))
                            .font(.system(size: 14))
                            .lineSpacing(7)
                            .foregroundStyle(CatDesign.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                    }
                }
                .frame(maxHeight: 360)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .catGlassCard(cornerRadius: 24, elevated: true)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Formatting & Computed State

    private var topBarIconColor: Color {
        colorScheme == .dark ? CatDesign.Cinema.textIvory : CatDesign.textIvory
    }

    private var metadataTaskID: String {
        MetadataCacheKey.from(item).cacheKey
    }

    private var displayTitle: String {
        item.mediaType == .tvShow ? (item.showTitle ?? item.title) : item.displayTitle
    }

    private var playButtonTitle: String {
        if item.mediaType != .tvShow,
           item.lastPlaybackPosition > 0,
           !item.isWatched,
           item.duration > item.lastPlaybackPosition {
            return L10n.tr("继续播放")
        }
        return L10n.tr("立即播放")
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding {
            favoriteErrorMessage != nil
        } set: { isPresented in
            if !isPresented { favoriteErrorMessage = nil }
        }
    }

    private var watchedErrorBinding: Binding<Bool> {
        Binding {
            watchedErrorMessage != nil
        } set: { isPresented in
            if !isPresented { watchedErrorMessage = nil }
        }
    }

    private var downloadErrorBinding: Binding<Bool> {
        Binding {
            downloadErrorMessage != nil
        } set: { isPresented in
            if !isPresented { downloadErrorMessage = nil }
        }
    }

    private func resolvedHeroBackdrops(from summaryState: MediaDetailSummaryState) -> [URL] {
        if let backdrops = summaryState.content?.backdropURLs, !backdrops.isEmpty {
            return backdrops
        }
        if let localBackdrop = item.backdropURL {
            return [localBackdrop]
        }
        return []
    }

    private func heroMetaText(
        summaryState: MediaDetailSummaryState,
        episodeState: MediaDetailEpisodeState
    ) -> String? {
        var parts: [String] = []
        if let year = summaryState.content?.year ?? item.year {
            parts.append("\(year)")
        }
        if let genre = displayGenres(from: summaryState).first {
            parts.append(genre)
        }
        if item.mediaType == .tvShow {
            if !episodeState.seasons.isEmpty {
                parts.append(L10n.tr("%d 季", episodeState.seasons.count))
            } else if item.duration > 0 {
                parts.append(item.duration.localizedShortDuration)
            }
        } else if item.duration > 0 {
            parts.append(item.duration.localizedShortDuration)
        }
        if let rating = summaryState.content?.rating ?? item.rating, rating > 0 {
            parts.append(String(format: "★ %.1f", rating))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    private func displayGenres(from summaryState: MediaDetailSummaryState) -> [String] {
        let genres = summaryState.content?.genres ?? []
        return genres.isEmpty ? item.genres : genres
    }

    private func displayOverview(from summaryState: MediaDetailSummaryState) -> String? {
        if let overview = summaryState.content?.overview, !overview.isEmpty { return overview }
        guard let overview = item.overview, !overview.isEmpty else { return nil }
        return overview
    }

    private func capabilityTags(
        summaryState: MediaDetailSummaryState,
        technicalState: MediaDetailTechnicalState
    ) -> [String] {
        MediaCapabilityTags.detailCapabilityBadges(
            contentRating: summaryState.content?.contentRating ?? item.contentRating,
            width: technicalState.videoWidth ?? item.videoWidth,
            height: technicalState.videoHeight ?? item.videoHeight,
            dynamicRange: technicalState.dynamicRange ?? item.dynamicRange,
            audioTracks: technicalState.audioTracks.isEmpty ? item.audioTracks : technicalState.audioTracks,
            fileName: [
                item.originalFileName,
                item.title,
                item.fileURL.lastPathComponent,
                technicalState.episodeFileNameHint
            ]
                .compactMap { $0 }
                .joined(separator: " ")
        )
    }

    private func shareSummaryText(from summaryState: MediaDetailSummaryState) -> String {
        let title = displayTitle
        let year = item.year.map { " (\($0))" } ?? ""
        let overview = displayOverview(from: summaryState)
        if let overview, !overview.isEmpty {
            return "\(title)\(year)\n\(overview)"
        }
        return "\(title)\(year)"
    }

    // MARK: - Actions & Loading

    private func loadDetailContent() async {
        store.syncLocalPlaybackStates(for: item, in: modelContext)
        let loadTask = Task {
            await store.load(
                item: item,
                modelContext: modelContext,
                autoDownloadMetadata: metadataAutoDownload
            )
        }
#if DEBUG
        await Task.yield()
        store.installDebugHeroWalkEpisodesIfNeeded(for: item)
#endif
        await loadTask.value
        store.syncLocalPlaybackStates(for: item, in: modelContext)
#if DEBUG
        if DownloadHeroWalkFixtures.shouldAutoEnqueue, item.mediaType == .tvShow {
            await enqueueDebugHeroWalkIfNeeded()
        }
#endif
    }

    private func handlePrimaryPlayTap() {
        if item.mediaType == .tvShow {
            if let ep = store.nextEpisodeToPlay {
                playEpisode(ep)
            }
        } else {
            appState.play(item)
        }
    }

    private func setFavorite(_ isFavorite: Bool) async {
        guard !isUpdatingFavorite else { return }

        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }

        let snapshot = try? mediaServerConnectionSnapshot()
        let writeMediaServer = shouldWriteMediaServerFavorite(snapshot)

        do {
            if writeMediaServer {
                try await EmbyFavoriteUpdater.setFavorite(
                    item,
                    isFavorite: isFavorite,
                    connection: snapshot
                )
            }
            let persisted = try persistFavoriteState(isFavorite)
            if persisted.isFavoriteCloudSynced {
                CloudSyncCoordinator.shared.markMediaFavoriteChanged(persisted, in: modelContext)
            }
            try modelContext.save()
            if persisted.isFavoriteCloudSynced {
                CloudSyncCoordinator.shared.requestSync(reason: "favorite", context: modelContext)
            }
            NotificationCenter.default.post(name: .mediaFavoriteDidChange, object: persisted)
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
    }

    private func toggleWatched() async {
        guard !isUpdatingWatched else { return }
        isUpdatingWatched = true
        defer { isUpdatingWatched = false }

        let targetWatched = !item.isWatched
        let previousPosition = item.lastPlaybackPosition
        let previousPlayedAt = item.lastPlayedAt

        item.isWatched = targetWatched
        if targetWatched {
            if item.duration > 0 {
                item.lastPlaybackPosition = item.duration
            }
            item.lastPlayedAt = Date()
        } else {
            item.lastPlaybackPosition = 0
        }

        do {
            let snapshot = try? mediaServerConnectionSnapshot()
            if item.serverId != nil,
               let snapshot,
               snapshot.type == .emby || snapshot.type == .jellyfin {
                try await EmbyPlayedUpdater.setPlayed(
                    item,
                    isPlayed: targetWatched,
                    connection: snapshot
                )
            }
            let persisted = try persistWatchedState(
                isWatched: targetWatched,
                position: item.lastPlaybackPosition,
                lastPlayedAt: item.lastPlayedAt
            )
            if persisted.isProgressCloudSynced {
                CloudSyncCoordinator.shared.markMediaProgressChanged(persisted, in: modelContext)
            }
            try modelContext.save()
            if persisted.isProgressCloudSynced {
                CloudSyncCoordinator.shared.requestSync(reason: "watched", context: modelContext)
            }
            if item.mediaType == .tvShow {
                store.applySeriesWatchedState(targetWatched, for: item, in: modelContext)
            }
        } catch {
            item.isWatched = !targetWatched
            item.lastPlaybackPosition = previousPosition
            item.lastPlayedAt = previousPlayedAt
            watchedErrorMessage = error.localizedDescription
        }
    }

    private func shouldWriteMediaServerFavorite(_ snapshot: MediaServerConnectionSnapshot?) -> Bool {
        if snapshot != nil { return true }
        if item.isFavoriteCloudSynced { return false }
        return item.serverId != nil
    }

    @discardableResult
    private func persistFavoriteState(_ isFavorite: Bool) throws -> MediaItem {
        item.isFavorite = isFavorite

        guard let serverId = item.serverId else {
            if item.modelContext == nil, isFavorite {
                modelContext.insert(item)
            }
            return item
        }

        let sourceConnectionId = item.sourceConnectionId
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.serverId == serverId &&
                    mediaItem.sourceConnectionId == sourceConnectionId
            }
        )
        if let storedItem = try modelContext.fetch(descriptor).first {
            storedItem.isFavorite = isFavorite
            return storedItem
        }
        if isFavorite, item.modelContext == nil {
            modelContext.insert(item)
        }
        return item
    }

    @discardableResult
    private func persistWatchedState(
        isWatched: Bool,
        position: TimeInterval,
        lastPlayedAt: Date?
    ) throws -> MediaItem {
        guard let serverId = item.serverId else {
            if item.modelContext == nil {
                modelContext.insert(item)
            }
            return item
        }

        let sourceConnectionId = item.sourceConnectionId
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.serverId == serverId &&
                    mediaItem.sourceConnectionId == sourceConnectionId
            }
        )
        if let storedItem = try modelContext.fetch(descriptor).first {
            storedItem.isWatched = isWatched
            storedItem.lastPlaybackPosition = position
            storedItem.lastPlayedAt = lastPlayedAt
            return storedItem
        }
        if item.modelContext == nil {
            modelContext.insert(item)
        }
        return item
    }

    private func playEpisode(_ episode: EpisodeInfo) {
        let episodeItem = MediaItem(
            title: item.title,
            fileURL: episode.streamURL,
            mediaType: .tvEpisode,
            duration: episode.duration
        )
        episodeItem.showTitle = item.title
        episodeItem.seasonNumber = episode.seasonNumber
        episodeItem.episodeNumber = episode.episodeNumber
        episodeItem.episodeTitle = episode.title
        episodeItem.posterURL = item.posterURL
        episodeItem.backdropURL = item.backdropURL
        episodeItem.serverId = episode.id
        episodeItem.seriesId = item.serverId ?? item.seriesId
        episodeItem.sourceConnectionId = item.sourceConnectionId
        episodeItem.lastPlaybackPosition = episode.lastPlaybackPosition
        episodeItem.isWatched = episode.isWatched
        appState.play(episodeItem)
    }

    private func handleDownloadButtonTap() {
        guard !isEnqueueingDownload else { return }
        if item.mediaType != .tvShow,
           let task = mediaDetailDisplayedTask(
               in: DownloadManager.shared.tasks,
               matching: isRelatedDownloadRequest
           ) {
            switch task.status {
            case .queued, .downloading:
                Task { await DownloadManager.shared.pause(task.id) }
                return
            case .paused:
                Task { await DownloadManager.shared.resume(task.id) }
                return
            case .failed:
                Task { await DownloadManager.shared.retry(task.id) }
                return
            case .completed:
                return
            }
        }
        beginDownload()
    }

#if DEBUG
    private func enqueueDebugHeroWalkIfNeeded() async {
        for _ in 0..<24 where DownloadHeroController.shared.sourceFrame.width <= 1 {
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        try? await Task.sleep(nanoseconds: 280_000_000)
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
                    try await DownloadManager.shared.enqueue(request)
                    DownloadHeroController.request(
                        title: DownloadActivityPresentation.title(for: request),
                        posterURL: request.postUrl ?? item.posterURL
                    )
#if DEBUG
                    VanmoLogger.library.info("[Debug][Downloads] enqueued source=detail mediaType=\(item.mediaType.rawValue, privacy: .public) connection=\(request.connectionType?.rawValue ?? "none", privacy: .public)")
#endif
                } catch {
#if DEBUG
                    let nsError = error as NSError
                    VanmoLogger.library.info("[Debug][Downloads] enqueue failed source=detail domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
#endif
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
                try await DownloadManager.shared.enqueue(requests)
                if let first = requests.first {
                    DownloadHeroController.request(
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
#if DEBUG
                let nsError = error as NSError
                VanmoLogger.library.info("[Debug][Downloads] enqueue failed source=detail-episodes domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
#endif
                downloadErrorMessage = error.localizedDescription
            }
        }
    }

    private func isRelatedDownloadRequest(_ request: DownloadRequest) -> Bool {
        guard request.sourceConnectionId == item.sourceConnectionId else { return false }
        if item.mediaType == .tvShow {
            let seriesID = item.serverId ?? item.seriesId
            return request.mediaType == .tvEpisode
                && (request.sourceMediaItemID == item.id
                    || (seriesID != nil && request.seriesServerID == seriesID)
                    || (request.seriesServerID == nil && request.showTitle == item.displayTitle))
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

    private func sourceConnectionType() throws -> ConnectionType? {
        guard let connectionId = item.sourceConnectionId else { return nil }
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == connectionId }
        )
        return try modelContext.fetch(descriptor).first?.type
    }

    private func makeCollectionItem(_ collection: ServerMediaItem) -> MediaItem {
        let collectionItem = ServerMediaItemMapper.makeMediaItem(from: collection)
        collectionItem.sourceConnectionId = item.sourceConnectionId
        return collectionItem
    }

    private func mediaServerConnectionSnapshot() throws -> MediaServerConnectionSnapshot? {
        try MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
    }
}

// MARK: - Observed Helper

private struct MediaDetailObservedObject<State: ObservableObject, Content: View>: View {
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

// MARK: - Detail Liquid Glass Helpers

private extension View {
    @ViewBuilder
    func detailLiquidGlass<S: InsettableShape>(
        in shape: S,
        colorScheme: ColorScheme,
        amberStroke: Bool = false,
        strokeWidth: CGFloat = 1
    ) -> some View {
        let tint: Color = colorScheme == .dark
            ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.22)
            : Color.white.opacity(0.62)
        let fallbackFill: Color = colorScheme == .dark
            ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.55)
            : Color.white.opacity(0.24)
        let stroke: Color = amberStroke
            ? CatDesign.strokeAmber
            : (colorScheme == .dark
                ? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.40)
                : CatDesign.strokeGlass)

        self.catLiquidGlass(
            in: shape,
            tint: tint,
            fallbackFill: fallbackFill,
            stroke: stroke,
            strokeWidth: strokeWidth,
            interactive: true
        )
    }

    func detailChipSurface(colorScheme: ColorScheme, height: CGFloat, horizontalPadding: CGFloat, cornerRadius: CGFloat) -> some View {
        let fill: Color = colorScheme == .dark
            ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.22)
            : CatDesign.surfacePill
        let stroke: Color = colorScheme == .dark
            ? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.40)
            : CatDesign.strokeGlass

        return self
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.8)
            )
    }
}

// MARK: - Seamless Parallax Hero Backdrop & Carousel

private struct MediaDetailHeroBackdrop: View {
    let backdropURLs: [URL]
    let fallbackPosterURL: URL?
    let scrollOffset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0
    @State private var loadedURLs: Set<URL> = []

    private let baseHeroHeight: CGFloat = 486
    private let minHeroHeight: CGFloat = 260
    private let scrimOverhang: CGFloat = 14
    private let carouselIntervalNanoseconds: UInt64 = 5_000_000_000

    private var effectiveURLs: [URL] {
        let raw = backdropURLs.isEmpty ? [fallbackPosterURL].compactMap { $0 } : backdropURLs
        return raw.map { highResolutionArtworkURL(from: $0) }
    }

    /// Pulling down stretches the pinned hero; scrolling up shrinks it until
    /// `minHeroHeight`, after which only the content panel keeps scrolling.
    private var heroHeight: CGFloat {
        reduceMotion ? baseHeroHeight : max(minHeroHeight, baseHeroHeight + scrollOffset)
    }

    var body: some View {
        let reducedMotionOffset = reduceMotion ? min(0, scrollOffset) : 0
        let scrollFade = 1.0 - min(max(-scrollOffset / 280, 0), 0.72)

        ZStack(alignment: .top) {
            CatDesign.mediaPlaceholder
                .frame(height: heroHeight)

            Group {
                if effectiveURLs.isEmpty {
                    Image("DefaultHeroBackdrop")
                        .resizable()
                        .scaledToFill()
                        .heroArtworkFrame(height: heroHeight)
                } else {
                    carouselImages(heroHeight: heroHeight)
                }
            }
            .opacity(scrollFade)

            LinearGradient(
                stops: [
                    .init(color: CatDesign.bgObsidian.opacity(0.40), location: 0.00),
                    .init(color: CatDesign.bgObsidian.opacity(0.08), location: 0.25),
                    .init(color: CatDesign.bgObsidian.opacity(0.60), location: 0.58),
                    .init(color: CatDesign.bgObsidian.opacity(0.90), location: 0.82),
                    .init(color: CatDesign.bgObsidian, location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: heroHeight + scrimOverhang)
        }
        .offset(y: reducedMotionOffset)
        .task(id: effectiveURLs) {
            activeIndex = 0
            prefetchHeroImages(effectiveURLs)
            guard effectiveURLs.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: carouselIntervalNanoseconds)
                guard !Task.isCancelled, effectiveURLs.count > 1 else { break }
                let nextIndex = (activeIndex + 1) % effectiveURLs.count
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                    activeIndex = nextIndex
                }
            }
        }
    }

    @ViewBuilder
    private func carouselImages(heroHeight: CGFloat) -> some View {
        let safeIndex = min(activeIndex, max(effectiveURLs.count - 1, 0))
        ZStack {
            ForEach(Array(effectiveURLs.enumerated()), id: \.offset) { index, url in
                let isCurrent = index == safeIndex
                let isAdjacent = effectiveURLs.count > 1 && index == (safeIndex + 1) % effectiveURLs.count
                if isCurrent || isAdjacent || loadedURLs.contains(url) {
                    KFImage(url)
                        .onSuccess { _ in
                            loadedURLs.insert(url)
                        }
                        .placeholder {
                            if index == 0, let fallbackPosterURL {
                                KFImage(fallbackPosterURL)
                                    .resizable()
                                    .scaledToFill()
                                    .blur(radius: 18)
                            } else {
                                CatDesign.mediaPlaceholder
                            }
                        }
                        // Not `.fade`: Kingfisher's fade animates the image out of a zero-size frame.
                        .loadTransition(.opacity, animation: .linear(duration: 0.35))
                        .resizable()
                        // Fill inside Kingfisher: the portrait placeholder is removed within the
                        // load animation and must not drive the backdrop's aspect ratio.
                        .contentConfigure { $0.scaledToFill() }
                        .heroArtworkFrame(height: heroHeight)
                        .opacity(isCurrent ? 1 : 0)
                }
            }
        }
    }

    private func prefetchHeroImages(_ urls: [URL]) {
        guard urls.count > 1 else { return }
        ImagePrefetcher(urls: urls).start()
    }

    private func highResolutionArtworkURL(from url: URL) -> URL {
        guard url.path.contains("/Items/"),
              (url.path.contains("/Images/Primary") || url.path.contains("/Images/Backdrop")),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { item in
            item.name.caseInsensitiveCompare("maxHeight") == .orderedSame ||
                item.name.caseInsensitiveCompare("maxWidth") == .orderedSame ||
                item.name.caseInsensitiveCompare("quality") == .orderedSame
        }
        if url.path.contains("/Images/Backdrop") {
            queryItems.append(URLQueryItem(name: "maxWidth", value: "1920"))
            queryItems.append(URLQueryItem(name: "quality", value: "90"))
        } else {
            queryItems.append(URLQueryItem(name: "maxHeight", value: "1800"))
            queryItems.append(URLQueryItem(name: "quality", value: "100"))
        }
        components.queryItems = queryItems
        return components.url ?? url
    }
}

private extension View {
    /// Pins fill-scaled artwork to the container width so it cannot widen the hero.
    func heroArtworkFrame(height: CGFloat) -> some View {
        containerRelativeFrame(.horizontal)
            .frame(height: height)
            .clipped()
    }
}

// MARK: - Title, Meta, Capability Badges & Primary Actions

private struct MediaDetailTitleAndMetaBlock: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let logoURL: URL?
    let metaText: String?
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MediaTitleLogoView(
                title: title,
                logoURL: logoURL,
                titleFont: .system(size: 30, weight: .bold),
                titleColor: CatDesign.textIvory,
                maxLogoHeight: 64,
                contentAlignment: .leading
            )

            if let metaText {
                Text(metaText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(CatDesign.accentAmber)
                    .lineLimit(1)
            }

            if !badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(CatDesign.textIvory)
                                .detailChipSurface(
                                    colorScheme: colorScheme,
                                    height: 24,
                                    horizontalPadding: 9,
                                    cornerRadius: 12
                                )
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediaDetailPrimaryActionRow: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.colorScheme) private var colorScheme

    let isTVShow: Bool
    let playButtonTitle: String
    let isFavorite: Bool
    let isUpdatingFavorite: Bool
    let isRelatedDownload: (DownloadRequest) -> Bool
    let isEnqueueingDownload: Bool
    let play: () -> Void
    let toggleFavorite: () -> Void
    let download: () -> Void

    private var displayedDownloadTask: DownloadTaskSnapshot? {
        mediaDetailDisplayedTask(in: downloadManager.tasks, matching: isRelatedDownload)
    }

    private var isDownloadDisabled: Bool {
        guard !isEnqueueingDownload else { return true }
        guard !isTVShow, let task = displayedDownloadTask else { return false }
        return task.status == .completed
    }

    var body: some View {
        HStack(spacing: 10) {
            playNowButton
            favoriteButton
            downloadButton
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private var playNowButton: some View {
        let fill: Color = colorScheme == .dark
            ? Color(red: 1.0, green: 181 / 255, blue: 71 / 255).opacity(0.70)
            : CatDesign.accentAmber.opacity(0.90)
        let stroke: Color = colorScheme == .dark
            ? Color.white.opacity(0.75)
            : Color.white.opacity(0.85)

        return Button(action: play) {
            HStack(spacing: 8) {
                Image("CatPlaySmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 15)
                    .foregroundStyle(Color.white.opacity(0.95))

                Text(playButtonTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(1)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Image("CatPerchingPlayTopRight")
                .resizable()
                .scaledToFit()
                .frame(width: 74, height: 68)
                .offset(x: 15, y: -22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var favoriteButton: some View {
        Button(action: toggleFavorite) {
            ZStack {
                if isUpdatingFavorite {
                    ProgressView()
                        .controlSize(.small)
                        .tint(CatDesign.accentAmber)
                } else if isFavorite {
                    Image("CatPawStamp")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                } else {
                    Image("CatPawStamp")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(CatDesign.textMuted)
                }
            }
            .frame(width: 48, height: 48)
            .detailLiquidGlass(in: Circle(), colorScheme: colorScheme, amberStroke: isFavorite)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFavorite)
        .accessibilityLabel(isFavorite ? L10n.tr("取消收藏") : L10n.tr("收藏"))
    }

    private var downloadButton: some View {
        Button(action: download) {
            MediaDetailDownloadCircleContent(
                taskID: displayedDownloadTask?.id,
                isEnqueueing: isEnqueueingDownload
            )
        }
        .buttonStyle(.plain)
        .disabled(isDownloadDisabled)
        .downloadHeroFrame("source")
        .accessibilityIdentifier("download.detail.button")
    }
}

private struct MediaDetailDownloadCircleContent: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.colorScheme) private var colorScheme

    let taskID: UUID?
    let isEnqueueing: Bool

    private var task: DownloadTaskSnapshot? {
        guard let taskID else { return nil }
        return downloadManager.tasks.first { $0.id == taskID }
    }

    private var isAmberHighlighted: Bool {
        task?.status == .downloading || task?.status == .queued || task?.status == .completed
    }

    var body: some View {
        ZStack {
            iconContent
        }
        .frame(width: 48, height: 48)
        .detailLiquidGlass(in: Circle(), colorScheme: colorScheme, amberStroke: isAmberHighlighted)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let task {
            switch task.status {
            case .queued:
                MediaDetailDownloadProgressRing(progress: nil, tint: CatDesign.accentAmber)
                    .frame(width: 20, height: 20)
            case .downloading:
                MediaDetailDownloadProgressRing(
                    progress: task.totalBytes > 0 ? task.progress : nil,
                    tint: CatDesign.accentAmber
                )
                .frame(width: 20, height: 20)
            case .paused:
                Image("CatPlaySmall")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(CatDesign.accentAmber)
            case .completed:
                Image("CatEarCheck")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
            case .failed:
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CatDesign.dangerRed)
            }
        } else if isEnqueueing {
            ProgressView()
                .controlSize(.small)
                .tint(CatDesign.accentAmber)
        } else if colorScheme == .light {
            Image("CatDownloadFeline")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(CatDesign.textIvory)
        } else {
            Image("CatDownloadFeline")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
    }

    private var accessibilityLabel: String {
        if isEnqueueing { return "正在加入下载队列" }
        guard let task else { return L10n.tr("下载") }
        switch task.status {
        case .queued: return "暂停等待中的下载"
        case .downloading: return "暂停下载"
        case .paused: return "继续下载"
        case .completed: return L10n.tr("已下载")
        case .failed: return L10n.tr("重新下载")
        }
    }

    private var accessibilityValue: String {
        guard let task, task.totalBytes > 0 else { return "" }
        return "\(Int(task.progress * 100))%"
    }
}

// MARK: - Synopsis Card

private struct MediaDetailSynopsisCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let overview: String?
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let fill: Color = colorScheme == .dark
            ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.45)
            : CatDesign.surfaceGlass
        let stroke: Color = colorScheme == .dark
            ? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.40)
            : CatDesign.strokeGlass

        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("简介"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)

                    Spacer()

                    Text(L10n.tr("更多 ›"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                }

                Text(overview ?? L10n.tr("暂无简介"))
                    .font(.system(size: 12))
                    .lineSpacing(3.5)
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(stroke, lineWidth: 0.9))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Episodes Section

private struct MediaDetailEpisodesSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let episodes: [EpisodeInfo]
    let seasonNumbers: [Int]
    @Binding var selectedSeason: Int?
    var isLoadingEpisodes: Bool = false
    var isLoadingMore: Bool = false
    var hasMoreEpisodes: Bool = false
    let onPlay: (EpisodeInfo) -> Void
    var onLoadMore: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if isLoadingEpisodes && episodes.isEmpty {
                ProgressView()
                    .tint(CatDesign.accentAmber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if episodes.isEmpty {
                Text(L10n.tr("暂无剧集"))
                    .font(.system(size: 13))
                    .foregroundStyle(CatDesign.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(episodes) { episode in
                            episodeHorizontalCard(episode)
                                .id(episode.id)
                        }

                        if hasMoreEpisodes || isLoadingMore {
                            Group {
                                if isLoadingMore {
                                    ProgressView()
                                        .tint(CatDesign.accentAmber)
                                        .frame(width: 48, height: 98)
                                } else {
                                    Color.clear
                                        .frame(width: 1, height: 98)
                                }
                            }
                            .onAppear { onLoadMore?() }
                        }
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                }
                .scrollClipDisabled()
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(L10n.tr("剧集"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            CatStretchingDivider()

            Spacer(minLength: 8)

            if !seasonNumbers.isEmpty {
                Menu {
                    ForEach(seasonNumbers, id: \.self) { season in
                        Button(LocalizedFormat.seasonLabel(season)) { selectedSeason = season }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalizedFormat.seasonLabel(selectedSeason ?? seasonNumbers.first ?? 1))
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(CatDesign.accentAmber)
                    .detailChipSurface(
                        colorScheme: colorScheme,
                        height: 28,
                        horizontalPadding: 11,
                        cornerRadius: 14
                    )
                }
                .disabled(seasonNumbers.count <= 1)
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    private func episodeHorizontalCard(_ episode: EpisodeInfo) -> some View {
        let isCompleted = episode.isWatched
        let isInProgress = !isCompleted && episode.lastPlaybackPosition > 0 && episode.duration > 0
        let progress = isInProgress ? min(max(episode.lastPlaybackPosition / episode.duration, 0.02), 1) : 0

        return Button {
            onPlay(episode)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                ZStack(alignment: .topLeading) {
                    if let backdropURL = episode.backdropURL {
                        KFImage(backdropURL)
                            .placeholder { thumbnailPlaceholder }
                            .loadTransition(.opacity, animation: .linear(duration: 0.2))
                            .resizable()
                            .contentConfigure { $0.scaledToFill() }
                            .id(backdropURL)
                    } else {
                        thumbnailPlaceholder
                    }

                    LinearGradient(
                        colors: [.clear, CatDesign.catSilhouette.opacity(0.92)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 58)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    Text(String(format: "E%02d", episode.episodeNumber))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CatDesign.Cinema.textIvory)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
                        .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeGlass, lineWidth: 0.75))
                        .padding(7)

                    if isCompleted {
                        CatSleepingPillBadge()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(7)
                    }

                    if isInProgress {
                        CatPawProgressBar(progress: progress, trackHeight: 3, showPawDot: true)
                            .padding(.horizontal, 9)
                            .padding(.bottom, 5)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(width: 174, height: 98)
                .clipShape(RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CatDesign.radiusSquircleMd, style: .continuous)
                        .strokeBorder(isInProgress ? CatDesign.strokeAmber : CatDesign.strokeGlass, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title.isEmpty ? LocalizedFormat.episodeLabel(episode.episodeNumber) : episode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                        .lineLimit(1)

                    episodeSubtitle(episode, isCompleted: isCompleted, isInProgress: isInProgress)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .frame(width: 174, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func episodeSubtitle(_ episode: EpisodeInfo, isCompleted: Bool, isInProgress: Bool) -> some View {
        if isCompleted {
            let durationLabel = episode.duration > 0 ? episode.duration.localizedShortDuration : LocalizedFormat.unknownDuration()
            Text("\(durationLabel) · \(L10n.tr("已看"))")
                .foregroundStyle(CatDesign.accentAmber)
        } else if isInProgress {
            let posText = formatPlaybackTimestamp(episode.lastPlaybackPosition)
            let totalText = episode.duration > 0 ? episode.duration.localizedShortDuration : LocalizedFormat.unknownDuration()
            Text("\(posText) · \(totalText)")
                .foregroundStyle(CatDesign.textMuted)
        } else {
            Text(episode.duration > 0 ? episode.duration.localizedShortDuration : LocalizedFormat.unknownDuration())
                .foregroundStyle(CatDesign.textMuted)
        }
    }

    private func formatPlaybackTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            CatDesign.mediaPlaceholder
            Image(systemName: "play.rectangle")
                .font(.title3)
                .foregroundStyle(CatDesign.textMuted.opacity(0.45))
        }
    }
}

// MARK: - Cast & Crew Section

private struct MediaDetailCastSection: View {
    let members: [CastMemberDisplay]

    var body: some View {
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("演职员"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .padding(.horizontal, CatDesign.horizontalMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(members) { member in
                            MediaDetailCastAvatar(member: member)
                        }
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                }
            }
        }
    }
}

private struct MediaDetailCastAvatar: View {
    let member: CastMemberDisplay

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(CatDesign.surfacePill)

                if let profileURL = member.profileURL {
                    KFImage(profileURL)
                        .placeholder {
                            Text(initial(for: member.name))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(CatDesign.textMuted)
                        }
                        .loadTransition(.opacity, animation: .linear(duration: 0.2))
                        .resizable()
                        .contentConfigure { $0.scaledToFill() }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Text(initial(for: member.name))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(CatDesign.textMuted)
                }
            }
            .frame(width: 60, height: 60)
            .overlay(Circle().strokeBorder(CatDesign.strokeGlass, lineWidth: 1))

            VStack(spacing: 1) {
                Text(member.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let role = member.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .frame(width: 72)
        }
    }

    private func initial(for name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

// MARK: - Collections Section

private struct MediaDetailCollectionsSection: View {
    let collections: [ServerMediaItem]
    let makeItem: (ServerMediaItem) -> MediaItem

    var body: some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("合集"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .padding(.horizontal, CatDesign.horizontalMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(collections, id: \.serverId) { collection in
                            NavigationLink {
                                EmbyFolderBrowseView(container: makeItem(collection))
                            } label: {
                                MediaDetailCollectionCard(collection: collection)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                }
            }
        }
    }
}

private struct MediaDetailCollectionCard: View {
    let collection: ServerMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CatDesign.mediaPlaceholder)

                if let posterURL = collection.posterURL {
                    KFImage(posterURL)
                        .loadTransition(.opacity, animation: .linear(duration: 0.2))
                        .resizable()
                        .contentConfigure { $0.scaledToFill() }
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                }
            }
            .frame(width: 124, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 1)
            )

            Text(collection.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
                .lineLimit(2)
                .frame(width: 124, alignment: .leading)
        }
    }
}

// MARK: - Technical Media Specifications Footer

private struct MediaDetailSpecsFooter: View {
    @Environment(\.colorScheme) private var colorScheme
    let chips: [String]

    var body: some View {
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("媒体规格"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CatDesign.textDim)
                    .padding(.horizontal, CatDesign.horizontalMargin)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                            Text(chip)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(CatDesign.textMuted)
                                .detailChipSurface(
                                    colorScheme: colorScheme,
                                    height: 26,
                                    horizontalPadding: 10,
                                    cornerRadius: 13
                                )
                        }
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                }
            }
        }
    }
}

// MARK: - Shared Helpers & Pickers

private func mediaDetailDisplayedTask(
    in tasks: [DownloadTaskSnapshot],
    matching isRelated: (DownloadRequest) -> Bool
) -> DownloadTaskSnapshot? {
    let related = tasks.filter { isRelated($0.request) }
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
    if let failed = related
        .filter({ $0.status == .failed })
        .max(by: { $0.updatedAt < $1.updatedAt }) {
        return failed
    }
    guard !related.isEmpty, related.allSatisfy({ $0.status == .completed }) else {
        return nil
    }
    return related.max(by: { $0.updatedAt < $1.updatedAt })
}

private struct MediaDetailDownloadProgressRing: View {
    let progress: Double?
    let tint: Color
    @State private var rotation = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2.4)
            if let progress {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0.02), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0.05, to: 0.32)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(rotation - 90))
            }
        }
        .onAppear(perform: startAnimatingIfNeeded)
        .onChange(of: progress == nil) { _, _ in
            startAnimatingIfNeeded()
        }
    }

    private func startAnimatingIfNeeded() {
        guard progress == nil else {
            rotation = 0
            return
        }
        rotation = 0
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

private struct EpisodeDownloadPicker: View {
    @Environment(\.dismiss) private var dismiss
    let episodes: [EpisodeInfo]
    let seasonNumbers: [Int]
    let selectedSeason: Int?
    @Binding var selectedEpisodes: [String: EpisodeInfo]
    let isLoading: Bool
    let onSelectSeason: (Int) -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(L10n.tr("季"), selection: Binding(
                        get: { selectedSeason ?? seasonNumbers.first ?? 1 },
                        set: onSelectSeason
                    )) {
                        ForEach(seasonNumbers, id: \.self) { season in
                            Text(LocalizedFormat.seasonLabel(season)).tag(season)
                        }
                    }
                    Button(allCurrentSeasonSelected ? L10n.tr("取消全选本季") : L10n.tr("全选本季")) {
                        toggleCurrentSeason()
                    }
                    .foregroundStyle(CatDesign.accentAmber)
                    .accessibilityIdentifier("download.picker.selectAll")
                }

                Section(L10n.tr("选择剧集")) {
                    ForEach(episodes) { episode in
                        Button {
                            toggle(episode)
                        } label: {
                            HStack {
                                Image(systemName: selectedEpisodes[episode.id] == nil ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(selectedEpisodes[episode.id] == nil ? CatDesign.textMuted : CatDesign.accentAmber)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(LocalizedFormat.episodeLabel(episode.episodeNumber)) · \(episode.title)")
                                        .foregroundStyle(CatDesign.textIvory)
                                    if episode.duration > 0 {
                                        Text(episode.duration.shortDuration)
                                            .font(.caption)
                                            .foregroundStyle(CatDesign.textMuted)
                                    }
                                }
                            }
                        }
                    }
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView().tint(CatDesign.accentAmber)
                            Spacer()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(CatDesign.bgObsidian)
            .navigationTitle(L10n.tr("选择下载剧集"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("取消")) { dismiss() }
                        .foregroundStyle(CatDesign.textMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下载 \(selectedEpisodes.count) 集", action: onConfirm)
                        .foregroundStyle(CatDesign.accentAmber)
                        .disabled(selectedEpisodes.isEmpty || isLoading)
                        .accessibilityIdentifier("download.picker.confirm")
                }
            }
        }
    }

    private var allCurrentSeasonSelected: Bool {
        !episodes.isEmpty && episodes.allSatisfy { selectedEpisodes[$0.id] != nil }
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

private struct DetailNavigationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MediaDetailRefreshErrorPresenter: ViewModifier {
    @ObservedObject var state: MediaDetailActionState

    private var refreshErrorBinding: Binding<Bool> {
        Binding {
            state.refreshErrorMessage != nil
        } set: { isPresented in
            if !isPresented { state.refreshErrorMessage = nil }
        }
    }

    func body(content: Content) -> some View {
        content
            .alert(L10n.tr("刷新失败"), isPresented: refreshErrorBinding) {
                Button(L10n.tr("确定")) {}
            } message: {
                Text(state.refreshErrorMessage ?? "")
            }
    }
}

// MARK: - Detail Content & Progressive Store

struct MediaDetailContent {
    var posterURL: URL?
    var backdropURLs: [URL]
    var year: Int?
    var rating: Double?
    var contentRating: String?
    var logoURL: URL?
    var overview: String?
    var genres: [String]
    var director: String?
    var castMembers: [CastMemberDisplay]
    var seasons: [SeasonInfo]
    var collections: [ServerMediaItem]
}

@MainActor
final class MediaDetailSummaryState: ObservableObject {
    @Published var content: MediaDetailContent?
    @Published var isLoading = false
}

@MainActor
final class MediaDetailCastState: ObservableObject {
    @Published var members: [CastMemberDisplay] = []
}

@MainActor
final class MediaDetailCollectionState: ObservableObject {
    @Published var items: [ServerMediaItem] = []
}

@MainActor
final class MediaDetailEpisodeState: ObservableObject {
    @Published var seasons: [SeasonInfo] = []
    @Published var selectedSeason: Int?
    @Published var episodes: [EpisodeInfo] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = false
}

@MainActor
final class MediaDetailTechnicalState: ObservableObject {
    @Published var videoWidth: Int?
    @Published var videoHeight: Int?
    @Published var videoCodec: String?
    @Published var videoBitDepth: Int?
    @Published var bitRate: Int?
    @Published var dynamicRange: String?
    @Published var audioTracks: [AudioTrackInfo] = []
    @Published var episodeFileNameHint: String?
}

@MainActor
final class MediaDetailActionState: ObservableObject {
    @Published var isRefreshingMetadata = false
    @Published var refreshErrorMessage: String?
}

@MainActor
final class MediaDetailStore: ObservableObject {
    let summaryState = MediaDetailSummaryState()
    let castState = MediaDetailCastState()
    let collectionState = MediaDetailCollectionState()
    let episodeState = MediaDetailEpisodeState()
    let technicalState = MediaDetailTechnicalState()
    let actionState = MediaDetailActionState()

    var content: MediaDetailContent? {
        get {
            guard var value = summaryState.content else { return nil }
            value.castMembers = castState.members
            value.seasons = episodeState.seasons
            value.collections = collectionState.items
            return value
        }
        set {
            summaryState.content = newValue.map {
                MediaDetailContent(
                    posterURL: $0.posterURL,
                    backdropURLs: $0.backdropURLs,
                    year: $0.year,
                    rating: $0.rating,
                    contentRating: $0.contentRating,
                    logoURL: $0.logoURL,
                    overview: $0.overview,
                    genres: $0.genres,
                    director: $0.director,
                    castMembers: [],
                    seasons: [],
                    collections: []
                )
            }
            castState.members = newValue?.castMembers ?? []
            episodeState.seasons = newValue?.seasons ?? []
            collectionState.items = newValue?.collections ?? []
        }
    }

    var isLoading: Bool {
        get { summaryState.isLoading }
        set { summaryState.isLoading = newValue }
    }

    var selectedSeason: Int? {
        get { episodeState.selectedSeason }
        set { episodeState.selectedSeason = newValue }
    }

    var seasonEpisodes: [EpisodeInfo] {
        get { episodeState.episodes }
        set { episodeState.episodes = newValue }
    }

    var isLoadingEpisodes: Bool {
        get { episodeState.isLoading }
        set { episodeState.isLoading = newValue }
    }

    var isLoadingMoreEpisodes: Bool {
        get { episodeState.isLoadingMore }
        set { episodeState.isLoadingMore = newValue }
    }

    var hasMoreEpisodes: Bool {
        get { episodeState.hasMore }
        set { episodeState.hasMore = newValue }
    }

    var isRefreshingMetadata: Bool {
        get { actionState.isRefreshingMetadata }
        set { actionState.isRefreshingMetadata = newValue }
    }

    var videoWidth: Int? {
        get { technicalState.videoWidth }
        set { technicalState.videoWidth = newValue }
    }

    var videoHeight: Int? {
        get { technicalState.videoHeight }
        set { technicalState.videoHeight = newValue }
    }

    var dynamicRange: String? {
        get { technicalState.dynamicRange }
        set { technicalState.dynamicRange = newValue }
    }

    var refreshErrorMessage: String? {
        get { actionState.refreshErrorMessage }
        set { actionState.refreshErrorMessage = newValue }
    }

    private var loadedKey: String?
    private var loadGeneration = 0
    private var episodeStartIndex = 0
    private var episodeLoadGeneration = 0
    private var metadataCacheRecord: MetadataCacheRecord?
    private var metadataRootDirectory: URL?
    private var initialEpisodeTask: Task<Void, Never>?
    private let metadataLoader = MediaDetailProgressiveLoader()

    private let episodePageSize = 20

    var nextEpisodeToPlay: EpisodeInfo? {
        let sorted = seasonEpisodes.sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
        if let inProgress = sorted.first(where: { !$0.isWatched && $0.lastPlaybackPosition > 0 }) {
            return inProgress
        }
        if let firstUnwatched = sorted.first(where: { !$0.isWatched }) {
            return firstUnwatched
        }
        return sorted.first
    }

    func supportsMetadataRefresh(for item: MediaItem, in modelContext: ModelContext) -> Bool {
        if (try? connectionSnapshot(for: item, in: modelContext)) != nil {
            return true
        }
        return MetadataRefreshCoordinator.supportsRefresh(for: item)
    }

    func load(item: MediaItem, modelContext: ModelContext, autoDownloadMetadata: Bool) async {
        let key = detailKey(for: item)
        guard loadedKey != key else { return }
        loadedKey = key
        loadGeneration += 1
        let generation = loadGeneration
        defer {
            if generation == loadGeneration {
                isLoading = false
                if Task.isCancelled {
                    loadedKey = nil
                }
            }
        }

        isLoading = true
        resetEpisodePagingState()
        content = baseContent(for: item)
        #if DEBUG
        VanmoLogger.library.info("[Debug][Detail] load type=\(item.mediaType.rawValue, privacy: .public) title=\(item.title, privacy: .private)")
        #endif
        technicalState.videoWidth = item.videoWidth
        technicalState.videoHeight = item.videoHeight
        technicalState.videoCodec = item.videoCodec
        technicalState.videoBitDepth = nil
        technicalState.bitRate = nil
        technicalState.dynamicRange = item.dynamicRange
        technicalState.audioTracks = item.audioTracks
        technicalState.episodeFileNameHint = nil

        await performAggregate(
            item: item,
            modelContext: modelContext,
            autoDownloadMetadata: autoDownloadMetadata,
            force: false,
            generation: generation
        )
    }

    func refreshMetadata(for item: MediaItem, modelContext: ModelContext, force: Bool) async {
        guard !isRefreshingMetadata else { return }
        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }
        loadGeneration += 1
        let generation = loadGeneration
        initialEpisodeTask?.cancel()
        episodeLoadGeneration += 1

        await performAggregate(
            item: item,
            modelContext: modelContext,
            autoDownloadMetadata: true,
            force: force,
            generation: generation
        )
    }

    func selectSeason(_ season: Int, item: MediaItem, modelContext: ModelContext) async {
        guard selectedSeason != season else { return }
        selectedSeason = season
        await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
    }

    /// 退出播放器或刚打开详情时，用 SwiftData 中的已看和进度记录更新主条目与剧集状态。
    func syncLocalPlaybackStates(for item: MediaItem, in modelContext: ModelContext) {
        let sourceConnectionId = item.sourceConnectionId
        if let serverId = item.serverId {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate<MediaItem> { mediaItem in
                    mediaItem.serverId == serverId &&
                        mediaItem.sourceConnectionId == sourceConnectionId
                }
            )
            if let stored = try? modelContext.fetch(descriptor).first {
                item.isWatched = stored.isWatched
                item.lastPlaybackPosition = stored.lastPlaybackPosition
                item.lastPlayedAt = stored.lastPlayedAt
                item.isFavorite = stored.isFavorite
            }
        }

        guard item.mediaType == .tvShow, !seasonEpisodes.isEmpty else { return }
        let localEpisodes = fetchLocalEpisodes(for: item, in: modelContext)
        guard !localEpisodes.isEmpty else { return }
        seasonEpisodes = mergeLocalProgress(into: seasonEpisodes, localItems: localEpisodes)
    }

    func applySeriesWatchedState(_ isWatched: Bool, for item: MediaItem, in modelContext: ModelContext) {
        let localEpisodes = fetchLocalEpisodes(for: item, in: modelContext)
        let episodeIDs = Set(seasonEpisodes.map(\.id))
        let now = Date()
        for local in localEpisodes {
            let matchesLoaded = local.serverId.map { episodeIDs.contains($0) } ?? false
            let matchesSeries = (item.serverId != nil && local.seriesId == item.serverId) || matchesLoaded
            guard matchesSeries else { continue }
            local.isWatched = isWatched
            if isWatched {
                if local.duration > 0 { local.lastPlaybackPosition = local.duration }
                local.lastPlayedAt = now
            } else {
                local.lastPlaybackPosition = 0
            }
        }
        try? modelContext.save()

        guard !seasonEpisodes.isEmpty else { return }
        seasonEpisodes = seasonEpisodes.map { episode in
            EpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropURL: episode.backdropURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath,
                videoWidth: episode.videoWidth,
                videoHeight: episode.videoHeight,
                videoCodec: episode.videoCodec,
                videoBitDepth: episode.videoBitDepth,
                bitRate: episode.bitRate,
                dynamicRange: episode.dynamicRange,
                audioTracks: episode.audioTracks,
                lastPlaybackPosition: isWatched ? (episode.duration > 0 ? episode.duration : episode.lastPlaybackPosition) : 0,
                isWatched: isWatched
            )
        }
    }

#if DEBUG
    func installDebugHeroWalkEpisodesIfNeeded(for item: MediaItem) {
        guard DownloadHeroWalkFixtures.requestedKind == .series, item.mediaType == .tvShow else { return }
        guard let episodes = try? DownloadHeroWalkFixtures.seriesEpisodes() else { return }
        if content == nil {
            content = MediaDetailContent(
                posterURL: item.posterURL,
                backdropURLs: item.backdropURL.map { [$0] } ?? [],
                year: item.year,
                rating: nil,
                contentRating: nil,
                logoURL: nil,
                overview: item.overview,
                genres: [],
                director: nil,
                castMembers: [],
                seasons: [SeasonInfo(seasonNumber: 1)],
                collections: []
            )
        } else {
            content?.seasons = [SeasonInfo(seasonNumber: 1)]
        }
        selectedSeason = 1
        seasonEpisodes = episodes
        hasMoreEpisodes = false
        isLoadingEpisodes = false
        isLoadingMoreEpisodes = false
    }
#endif

    func loadMoreEpisodes(item: MediaItem, modelContext: ModelContext) async {
        guard hasMoreEpisodes, !isLoadingMoreEpisodes, !isLoadingEpisodes else { return }
        await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: false)
    }

    private func performAggregate(
        item: MediaItem,
        modelContext: ModelContext,
        autoDownloadMetadata: Bool,
        force: Bool,
        generation: Int
    ) async {
        let root = (try? await MetadataCache.shared.rootDirectoryURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        metadataRootDirectory = root
        let connection = try? connectionSnapshot(for: item, in: modelContext)
        let canRefresh = supportsMetadataRefresh(for: item, in: modelContext)
        let updates = metadataLoader.updates(
            for: item,
            connection: connection,
            autoDownloadMetadata: autoDownloadMetadata && canRefresh,
            force: force
        )

        for await event in updates {
            guard generation == loadGeneration, !Task.isCancelled, !item.isDeleted else { return }
            switch event {
            case .cached(let record), .metadata(let record):
                applyMetadataRecord(record, root: root, item: item)
                if episodeState.seasons.isEmpty, item.mediaType == .tvShow {
                    applySeasons(seasonInfos(from: record), item: item, modelContext: modelContext)
                }
            case .seasons(let seasons):
                applySeasons(seasons, item: item, modelContext: modelContext)
            case .collections(let collections):
                collectionState.items = collections
            case .failed(let component, let message):
                if component == .metadata {
                    refreshErrorMessage = message
                }
            case .finished:
                isLoading = false
            }
        }

        guard generation == loadGeneration, !Task.isCancelled else { return }
        isLoading = false
    }

    private func baseContent(for item: MediaItem) -> MediaDetailContent {
        let members = item.cast.enumerated().map { index, name in
            CastMemberDisplay(id: "\(index)-\(name)", name: name, role: nil, profileURL: nil)
        }
        return MediaDetailContent(
            posterURL: item.posterURL,
            backdropURLs: item.backdropURL.map { [$0] } ?? [],
            year: item.year,
            rating: item.rating,
            contentRating: item.contentRating,
            logoURL: item.logoURL,
            overview: item.overview,
            genres: item.genres,
            director: item.director,
            castMembers: members,
            seasons: [],
            collections: []
        )
    }

    private func applyMetadataRecord(
        _ record: MetadataCacheRecord,
        root: URL,
        item: MediaItem
    ) {
        metadataCacheRecord = record
        var snapshot = summaryState.content ?? baseContent(for: item)
        snapshot.posterURL = record.posterRemoteURL ?? snapshot.posterURL
        let resolvedBackdrops = record.resolvedBackdropURLs(rootDirectory: root)
        if !resolvedBackdrops.isEmpty {
            snapshot.backdropURLs = resolvedBackdrops
        }
        snapshot.year = record.year ?? snapshot.year
        snapshot.rating = record.rating ?? snapshot.rating
        snapshot.contentRating = MediaCapabilityTags.normalizedContentRating(record.contentRating)
            ?? snapshot.contentRating
        snapshot.logoURL = record.resolvedLogoURL(rootDirectory: root) ?? snapshot.logoURL
        snapshot.overview = record.overview?.isEmpty == false ? record.overview : snapshot.overview
        snapshot.genres = record.genres.isEmpty ? snapshot.genres : record.genres
        snapshot.director = record.director?.isEmpty == false ? record.director : snapshot.director
        summaryState.content = snapshot

        let members = record.makeCastDisplays(rootDirectory: root)
        if !members.isEmpty {
            castState.members = members
        }

        technicalState.videoWidth = record.videoWidth ?? technicalState.videoWidth
        technicalState.videoHeight = record.videoHeight ?? technicalState.videoHeight
        technicalState.videoCodec = record.videoCodec ?? technicalState.videoCodec
        technicalState.videoBitDepth = record.videoBitDepth ?? technicalState.videoBitDepth
        technicalState.bitRate = record.bitRate ?? technicalState.bitRate
        technicalState.dynamicRange = record.dynamicRange ?? technicalState.dynamicRange
        if !record.audioTracks.isEmpty {
            technicalState.audioTracks = record.audioTracks
        }
    }

    private func applySeasons(
        _ seasons: [SeasonInfo],
        item: MediaItem,
        modelContext: ModelContext
    ) {
        guard !seasons.isEmpty else { return }
        episodeState.seasons = seasons
        let previousSeason = selectedSeason
        if let previousSeason, seasons.contains(where: { $0.seasonNumber == previousSeason }) {
            selectedSeason = previousSeason
        } else {
            selectedSeason = seasons.first?.seasonNumber
        }

        initialEpisodeTask?.cancel()
        initialEpisodeTask = Task { [weak self] in
            guard let self else { return }
            await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
        }
    }

    private func applyTechnicalFields(from episodes: [EpisodeInfo]) {
        let names = episodes.compactMap(\.originalFileName).joined(separator: " ")
        technicalState.episodeFileNameHint = names.isEmpty ? nil : names

        let match = episodes.first {
            ($0.videoWidth ?? 0) > 0 || ($0.videoHeight ?? 0) > 0 || $0.videoCodec != nil
        }
        #if DEBUG
        VanmoLogger.library.info("[Debug][Detail] tvTags episodes=\(episodes.count, privacy: .public) width=\(match?.videoWidth ?? 0, privacy: .public) height=\(match?.videoHeight ?? 0, privacy: .public) codec=\(match?.videoCodec ?? "nil", privacy: .public) files=\(names.isEmpty ? "none" : "yes", privacy: .public)")
        #endif
        guard let match else { return }

        technicalState.videoWidth = technicalState.videoWidth ?? match.videoWidth
        technicalState.videoHeight = technicalState.videoHeight ?? match.videoHeight
        technicalState.videoCodec = technicalState.videoCodec ?? match.videoCodec
        technicalState.videoBitDepth = technicalState.videoBitDepth ?? match.videoBitDepth
        technicalState.bitRate = technicalState.bitRate ?? match.bitRate
        technicalState.dynamicRange = technicalState.dynamicRange ?? match.dynamicRange
        if technicalState.audioTracks.isEmpty && !match.audioTracks.isEmpty {
            technicalState.audioTracks = match.audioTracks
        }
    }

    private func resetEpisodePagingState() {
        initialEpisodeTask?.cancel()
        episodeLoadGeneration += 1
        selectedSeason = nil
        seasonEpisodes = []
        isLoadingEpisodes = false
        isLoadingMoreEpisodes = false
        hasMoreEpisodes = false
        episodeStartIndex = 0
        metadataCacheRecord = nil
        metadataRootDirectory = nil
    }

    private func loadSeasonEpisodes(item: MediaItem, modelContext: ModelContext, reset: Bool) async {
        guard !Task.isCancelled,
              loadedKey == detailKey(for: item),
              item.mediaType == .tvShow else {
            return
        }
        guard let season = selectedSeason else { return }

        if reset {
            episodeLoadGeneration += 1
            seasonEpisodes = []
            episodeStartIndex = 0
            hasMoreEpisodes = false
            isLoadingEpisodes = true
            isLoadingMoreEpisodes = false
        } else {
            guard hasMoreEpisodes, !isLoadingMoreEpisodes, !isLoadingEpisodes else { return }
            isLoadingMoreEpisodes = true
        }

        let generation = episodeLoadGeneration
        let startIndex = reset ? 0 : episodeStartIndex

        defer {
            if generation == episodeLoadGeneration {
                isLoadingEpisodes = false
                isLoadingMoreEpisodes = false
            }
        }

        do {
            let page = try await fetchEpisodesPage(
                item: item,
                modelContext: modelContext,
                season: season,
                startIndex: startIndex,
                pageSize: episodePageSize
            )

            guard generation == episodeLoadGeneration, !item.isDeleted else { return }

            let mergedBackdrops = mergeEpisodeBackdrops(page.items, for: item)
            let localEpisodes = fetchLocalEpisodes(for: item, in: modelContext)
            let merged = mergeLocalProgress(into: mergedBackdrops, localItems: localEpisodes)

            if reset {
                seasonEpisodes = merged
            } else {
                let existingIDs = Set(seasonEpisodes.map(\.id))
                seasonEpisodes.append(contentsOf: merged.filter { !existingIDs.contains($0.id) })
            }

            episodeStartIndex = startIndex + page.items.count
            hasMoreEpisodes = page.items.count >= episodePageSize
                && episodeStartIndex < page.totalRecordCount
            let cacheKey = MetadataCacheKey.from(item)
            Task(priority: .utility) {
                try? await MetadataCache.shared.cacheEpisodes(page.items, for: cacheKey)
            }
        } catch {
            VanmoLogger.library.error("[MediaServer] Failed to load season episodes: \(error.localizedDescription)")
            guard generation == episodeLoadGeneration else { return }

            if reset, let fallback = cachedEpisodes(for: season, item: item), !fallback.isEmpty {
                let localEpisodes = fetchLocalEpisodes(for: item, in: modelContext)
                seasonEpisodes = mergeLocalProgress(into: fallback, localItems: localEpisodes)
                episodeStartIndex = fallback.count
                hasMoreEpisodes = false
            } else if reset {
                seasonEpisodes = []
                hasMoreEpisodes = false
            }
        }

        applyTechnicalFields(from: seasonEpisodes)
    }

    private func fetchLocalEpisodes(for item: MediaItem, in modelContext: ModelContext) -> [MediaItem] {
        let sourceConnectionId = item.sourceConnectionId
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.sourceConnectionId == sourceConnectionId
            }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.mediaType == .tvEpisode }
    }

    private func mergeLocalProgress(into episodes: [EpisodeInfo], localItems: [MediaItem]) -> [EpisodeInfo] {
        guard !localItems.isEmpty else { return episodes }
        var byServerId: [String: MediaItem] = [:]
        var byURL: [String: MediaItem] = [:]
        for local in localItems {
            if let serverId = local.serverId {
                byServerId[serverId] = local
            }
            byURL[local.fileURL.standardizedFileURL.absoluteString] = local
        }

        return episodes.map { episode in
            let local = byServerId[episode.id] ?? byURL[episode.streamURL.standardizedFileURL.absoluteString]
            guard let local else { return episode }

            let mergedWatched = episode.isWatched || local.isWatched
            let mergedPosition = max(episode.lastPlaybackPosition, local.lastPlaybackPosition)
            guard mergedWatched != episode.isWatched || mergedPosition != episode.lastPlaybackPosition else {
                return episode
            }
            return EpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropURL: episode.backdropURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath,
                videoWidth: episode.videoWidth,
                videoHeight: episode.videoHeight,
                videoCodec: episode.videoCodec,
                videoBitDepth: episode.videoBitDepth,
                bitRate: episode.bitRate,
                dynamicRange: episode.dynamicRange,
                audioTracks: episode.audioTracks,
                lastPlaybackPosition: mergedPosition,
                isWatched: mergedWatched
            )
        }
    }

    private func fetchEpisodesPage(
        item: MediaItem,
        modelContext: ModelContext,
        season: Int,
        startIndex: Int,
        pageSize: Int
    ) async throws -> EpisodePage {
        guard let seriesServerId = item.serverId else {
            throw NetworkError.notConnected
        }

        let snapshot = try? connectionSnapshot(for: item, in: modelContext)

        switch item.fileURL.host {
        case "plex-series":
            if let seasonKey = content?.seasons.first(where: { $0.seasonNumber == season })?.serverId {
                if let snapshot {
                    return try await PlexEpisodeFetcher.fetchEpisodesPage(
                        seasonRatingKey: seasonKey,
                        seasonNumber: season,
                        startIndex: startIndex,
                        pageSize: pageSize,
                        connection: snapshot
                    )
                }
                return try await PlexEpisodeFetcher.fetchEpisodesPage(
                    seasonRatingKey: seasonKey,
                    seasonNumber: season,
                    startIndex: startIndex,
                    pageSize: pageSize
                )
            }

            let all: [EpisodeInfo]
            if let snapshot {
                all = try await PlexEpisodeFetcher.fetchEpisodes(
                    seriesRatingKey: seriesServerId,
                    connection: snapshot
                )
            } else {
                all = try await PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey: seriesServerId)
            }
            let filtered = all
                .filter { $0.seasonNumber == season }
                .sorted { $0.episodeNumber < $1.episodeNumber }
            let slice = Array(filtered.dropFirst(startIndex).prefix(pageSize))
            return EpisodePage(items: slice, totalRecordCount: filtered.count)
        default:
            if let snapshot {
                return try await EmbyEpisodeFetcher.fetchEpisodesPage(
                    seriesId: seriesServerId,
                    season: season,
                    startIndex: startIndex,
                    pageSize: pageSize,
                    connection: snapshot
                )
            }
            return try await EmbyEpisodeFetcher.fetchEpisodesPage(
                seriesId: seriesServerId,
                season: season,
                startIndex: startIndex,
                pageSize: pageSize
            )
        }
    }

    private func seasonInfos(from record: MetadataCacheRecord) -> [SeasonInfo] {
        Array(Set(record.episodes.map(\.seasonNumber)))
            .sorted()
            .map { SeasonInfo(seasonNumber: $0) }
    }

    private func cachedEpisodes(for season: Int, item: MediaItem) -> [EpisodeInfo]? {
        guard let record = metadataCacheRecord,
              let root = metadataRootDirectory,
              item.mediaType == .tvShow,
              !record.episodes.isEmpty else {
            return nil
        }
        return record.episodes
            .filter { $0.seasonNumber == season }
            .map { $0.makeEpisodeInfo(rootDirectory: root) }
            .sorted { $0.episodeNumber < $1.episodeNumber }
    }

    private func mergeEpisodeBackdrops(_ loaded: [EpisodeInfo], for item: MediaItem) -> [EpisodeInfo] {
        guard let record = metadataCacheRecord,
              let root = metadataRootDirectory,
              item.mediaType == .tvShow,
              !record.episodes.isEmpty else {
            return loaded
        }

        let cachedByID = Dictionary(record.episodes.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        return loaded.map { episode in
            guard episode.backdropURL == nil, let cached = cachedByID[episode.id] else { return episode }
            let cachedEpisode = cached.makeEpisodeInfo(rootDirectory: root)
            guard let backdropURL = cachedEpisode.backdropURL else { return episode }
            return EpisodeInfo(
                id: episode.id,
                title: episode.title,
                seasonNumber: episode.seasonNumber,
                episodeNumber: episode.episodeNumber,
                duration: episode.duration,
                overview: episode.overview,
                streamURL: episode.streamURL,
                backdropURL: backdropURL,
                fileSize: episode.fileSize,
                originalFileName: episode.originalFileName,
                container: episode.container,
                remotePath: episode.remotePath,
                videoWidth: episode.videoWidth,
                videoHeight: episode.videoHeight,
                videoCodec: episode.videoCodec,
                videoBitDepth: episode.videoBitDepth,
                bitRate: episode.bitRate,
                dynamicRange: episode.dynamicRange,
                audioTracks: episode.audioTracks,
                lastPlaybackPosition: episode.lastPlaybackPosition,
                isWatched: episode.isWatched
            )
        }
    }

    private func detailKey(for item: MediaItem) -> String {
        MetadataCacheKey.from(item).cacheKey
    }

    private func connectionSnapshot(for item: MediaItem, in modelContext: ModelContext) throws -> MediaServerConnectionSnapshot? {
        try MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
    }
}

// MARK: - Previews

#Preview("Movie Detail — Dark") {
    let movie = MediaItem(
        title: "DUNE: PROPHECY",
        fileURL: URL(fileURLWithPath: "/dune.mkv"),
        mediaType: .movie,
        fileSize: 68_000_000_000,
        duration: 8280
    )
    movie.year = 2024
    movie.genres = ["Sci-Fi"]
    movie.rating = 8.6
    movie.videoWidth = 3840
    movie.videoHeight = 2160
    movie.videoCodec = "HEVC"
    movie.dynamicRange = DynamicRange.dolbyVision.rawValue
    movie.audioTracks = [AudioTrackInfo(id: 0, codec: "truehd", channels: 8)]
    movie.overview = "Ten thousand years before the ascension of Paul Atreides, two Harkonnen sisters combat forces that threaten humanity and establish the Bene Gesserit."
    movie.cast = ["Timothée Chalamet", "Zendaya Coleman", "Rebecca Ferguson", "Javier Bardem"]

    return NavigationStack {
        MediaDetailView(item: movie)
    }
    .environmentObject(AppState())
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.dark)
}

#Preview("Movie Detail — Light") {
    let movie = MediaItem(
        title: "DUNE: PROPHECY",
        fileURL: URL(fileURLWithPath: "/dune.mkv"),
        mediaType: .movie,
        fileSize: 68_000_000_000,
        duration: 8280
    )
    movie.year = 2024
    movie.genres = ["Sci-Fi"]
    movie.rating = 8.6
    movie.videoWidth = 3840
    movie.videoHeight = 2160
    movie.videoCodec = "HEVC"
    movie.dynamicRange = DynamicRange.dolbyVision.rawValue
    movie.audioTracks = [AudioTrackInfo(id: 0, codec: "truehd", channels: 8)]
    movie.overview = "Ten thousand years before the ascension of Paul Atreides, two Harkonnen sisters combat forces that threaten humanity and establish the Bene Gesserit."
    movie.cast = ["Timothée Chalamet", "Zendaya Coleman", "Rebecca Ferguson"]

    return NavigationStack {
        MediaDetailView(item: movie)
    }
    .environmentObject(AppState())
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.light)
}
