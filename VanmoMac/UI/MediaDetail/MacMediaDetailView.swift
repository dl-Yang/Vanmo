import SwiftUI
import SwiftData
import VanmoCore

struct MacMediaDetailView: View {
    @EnvironmentObject private var appState: MacAppState
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
        .alert("下载失败", isPresented: Binding(
            get: { downloadErrorMessage != nil },
            set: { if !$0 { downloadErrorMessage = nil } }
        )) {
            Button("确定") {}
        } message: {
            Text(downloadErrorMessage ?? "")
        }
        .sheet(isPresented: $isDownloadPickerPresented) {
            MacEpisodeDownloadPicker(
                episodes: store.currentSeasonEpisodes,
                seasonNumbers: store.seasonNumbers,
                selectedSeason: store.selectedSeason,
                selectedEpisodes: $selectedDownloadEpisodes,
                isLoading: store.isLoadingEpisodes || store.isLoadingMoreEpisodes,
                isConfirming: isEnqueueingDownload,
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

    @ViewBuilder
    private var skeletonView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if #available(macOS 26.0, *) {
                    Color.clear
                        .glassEffect(.regular.tint(theme.secondaryButtonBackground), in: Rectangle())
                } else {
                    Rectangle()
                        .fill(theme.secondaryButtonBackground)
                }
            }
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
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        playButton
                        favoriteButton
                        downloadButton
                        watchedButton
                        moreMenu
                    }
                }
            } else {
                HStack(spacing: 16) {
                    playButton
                    favoriteButton
                    downloadButton
                    watchedButton
                    moreMenu
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var playButton: some View {
        let action = {
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
        }

        if #available(macOS 26.0, *) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Play")
                        .font(.system(size: 16, weight: .semibold))
                }
                .padding(.horizontal, 16)
            }
            .buttonStyle(.glassProminent)
            .tint(MacDesignTokens.accentBlue)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        } else {
            Button(action: action) {
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
        }
    }

    @ViewBuilder
    private var favoriteButton: some View {
        let isFav = store.isFavorite
        let action: () -> Void = { Task { await store.toggleFavorite(for: item, modelContext: modelContext) } }

        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    if store.isUpdatingFavorite {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isFav ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
//                .tint(isFav ? Color.red : Color.primary)
                .controlSize(.large)
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    ZStack {
                        if store.isUpdatingFavorite {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: isFav ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(isFav ? .red : theme.primaryText)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(theme.secondaryButtonBackground)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(store.isUpdatingFavorite)
        .help(isFav ? "取消收藏" : "收藏")
    }

    @ViewBuilder
    private var downloadButton: some View {
        let action = beginDownload
        let content = MacDownloadProgressButtonContent(
            task: displayedDownloadTask,
            isEnqueueing: isEnqueueingDownload,
            idleColor: theme.primaryText,
            trackColor: theme.progressTrack
        )

        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    content
                        .frame(width: 17, height: 17)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    content
                        .frame(width: 40, height: 40)
                        .background(theme.secondaryButtonBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(isDownloadButtonDisabled)
        .help(item.mediaType == .tvShow ? "选择剧集下载" : "下载")
    }

    @ViewBuilder
    private var watchedButton: some View {
        let isWatched = item.isWatched
        let action: () -> Void = { Task { await store.toggleWatched(for: item, modelContext: modelContext) } }

        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    if store.isUpdatingWatched {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .buttonStyle(.glass)
//                .tint(isWatched ? MacDesignTokens.accentBlue : Color.primary)
                .controlSize(.large)
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    ZStack {
                        if store.isUpdatingWatched {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(isWatched ? MacDesignTokens.accentBlue : theme.primaryText)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(theme.secondaryButtonBackground)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .disabled(store.isUpdatingWatched)
        .help(isWatched ? "标记未看" : "标记已看")
    }

    @ViewBuilder
    private var moreMenu: some View {
        let menuContent = Group {
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
        }

        if #available(macOS 26.0, *) {
            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.glass)
            .controlSize(.large)
            .buttonBorderShape(.circle)
            .help("更多")
        } else {
            Menu {
                menuContent
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
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .center, spacing: 16) {
                                ForEach(store.currentSeasonEpisodes) { episode in
                                    episodeCard(episode)
                                        .id(episode.id)
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
                            .padding(.horizontal, 15)
                        }
                        .frame(height: 172)
                        .task(id: focusedEpisode) {
                            await focusRequestedEpisode(using: proxy)
                        }
                    }
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
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isFocusedEpisode(episode) ? MacDesignTokens.accentBlue : Color.clear,
                            lineWidth: 2
                        )
                }

                Text(episode.title.isEmpty ? "第 \(episode.episodeNumber) 集" : "\(episode.episodeNumber) \(episode.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
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

    @ViewBuilder
    private func metadataChip(_ text: String) -> some View {
        if #available(macOS 26.0, *) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.chipText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background {
                    Color.clear.glassEffect(.regular.tint(theme.chipBackground), in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip))
                }
        } else {
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

    private var displayedDownloadTask: DownloadTaskSnapshot? {
        // 剧集详情的下载按钮表示整部剧的批量队列；即使由某一集跳入详情，
        // 仍应优先展示当前实际下载集，而不是被定位集的静态状态。
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
#if DEBUG
                    print("[Debug][Downloads] enqueued source=detail mediaType=\(item.mediaType.rawValue) connection=\(request.connectionType?.rawValue ?? "none")")
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
#if DEBUG
                print("[Debug][Downloads] enqueued source=detail-episodes count=\(requests.count) connection=\(connectionType?.rawValue ?? "none")")
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

private struct MacDownloadProgressButtonContent: View {
    let task: DownloadTaskSnapshot?
    let isEnqueueing: Bool
    let idleColor: Color
    let trackColor: Color

    var body: some View {
        Group {
            if let task {
                taskContent(task)
            } else if isEnqueueing {
                indicator(progress: nil, color: MacDesignTokens.accentBlue)
            } else {
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(idleColor)
            }
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder
    private func taskContent(_ task: DownloadTaskSnapshot) -> some View {
        switch task.status {
        case .queued:
            indicator(progress: nil, color: MacDesignTokens.accentBlue)
        case .downloading:
            indicator(
                progress: task.totalBytes > 0 ? task.progress : nil,
                color: MacDesignTokens.accentBlue
            )
        case .paused:
            indicator(
                progress: task.progress,
                color: MacDesignTokens.accentBlue,
                symbol: "pause.fill"
            )
        case .completed:
            indicator(progress: 1, color: .green, symbol: "checkmark")
        case .failed:
            Image(systemName: "arrow.down")
                .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 28, height: 28)
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

#Preview {
    MacMediaDetailView(item: MacMediaDetailPreviewItem.make())
        .environmentObject(MacAppState())
        .environmentObject(DownloadManager.shared)
        .macTheme(.dark)
        .frame(width: 1214, height: 836)
}

private struct MacEpisodeDownloadPicker: View {
    @Environment(\.dismiss) private var dismiss
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
                Text("选择下载剧集")
                    .font(.title2.bold())
                Spacer()
                Picker("季", selection: Binding(
                    get: { selectedSeason ?? seasonNumbers.first ?? 1 },
                    set: onSelectSeason
                )) {
                    ForEach(seasonNumbers, id: \.self) { season in
                        Text("第 \(season) 季").tag(season)
                    }
                }
                .frame(width: 120)
                .disabled(isConfirming)
            }
            .padding()

            HStack {
                Button(allCurrentSeasonSelected ? "取消全选本季" : "全选本季") {
                    toggleCurrentSeason()
                }
                .disabled(isConfirming)
                Spacer()
                if isLoading || isConfirming { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal)

            List {
                ForEach(Array(episodes.enumerated()), id: \.offset) { _, episode in
                    Button {
                        toggle(episode)
                    } label: {
                        HStack {
                            Image(systemName: selectedEpisodes[episode.id] == nil ? "circle" : "checkmark.circle.fill")
                            Text("第 \(episode.episodeNumber) 集 · \(episode.title)")
                            Spacer()
                            if episode.duration > 0 {
                                Text(MacFormatters.formatDuration(episode.duration))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isConfirming)
                }
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .disabled(isConfirming)
                if #available(macOS 26.0, *) {
                    Button(confirmButtonTitle, action: onConfirm)
                        .buttonStyle(.glassProminent)
                        .tint(MacDesignTokens.accentBlue)
                        .disabled(selectedEpisodes.isEmpty || isLoading || isConfirming)
                } else {
                    Button(confirmButtonTitle, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedEpisodes.isEmpty || isLoading || isConfirming)
                }
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var allCurrentSeasonSelected: Bool {
        !episodes.isEmpty && episodes.allSatisfy { selectedEpisodes[$0.id] != nil }
    }

    private var confirmButtonTitle: String {
        isConfirming ? "正在加入…" : "下载 \(selectedEpisodes.count) 集"
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
