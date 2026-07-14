import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("metadata.autoDownload") private var metadataAutoDownload = true
    let item: MediaItem

    @State private var dominantColor: Color = .black.opacity(0.0)
    @State private var accentColor: Color = Color(hue: 0, saturation: 0.05, brightness: 0.88)
    @State private var isUpdatingFavorite = false
    @State private var favoriteErrorMessage: String?
    @State private var activeSheet: MediaDetailSheet?
    @State private var isHeroPosterLoaded = false
    @StateObject private var store = MediaDetailStore()

    /// 面板的三种形态：收起（不可见）/ 展开（固定 3/4 屏高）
    private enum PanelState { case collapsed, expanded }
    @State private var panelState: PanelState = .collapsed
    /// 拖拽过程中实时的手势位移
    @State private var dragOffset: CGFloat = 0
    /// 用户是否已主动操作过面板（拖拽/展开）。一旦交互过，加载完成后不再自动展开。
    @State private var userDidInteractWithPanel = false

    /// 媒体信息布局占屏高比例（不超过 3/4）
    private let panelHeightRatio: CGFloat = 0.75

    private let accentBlue = Color.vanmoAccent
    private let starYellow = Color(red: 245/255, green: 194/255, blue: 75/255)

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let panelHeight = totalHeight * panelHeightRatio
            let expandedTop = totalHeight - panelHeight          // 展开时面板顶部 Y
            let collapsedTop = totalHeight                        // 收起时面板完全移出屏幕
            let baseTop = panelState == .expanded ? expandedTop : collapsedTop
            let currentTop = min(max(baseTop + dragOffset, expandedTop), collapsedTop)
            // 0 = 收起，1 = 展开
            let reveal = max(0, min(1, (collapsedTop - currentTop) / panelHeight))
            // 收起态向下回拉（用于海报景深联动）
            let pullDown = panelState == .collapsed ? max(0, dragOffset) : 0

            ZStack(alignment: .top) {
                fixedPosterBackground(width: geometry.size.width,
                                      height: totalHeight,
                                      reveal: reveal,
                                      pullDown: pullDown)
                    .allowsHitTesting(false)

                // 收起态前景：底部标题 + 上滑指示器
                collapsedForeground
                    .frame(width: geometry.size.width, height: totalHeight, alignment: .bottom)
                    .opacity(1 - reveal)
                    .allowsHitTesting(panelState == .collapsed)
                    .contentShape(Rectangle())
                    .gesture(panelDrag())

                // 媒体信息面板
                mediaInfoPanel(panelHeight: panelHeight,
                               isScrollEnabled: panelState == .expanded && dragOffset == 0)
                    .frame(width: geometry.size.width, height: panelHeight)
                    .offset(y: currentTop)

                topNavBar(topPadding: geometry.safeAreaInsets.top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            let posterURL = displayPosterURL
            async let dominant = DominantColorExtractor.cachedColor(for: posterURL)
            async let accent = DominantColorExtractor.cachedAccentColor(for: posterURL)
            let (d, a) = await (dominant, accent)
            dominantColor = d
            accentColor = a
        }
        .task(id: metadataTaskID) {
            await store.load(
                item: item,
                modelContext: modelContext,
                autoDownloadMetadata: metadataAutoDownload
            )
            if !userDidInteractWithPanel, panelState == .collapsed {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    panelState = .expanded
                }
            }
        }
        .alert("收藏失败", isPresented: favoriteErrorBinding) {
            Button("确定") {}
        } message: {
            Text(favoriteErrorMessage ?? "")
        }
        .modifier(MediaDetailRefreshErrorPresenter(store: store))
        .overlay {
            if let sheet = activeSheet {
                modalOverlay(for: sheet)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: activeSheet)
    }

    // MARK: - 手势

    private func panelDrag() -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                userDidInteractWithPanel = true
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.height
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    switch panelState {
                    case .collapsed:
                        if predicted < -120 { panelState = .expanded }
                    case .expanded:
                        if predicted > 120 { panelState = .collapsed }
                    }
                    dragOffset = 0
                }
            }
    }

    // MARK: - 顶部导航

    private func topNavBar(topPadding: CGFloat) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.2), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            favoriteButton
        }
        .padding(.horizontal, 16)
        .padding(.top, topPadding > 0 ? topPadding + 8 : 48)
    }

    // MARK: - 背景海报（全屏沉浸 + 景深联动）

    private func fixedPosterBackground(width: CGFloat,
                                       height: CGFloat,
                                       reveal: CGFloat,
                                       pullDown: CGFloat) -> some View {
        let blurRadius = 22.0 * reveal
        // 展开时轻微缩小；收起态下拉时轻微放大（景深联动）
        let scale = 1.0 - (0.06 * reveal) + (pullDown / 2600)

        return ZStack {
            dominantColor

            heroBackdropImage(width: width, height: height)
                .blur(radius: blurRadius)
                .scaleEffect(scale)

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.35), location: 0.0),
                    .init(color: Color.black.opacity(0.10), location: 0.45),
                    .init(color: Color.black.opacity(0.55), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(0.85 + (0.15 * reveal))
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func heroBackdropImage(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            if !isHeroPosterLoaded {
                KFImage(item.posterURL)
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .scaleEffect(1.15)
                    .blur(radius: 24)
                    .clipped()
                    .transition(.opacity)
            }

            KFImage(displayPosterURL)
                .onSuccess { _ in
                    withAnimation(.easeOut(duration: 0.35)) {
                        isHeroPosterLoaded = true
                    }
                }
                .fade(duration: 0.35)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .scaleEffect(1.08)
                .clipped()
                .opacity(isHeroPosterLoaded ? 1 : 0)
        }
    }

    // MARK: - 收起态前景

    private var collapsedForeground: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                MediaDetailTitleLogoView(
                    title: collapsedTitle,
                    logoURL: store.content?.logoURL ?? item.logoURL,
                    collapsedStyle: true,
                    maxLogoHeight: 88
                )

                MediaDetailMetaRow(values: panelMetaValues, style: .collapsed)
            }
            .padding(.bottom, 90)

            collapsedHint
                .padding(.bottom, 50)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var collapsedHint: some View {
        if store.isLoading {
            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)

                Text("加载中")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.25), in: Circle())
                    .overlay { Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1) }

                Text("上滑查看详情")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    // MARK: - 媒体信息面板

    private func mediaInfoPanel(panelHeight: CGFloat, isScrollEnabled: Bool) -> some View {
        VStack(spacing: 0) {
            // 拖拽抓手（始终接管拖拽手势）
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 48, height: 6)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(panelDrag())

            // 媒体信息内容（展开后内部滚动）
            ScrollView {
                Group {
                    if store.isLoading || store.content == nil {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if item.mediaType == .tvShow {
                        tvShowPanelContent
                    } else {
                        moviePanelContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .scrollDisabled(!isScrollEnabled)
            .scrollIndicators(.hidden)
        }
        .frame(height: panelHeight, alignment: .top)
        .background(panelGlassBackground)
    }

    /// 媒体信息布局的液态玻璃背景（顶部圆角矩形 + Liquid Glass 质感 + 顶部高光边）
    /// iOS 26+ 使用系统液态玻璃 `glassEffect`，更低版本回退到毛玻璃材质。
    private var panelGlassBackground: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
        let isDark = colorScheme == .dark
        let tintColor = isDark ? Color(red: 9/255, green: 9/255, blue: 11/255).opacity(0.2) : Color.white.opacity(0.2)
        let borderColor = isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.2)
        let shadowColor = isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)

        return Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular.tint(tintColor), in: shape)
            } else {
                shape
                    .fill(tintColor)
                    .background(.ultraThinMaterial, in: shape)
            }
        }
        .overlay(
            shape.strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 28, y: -8)
        .ignoresSafeArea(edges: .bottom)
    }

    private var moviePanelContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: item.displayTitle)
            panelActions(play: { appState.play(item) })

            MediaDetailSynopsisSection(overview: displayOverview) { activeSheet = .synopsis }
            MediaDetailCastSection(members: store.content?.castMembers ?? [])
            MediaDetailCollectionsSection(collections: store.content?.collections ?? [], makeItem: makeCollectionItem)
            MediaDetailDetailsSection(
                director: store.content?.director,
                genres: displayGenres,
                directorLabel: "导演"
            )
        }
    }

    private var tvShowPanelContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: item.showTitle ?? item.title)
            panelActions(play: {
                if let ep = store.nextEpisodeToPlay { playEpisode(ep) }
            })

            MediaDetailSynopsisSection(overview: displayOverview) { activeSheet = .synopsis }
            MediaDetailEpisodesSection(
                episodes: store.currentSeasonEpisodes,
                seasonNumbers: store.seasonNumbers,
                selectedSeason: Binding(
                    get: { store.selectedSeason },
                    set: { season in
                        guard let season else { return }
                        Task {
                            await store.selectSeason(season, item: item, modelContext: modelContext)
                        }
                    }
                ),
                accentColor: Color.vanmoAccent,
                isLoadingEpisodes: store.isLoadingEpisodes,
                isLoadingMore: store.isLoadingMoreEpisodes,
                hasMoreEpisodes: store.hasMoreEpisodes,
                onPlay: playEpisode,
                onLoadMore: {
                    Task {
                        await store.loadMoreEpisodes(item: item, modelContext: modelContext)
                    }
                }
            )
            MediaDetailCastSection(members: store.content?.castMembers ?? [])
            MediaDetailCollectionsSection(collections: store.content?.collections ?? [], makeItem: makeCollectionItem)
            MediaDetailDetailsSection(
                director: store.content?.director,
                genres: displayGenres,
                directorLabel: "主创"
            )
        }
    }

    // MARK: - 面板子区块

    private func panelHeader(title: String) -> some View {
        MediaDetailPanelHeader(
            title: title,
            rating: store.content?.rating ?? item.rating,
            logoURL: store.content?.logoURL ?? item.logoURL,
            metaValues: panelMetaValues,
            starYellow: starYellow
        )
    }

    /// 元信息行的展示值（年份 / 类型 / 季数或时长），供收起态与 header 共用。
    private var panelMetaValues: [String] {
        var values: [String] = []
        if let year = item.year { values.append("\(year)") }
        if let genre = displayGenres.first { values.append(genre) }
        if item.mediaType == .tvShow {
            if !store.seasonNumbers.isEmpty {
                values.append("\(store.seasonNumbers.count) 季")
            }
        } else if item.duration > 0 {
            values.append(item.duration.shortDuration)
        }
        return values
    }

    private var displayGenres: [String] {
        let genres = store.content?.genres ?? []
        return genres.isEmpty ? item.genres : genres
    }

    private func tagView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }

    private func panelActions(play: @escaping () -> Void) -> some View {
        MediaDetailPanelActions(
            accentBlue: accentBlue,
            isRefreshing: store.isRefreshingMetadata,
            supportsMetadataRefresh: store.supportsMetadataRefresh(for: item, in: modelContext),
            play: play,
            refresh: { Task { await store.refreshMetadata(for: item, modelContext: modelContext, force: true) } }
        )
    }

    private func circleActionLabel(icon: String, isSystem: Bool = true) -> some View {
        Group {
            if isSystem {
                Image(systemName: icon)
                    .font(.system(size: 20))
            } else {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 56, height: 56)
        .background(
            Circle()
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func circleAction(icon: String, isSystem: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isSystem {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                } else {
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 状态逻辑

    private var metadataTaskID: String {
        MetadataCacheKey.from(item).cacheKey
    }

    private var collapsedTitle: String {
        item.mediaType == .tvShow ? (item.showTitle ?? item.title) : item.displayTitle
    }

    private var favoriteButton: some View {
        Button {
            Task { await setFavorite(!item.isFavorite) }
        } label: {
            ZStack {
                if isUpdatingFavorite {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.isFavorite ? .red : .white.opacity(0.95))
                }
            }
            .frame(width: 40, height: 40)
            .background(Color.black.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFavorite)
        .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")
        .accessibilityValue(isUpdatingFavorite ? "正在更新" : "")
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding {
            favoriteErrorMessage != nil
        } set: { isPresented in
            if !isPresented { favoriteErrorMessage = nil }
        }
    }

    private var displayOverview: String? {
        if let overview = store.content?.overview { return overview }
        guard let overview = item.overview, !overview.isEmpty else { return nil }
        return overview
    }

    private var displayPosterURL: URL? {
        highResolutionPosterURL(from: item.posterURL)
    }

    private func setFavorite(_ isFavorite: Bool) async {
        guard !isUpdatingFavorite else { return }

        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }

        do {
            try await EmbyFavoriteUpdater.setFavorite(
                item,
                isFavorite: isFavorite,
                connection: try? mediaServerConnectionSnapshot()
            )
            item.isFavorite = isFavorite
            try updateStoredFavoriteState(isFavorite)
            try modelContext.save()
            NotificationCenter.default.post(name: .mediaFavoriteDidChange, object: item)
        } catch {
            favoriteErrorMessage = error.localizedDescription
        }
    }

    private func updateStoredFavoriteState(_ isFavorite: Bool) throws {
        guard let serverId = item.serverId else { return }

        let sourceConnectionId = item.sourceConnectionId
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.serverId == serverId &&
                    mediaItem.sourceConnectionId == sourceConnectionId
            }
        )
        if let storedItem = try modelContext.fetch(descriptor).first {
            storedItem.isFavorite = isFavorite
        }
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
        appState.play(episodeItem)
    }

    private func makeCollectionItem(_ collection: ServerMediaItem) -> MediaItem {
        let collectionItem = ServerMediaItemMapper.makeMediaItem(from: collection)
        collectionItem.sourceConnectionId = item.sourceConnectionId
        return collectionItem
    }

    private func mediaServerConnectionSnapshot() throws -> MediaServerConnectionSnapshot? {
        try MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
    }

    private func initial(for name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private func highResolutionPosterURL(from url: URL?) -> URL? {
        guard let url,
              url.path.contains("/Items/"),
              url.path.contains("/Images/Primary"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { item in
            item.name.caseInsensitiveCompare("maxHeight") == .orderedSame ||
                item.name.caseInsensitiveCompare("maxWidth") == .orderedSame ||
                item.name.caseInsensitiveCompare("quality") == .orderedSame
        }
        queryItems.append(URLQueryItem(name: "maxHeight", value: "1800"))
        queryItems.append(URLQueryItem(name: "quality", value: "100"))
        components.queryItems = queryItems
        return components.url ?? url
    }

    // MARK: - 弹层

    private func modalOverlay(for sheet: MediaDetailSheet) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { activeSheet = nil }
                .transition(.opacity)

            VStack(alignment: .leading, spacing: 0) {
                Text(sheet == .synopsis ? "简介" : "详情")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.primary)
                    .padding(.top, 20)

                if sheet == .synopsis {
                    ScrollView {
                        Text(displayOverview ?? "暂无简介")
                            .font(.system(size: 14))
                            .lineSpacing(8)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 18)
                    }
                    .frame(maxHeight: 360)
                }
            }
            .padding(.horizontal, 23)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 24)
            .overlay(alignment: .topTrailing) {
                Button { activeSheet = nil } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
        }
    }
}

private enum MediaDetailSheet: Identifiable, Equatable {
    case synopsis
    case cast
    case episodes

    var id: String {
        switch self {
        case .synopsis: return "synopsis"
        case .cast: return "cast"
        case .episodes: return "episodes"
        }
    }
}

/// 详情页信息面板的聚合快照：所有异步数据一次性组装，供 UI 单次刷新。
struct MediaDetailContent {
    var rating: Double?
    var logoURL: URL?
    var overview: String?
    var genres: [String]
    var director: String?
    var castMembers: [CastMemberDisplay]
    var seasons: [SeasonInfo]
    var collections: [ServerMediaItem]
}

@MainActor
final class MediaDetailStore: ObservableObject {
    @Published private(set) var content: MediaDetailContent?
    @Published private(set) var isLoading = false
    @Published private(set) var selectedSeason: Int?
    @Published private(set) var seasonEpisodes: [EpisodeInfo] = []
    @Published private(set) var isLoadingEpisodes = false
    @Published private(set) var isLoadingMoreEpisodes = false
    @Published private(set) var hasMoreEpisodes = false
    @Published private(set) var isRefreshingMetadata = false
    @Published var refreshErrorMessage: String?

    private var loadedKey: String?
    private var loadGeneration = 0
    private var episodeStartIndex = 0
    private var episodeLoadGeneration = 0
    private var metadataCacheRecord: MetadataCacheRecord?
    private var metadataRootDirectory: URL?

    private let episodePageSize = 20

    // MARK: - 派生

    var seasonNumbers: [Int] {
        (content?.seasons ?? []).map(\.seasonNumber)
    }

    var currentSeasonEpisodes: [EpisodeInfo] {
        seasonEpisodes
    }

    var nextEpisodeToPlay: EpisodeInfo? {
        seasonEpisodes
            .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
            .first
    }

    func supportsMetadataRefresh(for item: MediaItem, in modelContext: ModelContext) -> Bool {
        if (try? connectionSnapshot(for: item, in: modelContext)) != nil {
            return true
        }
        return MetadataRefreshCoordinator.supportsRefresh(for: item)
    }

    // MARK: - Loading

    func load(item: MediaItem, modelContext: ModelContext, autoDownloadMetadata: Bool) async {
        let key = detailKey(for: item)
        guard loadedKey != key else { return }
        loadedKey = key
        loadGeneration += 1
        let generation = loadGeneration

        isLoading = true
        content = nil
        resetEpisodePagingState()

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

        await performAggregate(
            item: item,
            modelContext: modelContext,
            autoDownloadMetadata: true,
            force: force,
            generation: loadGeneration
        )
    }

    func selectSeason(_ season: Int, item: MediaItem, modelContext: ModelContext) async {
        guard selectedSeason != season else { return }
        selectedSeason = season
        await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
    }

    func loadMoreEpisodes(item: MediaItem, modelContext: ModelContext) async {
        guard hasMoreEpisodes, !isLoadingMoreEpisodes, !isLoadingEpisodes else { return }
        await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: false)
    }

    /// 并行发起全部异步请求，等待全部完成后聚合成一份快照，对 UI 做一次性刷新。
    /// - Parameter generation: 本次加载代际号，回写前校验，避免旧 item 结果覆盖新 item。
    private func performAggregate(
        item: MediaItem,
        modelContext: ModelContext,
        autoDownloadMetadata: Bool,
        force: Bool,
        generation: Int
    ) async {
        async let enrichedTask = fetchEnrichment(item: item, modelContext: modelContext)
        async let seasonsTask = fetchSeasons(item: item, modelContext: modelContext)
        async let collectionsTask = fetchCollections(item: item, modelContext: modelContext)
        async let recordTask = fetchMetadataRecord(
            item: item,
            modelContext: modelContext,
            enabled: autoDownloadMetadata,
            force: force
        )

        let enriched = await enrichedTask
        var loadedSeasons = await seasonsTask
        let loadedCollections = await collectionsTask
        let record = await recordTask

        let root = (try? await MetadataCache.shared.rootDirectoryURL())
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        metadataCacheRecord = record
        metadataRootDirectory = root

        if loadedSeasons.isEmpty, let record, item.mediaType == .tvShow {
            loadedSeasons = seasonInfos(from: record)
        }

        var castMembers = record?.makeCastDisplays(rootDirectory: root) ?? []
        if castMembers.isEmpty {
            let names = (enriched?.cast.isEmpty == false) ? (enriched?.cast ?? []) : item.cast
            castMembers = names.map { CastMemberDisplay(id: $0, name: $0, role: nil, profileURL: nil) }
        }

        let snapshot = MediaDetailContent(
            rating: record?.rating ?? item.rating,
            logoURL: record?.resolvedLogoURL(rootDirectory: root) ?? item.logoURL,
            overview: resolvedOverview(enriched: enriched, item: item),
            genres: resolvedGenres(enriched: enriched, item: item),
            director: resolvedDirector(enriched: enriched, item: item),
            castMembers: castMembers,
            seasons: loadedSeasons,
            collections: loadedCollections
        )

        // 代际校验：加载期间若切换到其它 item，丢弃本次结果。
        guard generation == loadGeneration else { return }

        content = snapshot
        let previousSeason = selectedSeason
        if let previousSeason, loadedSeasons.contains(where: { $0.seasonNumber == previousSeason }) {
            selectedSeason = previousSeason
        } else {
            selectedSeason = loadedSeasons.first?.seasonNumber
        }
        isLoading = false

        if item.mediaType == .tvShow, selectedSeason != nil {
            await loadSeasonEpisodes(item: item, modelContext: modelContext, reset: true)
        }
    }

    private func resetEpisodePagingState() {
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

    // MARK: - 并行取数

    private func fetchEnrichment(item: MediaItem, modelContext: ModelContext) async -> ServerMediaItem? {
        guard shouldEnrichFromServer(item: item, modelContext: modelContext),
              let serverId = item.serverId else { return nil }

        do {
            if let snapshot = try? connectionSnapshot(for: item, in: modelContext) {
                return try await EmbyItemDetailFetcher.fetchDetail(itemId: serverId, connection: snapshot)
            }
            return try await EmbyItemDetailFetcher.fetchDetail(itemId: serverId)
        } catch {
            VanmoLogger.library.error("[MediaDetail] Failed to enrich item detail: \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchSeasons(item: MediaItem, modelContext: ModelContext) async -> [SeasonInfo] {
        guard item.mediaType == .tvShow, let seriesServerId = item.serverId else { return [] }

        do {
            let snapshot = try? connectionSnapshot(for: item, in: modelContext)
            switch item.fileURL.host {
            case "plex-series":
                if let snapshot {
                    return try await PlexEpisodeFetcher.fetchSeasons(
                        seriesRatingKey: seriesServerId,
                        connection: snapshot
                    )
                }
                return try await PlexEpisodeFetcher.fetchSeasons(seriesRatingKey: seriesServerId)
            default:
                if let snapshot {
                    return try await EmbyEpisodeFetcher.fetchSeasons(
                        seriesId: seriesServerId,
                        connection: snapshot
                    )
                }
                return try await EmbyEpisodeFetcher.fetchSeasons(seriesId: seriesServerId)
            }
        } catch {
            VanmoLogger.library.error("[MediaServer] Failed to load seasons: \(error.localizedDescription)")
            return []
        }
    }

    private func loadSeasonEpisodes(item: MediaItem, modelContext: ModelContext, reset: Bool) async {
        guard item.mediaType == .tvShow else { return }
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

            let merged = mergeEpisodeBackdrops(page.items, for: item)
            if reset {
                seasonEpisodes = merged
            } else {
                let existingIDs = Set(seasonEpisodes.map(\.id))
                seasonEpisodes.append(contentsOf: merged.filter { !existingIDs.contains($0.id) })
            }

            episodeStartIndex = startIndex + page.items.count
            hasMoreEpisodes = page.items.count >= episodePageSize
                && episodeStartIndex < page.totalRecordCount
        } catch {
            VanmoLogger.library.error("[MediaServer] Failed to load season episodes: \(error.localizedDescription)")
            guard generation == episodeLoadGeneration else { return }

            if reset, let fallback = cachedEpisodes(for: season, item: item), !fallback.isEmpty {
                seasonEpisodes = fallback
                episodeStartIndex = fallback.count
                hasMoreEpisodes = false
            } else if reset {
                seasonEpisodes = []
                hasMoreEpisodes = false
            }
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

    private func fetchCollections(item: MediaItem, modelContext: ModelContext) async -> [ServerMediaItem] {
        guard let serverId = item.serverId, item.mediaType != .boxSet else { return [] }

        do {
            if let snapshot = try? connectionSnapshot(for: item, in: modelContext) {
                guard snapshot.type == .emby || snapshot.type == .jellyfin else { return [] }
                return try await EmbyCollectionsFetcher.fetchCollections(containing: serverId, connection: snapshot)
            } else if isEmbyOriginItem(item) {
                return try await EmbyCollectionsFetcher.fetchCollections(containing: serverId)
            } else {
                return []
            }
        } catch {
            VanmoLogger.library.error("[MediaDetail] Failed to load collections: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchMetadataRecord(
        item: MediaItem,
        modelContext: ModelContext,
        enabled: Bool,
        force: Bool
    ) async -> MetadataCacheRecord? {
        let key = MetadataCacheKey.from(item)
        let cached = await MetadataCache.shared.load(for: key)

        guard enabled, supportsMetadataRefresh(for: item, in: modelContext) else { return cached }

        do {
            if let draft = try await MetadataRefreshCoordinator.shared.prepareRefreshDraft(
                item,
                force: force,
                connection: try? connectionSnapshot(for: item, in: modelContext)
            ) {
                return try await MetadataCache.shared.save(draft)
            }
            return cached
        } catch {
            refreshErrorMessage = error.localizedDescription
            return cached
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
                backdropURL: backdropURL
            )
        }
    }

    // MARK: - 回退解析

    private func resolvedOverview(enriched: ServerMediaItem?, item: MediaItem) -> String? {
        let overview = enriched?.overview ?? item.overview
        guard let overview, !overview.isEmpty else { return nil }
        return overview
    }

    private func resolvedGenres(enriched: ServerMediaItem?, item: MediaItem) -> [String] {
        if let genres = enriched?.genres, !genres.isEmpty { return genres }
        return item.genres
    }

    private func resolvedDirector(enriched: ServerMediaItem?, item: MediaItem) -> String? {
        if let director = enriched?.director, !director.isEmpty { return director }
        return item.director
    }

    // MARK: - 支持

    private func detailKey(for item: MediaItem) -> String {
        MetadataCacheKey.from(item).cacheKey
    }

    private func shouldEnrichFromServer(item: MediaItem, modelContext: ModelContext) -> Bool {
        guard let serverId = item.serverId,
              !serverId.isEmpty,
              needsServerDetailFields(item) else {
            return false
        }
        if let snapshot = try? connectionSnapshot(for: item, in: modelContext) {
            return snapshot.type == .emby || snapshot.type == .jellyfin
        }
        return isEmbyOriginItem(item) &&
            EmbyCredentialStore.baseURL != nil &&
            EmbyCredentialStore.userId != nil &&
            EmbyCredentialStore.token != nil
    }

    private func needsServerDetailFields(_ item: MediaItem) -> Bool {
        item.overview == nil ||
            item.overview?.isEmpty == true ||
            item.cast.isEmpty ||
            item.director == nil ||
            item.genres.isEmpty ||
            item.backdropURL == nil
    }

    private func isEmbyOriginItem(_ item: MediaItem) -> Bool {
        if item.fileURL.scheme == "vanmo" {
            switch item.fileURL.host?.lowercased() {
            case "series", "emby-container", "emby-item":
                return true
            default:
                return false
            }
        }
        guard let baseHost = EmbyCredentialStore.baseURL.flatMap({ URL(string: $0)?.host?.lowercased() }),
              let itemHost = item.fileURL.host?.lowercased() else {
            return false
        }
        return baseHost == itemHost
    }

    private func connectionSnapshot(for item: MediaItem, in modelContext: ModelContext) throws -> MediaServerConnectionSnapshot? {
        try MediaServerConnectionResolver.snapshot(for: item, in: modelContext)
    }
}

private struct MediaDetailRefreshErrorPresenter: ViewModifier {
    @ObservedObject var store: MediaDetailStore

    private var refreshErrorBinding: Binding<Bool> {
        Binding {
            store.refreshErrorMessage != nil
        } set: { isPresented in
            if !isPresented { store.refreshErrorMessage = nil }
        }
    }

    func body(content: Content) -> some View {
        content
            .alert("刷新失败", isPresented: refreshErrorBinding) {
                Button("确定") {}
            } message: {
                Text(store.refreshErrorMessage ?? "")
            }
    }
}

private struct MediaDetailTitleLogoView: View {
    let title: String
    let logoURL: URL?
    var collapsedStyle = false
    var maxLogoHeight: CGFloat = 72

    var body: some View {
        MediaTitleLogoView(
            title: title,
            logoURL: logoURL,
            collapsedStyle: collapsedStyle,
            maxLogoHeight: maxLogoHeight
        )
    }
}

private struct MediaDetailPanelHeader: View {
    let title: String
    let rating: Double?
    let logoURL: URL?
    let metaValues: [String]
    let starYellow: Color

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            MediaDetailTitleLogoView(
                title: title,
                logoURL: logoURL,
                maxLogoHeight: 72
            )

            MediaDetailMetaRow(values: metaValues, style: .header)

            HStack(spacing: 6) {
                tagView("TV-MA")
                tagView("4K")
                tagView("DOLBY")
            }

            MediaDetailRatingRow(rating: rating, starYellow: starYellow)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func tagView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct MediaDetailRatingRow: View {
    let rating: Double?
    let starYellow: Color

    var body: some View {
        if let rating {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundStyle(starYellow)
                    .font(.system(size: 16))
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("(450K Reviews)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .animation(.easeInOut(duration: 0.25), value: rating)
        }
    }
}

private struct MediaDetailPanelActions: View {
    let accentBlue: Color
    let isRefreshing: Bool
    let supportsMetadataRefresh: Bool
    let play: () -> Void
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("播放")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(accentBlue)
                .clipShape(Capsule())
                .shadow(color: accentBlue.opacity(0.25), radius: 8, y: 6)
            }
            .buttonStyle(.plain)

            circleAction(icon: "icon_download", isSystem: false) {}

            Menu {
                if supportsMetadataRefresh {
                    Button {
                        refresh()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            } label: {
                circleActionLabel(icon: "ellipsis")
            }
            .disabled(isRefreshing || !supportsMetadataRefresh)
        }
    }

    private func circleActionLabel(icon: String, isSystem: Bool = true) -> some View {
        Group {
            if isSystem {
                Image(systemName: icon)
                    .font(.system(size: 20))
            } else {
                Image(icon)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 56, height: 56)
        .background(
            Circle()
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            Circle()
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private func circleAction(icon: String, isSystem: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            circleActionLabel(icon: icon, isSystem: isSystem)
        }
        .buttonStyle(.plain)
    }
}

private struct MediaDetailCastSection: View {
    let members: [CastMemberDisplay]

    var body: some View {
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("主演")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(members) { member in
                            MediaDetailCastAvatar(member: member)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, -24)
            }
        }
    }
}

private struct MediaDetailCastAvatar: View {
    let member: CastMemberDisplay

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))

                if let profileURL = member.profileURL {
                    KFImage(profileURL)
                        .placeholder {
                            Text(initial(for: member.name))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .fade(duration: 0.2)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    Text(initial(for: member.name))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            Text(member.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 80)
        }
    }

    private func initial(for name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }
}

private struct MediaDetailCollectionsSection: View {
    let collections: [ServerMediaItem]
    let makeItem: (ServerMediaItem) -> MediaItem

    var body: some View {
        if !collections.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("合集")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

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
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, -24)
            }
        }
    }
}

private struct MediaDetailCollectionCard: View {
    let collection: ServerMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))

                if let posterURL = collection.posterURL {
                    KFImage(posterURL)
                        .fade(duration: 0.2)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.vanmoPrimary)
                }
            }
            .frame(width: 120, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(collection.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
        }
    }
}

private struct MediaDetailMetaRow: View {
    enum Style { case collapsed, header }

    let values: [String]
    let style: Style

    var body: some View {
        if !values.isEmpty {
            HStack(spacing: style == .collapsed ? 8 : 6) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    if index > 0 {
                        Circle()
                            .fill(style == .collapsed ? Color.white.opacity(0.5) : Color.secondary.opacity(0.5))
                            .frame(width: 4, height: 4)
                    }
                    Text(value)
                        .font(.system(size: style == .collapsed ? 14 : 12,
                                      weight: style == .collapsed ? .medium : .semibold))
                        .foregroundStyle(style == .collapsed
                            ? AnyShapeStyle(Color.white.opacity(0.85))
                            : AnyShapeStyle(.secondary))
                }
            }
        }
    }
}

private struct MediaDetailSynopsisSection: View {
    let overview: String?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("简介")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Text(overview ?? "暂无简介")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
        }
    }
}

private struct MediaDetailDetailsSection: View {
    let director: String?
    let genres: [String]
    let directorLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("详情")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 8)

            if let director {
                detailRow(title: directorLabel, value: director)
            }
            if !genres.isEmpty {
                detailRow(title: "类型", value: genres.joined(separator: " / "))
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .leading)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
            Divider()
        }
    }
}

private struct MediaDetailEpisodesSection: View {
    let episodes: [EpisodeInfo]
    let seasonNumbers: [Int]
    @Binding var selectedSeason: Int?
    let accentColor: Color
    var isLoadingEpisodes: Bool = false
    var isLoadingMore: Bool = false
    var hasMoreEpisodes: Bool = false
    let onPlay: (EpisodeInfo) -> Void
    var onLoadMore: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("剧集")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                if seasonNumbers.count > 1 {
                    Spacer()
                    Menu {
                        ForEach(seasonNumbers, id: \.self) { season in
                            Button("第 \(season) 季") { selectedSeason = season }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("第 \(selectedSeason ?? seasonNumbers.first ?? 1) 季")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    }
                }
            }

            if isLoadingEpisodes && episodes.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if episodes.isEmpty {
                Text("暂无剧集")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(episodes) { episode in
                        episodeRow(episode)
                            .id(episode.id)
                    }

                    if hasMoreEpisodes || isLoadingMore {
                        Group {
                            if isLoadingMore {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else {
                                Color.clear
                                    .frame(height: 1)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .onAppear {
                            onLoadMore?()
                        }
                    }
                }
            }
        }
    }

    private func episodeRow(_ episode: EpisodeInfo) -> some View {
        Button {
            onPlay(episode)
        } label: {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    if let backdropURL = episode.backdropURL {
                        KFImage(backdropURL)
                            .placeholder { thumbnailPlaceholder }
                            .fade(duration: 0.2)
                            .resizable()
                            .scaledToFill()
                            .id(backdropURL)
                    } else {
                        thumbnailPlaceholder
                    }

                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(accentColor, in: Circle())
                }
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text("\(episode.episodeNumber). \(episode.title.isEmpty ? "第 \(episode.episodeNumber) 集" : episode.title)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(episode.duration > 0 ? episode.duration.shortDuration : "-- 分钟")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Text(episode.overview ?? "暂无简介")
                        .font(.system(size: 12))
                        .lineSpacing(3)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.top, 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemBackground))
    }
}

#Preview {
    NavigationStack {
        MediaDetailView(item: MediaItem(
            title: "DUNE: PART TWO",
            fileURL: URL(fileURLWithPath: "/test.mkv"),
            mediaType: .movie,
            fileSize: 4_500_000_000,
            duration: 8880
        ))
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}















