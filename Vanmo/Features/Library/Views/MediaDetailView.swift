import SwiftUI
import SwiftData
import Kingfisher

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("metadata.autoDownload") private var metadataAutoDownload = true
    let item: MediaItem

    @State private var dominantColor: Color = .black.opacity(0.0)
    @State private var accentColor: Color = Color(hue: 0, saturation: 0.05, brightness: 0.88)
    @State private var episodes: [EpisodeInfo] = []
    @State private var isLoadingEpisodes = false
    @State private var isUpdatingFavorite = false
    @State private var favoriteErrorMessage: String?
    @State private var selectedSeason: Int?
    @State private var enrichedItem: ServerMediaItem?
    @State private var activeSheet: MediaDetailSheet?
    @State private var isHeroPosterLoaded = false
    @State private var ratingStore = MediaDetailRatingStore()
    @State private var refreshStore = MediaDetailRefreshStore()
    @State private var castStore = MediaDetailCastStore()

    /// 面板的三种形态：收起（不可见）/ 展开（固定 3/4 屏高）
    private enum PanelState { case collapsed, expanded }
    @State private var panelState: PanelState = .collapsed
    /// 拖拽过程中实时的手势位移
    @State private var dragOffset: CGFloat = 0

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
            ratingStore.updateRating(item.rating)
            let posterURL = displayPosterURL
            async let dominant = DominantColorExtractor.cachedColor(for: posterURL)
            async let accent = DominantColorExtractor.cachedAccentColor(for: posterURL)
            let (d, a) = await (dominant, accent)
            dominantColor = d
            accentColor = a
        }
        .task {
            if item.mediaType == .tvShow {
                await loadEpisodes()
            }
        }
        .task(id: item.serverId) {
            await enrichItemDetailIfNeeded()
        }
        .task(id: metadataTaskID) {
            guard supportsMetadataRefresh else { return }
            await loadCachedMetadataIfNeeded()
            if metadataAutoDownload {
                await refreshMetadata(force: false)
            }
        }
        .alert("收藏失败", isPresented: favoriteErrorBinding) {
            Button("确定") {}
        } message: {
            Text(favoriteErrorMessage ?? "")
        }
        .modifier(MediaDetailRefreshErrorPresenter(store: refreshStore))
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
                MediaTitleLogoView(
                    title: collapsedTitle,
                    logoURL: displayLogoURL,
                    collapsedStyle: true,
                    maxLogoHeight: 88
                )

                HStack(spacing: 8) {
                    ForEach(Array(collapsedMetaItems.enumerated()), id: \.offset) { index, value in
                        if index > 0 {
                            Circle().fill(.white.opacity(0.5)).frame(width: 4, height: 4)
                        }
                        Text(value)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(.bottom, 90)

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
            .padding(.bottom, 50)
        }
    }

    private var collapsedMetaItems: [String] {
        var values: [String] = []
        if let year = item.year { values.append("\(year)") }
        if let genre = displayGenres.first { values.append(genre) }
        if item.mediaType == .tvShow {
            if !seasonNumbers.isEmpty {
                values.append("\(seasonNumbers.count) 季")
            }
        } else if item.duration > 0 {
            values.append(item.duration.shortDuration)
        }
        return values
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
                    if item.mediaType == .tvShow {
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

            synopsisSection
            castSection
            detailsSection(directorLabel: "导演")
        }
    }

    private var tvShowPanelContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            panelHeader(title: item.showTitle ?? item.title)
            panelActions(play: {
                if let ep = nextEpisodeToPlay { playEpisode(ep) }
            })

            synopsisSection
            episodesSection
            castSection
            detailsSection(directorLabel: "主创")
        }
    }

    // MARK: - 面板子区块

    private func panelHeader(title: String) -> some View {
        MediaDetailPanelHeader(
            title: title,
            logoURL: displayLogoURL,
            metaItems: collapsedMetaItems,
            store: ratingStore,
            starYellow: starYellow
        )
    }

    private func ratingRow(_ rating: Double) -> some View {
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
            store: refreshStore,
            supportsMetadataRefresh: supportsMetadataRefresh,
            play: play,
            refresh: { Task { await refreshMetadata(force: true) } }
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

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("简介")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
            Text(displayOverview ?? "暂无简介")
                .font(.system(size: 15))
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { activeSheet = .synopsis }
        }
    }

    @ViewBuilder
    private var castSection: some View {
        MediaDetailCastSection(
            store: castStore,
            fallbackNames: displayCast
        )
    }

    private var resolvedCastMembers: [CastMemberDisplay] {
        if !castStore.members.isEmpty {
            return castStore.members
        }
        return displayCast.map { name in
            CastMemberDisplay(id: name, name: name, role: nil, profileURL: nil)
        }
    }

    @ViewBuilder
    private var episodesSection: some View {
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

            if isLoadingEpisodes {
                ProgressView()
                    .tint(Color.vanmoAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if currentSeasonEpisodes.isEmpty {
                Text("暂无剧集")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 16) {
                    ForEach(currentSeasonEpisodes) { episode in
                        tvEpisodeRow(episode)
                            .id(episode.id)
                    }
                }
            }
        }
    }

    private func detailsSection(directorLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("详情")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.bottom, 8)

            if let director = displayDirector {
                detailRow(title: directorLabel, value: director)
            }
            if !displayGenres.isEmpty {
                detailRow(title: "类型", value: displayGenres.joined(separator: " / "))
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

    private func tvEpisodeRow(_ episode: EpisodeInfo) -> some View {
        Button {
            playEpisode(episode)
        } label: {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    if let backdropURL = episode.backdropURL {
                        KFImage(backdropURL)
                            .placeholder { episodeThumbnailPlaceholder }
                            .fade(duration: 0.2)
                            .resizable()
                            .scaledToFill()
                            .id(backdropURL)
                    } else {
                        episodeThumbnailPlaceholder
                    }

                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.vanmoAccent, in: Circle())
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

    private var episodeThumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemBackground))
    }

    // MARK: - 状态逻辑

    private var supportsMetadataRefresh: Bool {
        MetadataRefreshCoordinator.supportsRefresh(for: item)
    }

    private var metadataTaskID: String {
        MetadataCacheKey.from(item).cacheKey
    }

    private var collapsedTitle: String {
        item.mediaType == .tvShow ? (item.showTitle ?? item.title) : item.displayTitle
    }

    private var displayLogoURL: URL? {
        item.logoURL
    }

    private func loadCachedMetadataIfNeeded() async {
        let key = MetadataCacheKey.from(item)
        guard let record = await MetadataCache.shared.load(for: key) else { return }
        await applyRecordToUI(record)
    }

    @MainActor
    private func refreshMetadata(force: Bool) async {
        guard supportsMetadataRefresh else { return }
        guard !refreshStore.isRefreshingMetadata else { return }

        refreshStore.beginRefreshing()
        defer { refreshStore.finishRefreshing() }

        do {
            let record = try await MetadataRefreshCoordinator.shared.refresh(item, force: force)
            await applyRecordToUI(record)
        } catch {
            refreshStore.failRefreshing(error.localizedDescription)
        }
    }

    @MainActor
    private func applyRecordToUI(_ record: MetadataCacheRecord) async {
        if let rating = record.rating {
            ratingStore.updateRating(rating)
        }

        let root = (try? await MetadataCache.shared.rootDirectoryURL()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let castDisplays = record.makeCastDisplays(rootDirectory: root)
        castStore.update(castDisplays)

        await mergeCachedEpisodesIfNeeded(from: record, rootDirectory: root)
    }

    @MainActor
    private func mergeCachedEpisodesIfNeeded(from record: MetadataCacheRecord, rootDirectory: URL) async {
        guard item.mediaType == .tvShow, !record.episodes.isEmpty else { return }

        let cachedByID = Dictionary(uniqueKeysWithValues: record.episodes.map { ($0.id, $0) })

        if episodes.isEmpty {
            episodes = record.episodes.map { $0.makeEpisodeInfo(rootDirectory: rootDirectory) }
            return
        }

        episodes = episodes.map { episode in
            guard let cached = cachedByID[episode.id] else { return episode }
            let cachedEpisode = cached.makeEpisodeInfo(rootDirectory: rootDirectory)
            guard episode.backdropURL == nil, let backdropURL = cachedEpisode.backdropURL else {
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
                backdropURL: backdropURL
            )
        }
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
        let overview = enrichedItem?.overview ?? item.overview
        guard let overview, !overview.isEmpty else { return nil }
        return overview
    }

    private var displayPosterURL: URL? {
        highResolutionPosterURL(from: item.posterURL)
    }

    private var displayGenres: [String] {
        if let enrichedGenres = enrichedItem?.genres, !enrichedGenres.isEmpty {
            return enrichedGenres
        }
        return item.genres
    }

    private var displayDirector: String? {
        if let director = enrichedItem?.director, !director.isEmpty {
            return director
        }
        return item.director
    }

    private var displayCast: [String] {
        if let cast = enrichedItem?.cast, !cast.isEmpty {
            return cast
        }
        return item.cast
    }

    private var shouldEnrichFromServer: Bool {
        guard enrichedItem == nil,
              let serverId = item.serverId,
              !serverId.isEmpty,
              item.sourceConnectionId == nil,
              needsServerDetailFields,
              isEmbyOriginItem,
              EmbyCredentialStore.baseURL != nil,
              EmbyCredentialStore.userId != nil,
              EmbyCredentialStore.token != nil else {
            return false
        }
        return true
    }

    private var isEmbyOriginItem: Bool {
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

    private var needsServerDetailFields: Bool {
        item.overview == nil ||
            item.overview?.isEmpty == true ||
            item.cast.isEmpty ||
            item.director == nil ||
            item.genres.isEmpty ||
            item.backdropURL == nil
    }

    private func enrichItemDetailIfNeeded() async {
        guard shouldEnrichFromServer, let serverId = item.serverId else { return }

        do {
            enrichedItem = try await EmbyItemDetailFetcher.fetchDetail(itemId: serverId)
        } catch {
            VanmoLogger.library.error("[MediaDetail] Failed to enrich item detail: \(error.localizedDescription)")
        }
    }

    private func setFavorite(_ isFavorite: Bool) async {
        guard !isUpdatingFavorite else { return }

        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }

        do {
            try await EmbyFavoriteUpdater.setFavorite(item, isFavorite: isFavorite)
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

        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { mediaItem in
                mediaItem.serverId == serverId
            }
        )
        if let storedItem = try modelContext.fetch(descriptor).first {
            storedItem.isFavorite = isFavorite
        }
    }

    private var seasonNumbers: [Int] {
        Array(Set(episodes.map(\.seasonNumber))).sorted()
    }

    private var currentSeasonEpisodes: [EpisodeInfo] {
        let season = selectedSeason ?? seasonNumbers.first ?? 1
        return episodes
            .filter { $0.seasonNumber == season }
            .sorted { $0.episodeNumber < $1.episodeNumber }
    }

    private var nextEpisodeToPlay: EpisodeInfo? {
        episodes.sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }.first
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
        appState.play(episodeItem)
    }

    private func loadEpisodes() async {
        guard let seriesServerId = item.serverId else { return }

        isLoadingEpisodes = true
        defer { isLoadingEpisodes = false }

        do {
            switch item.fileURL.host {
            case "plex-series":
                episodes = try await PlexEpisodeFetcher.fetchEpisodes(seriesRatingKey: seriesServerId)
            default:
                episodes = try await EmbyEpisodeFetcher.fetchEpisodes(seriesId: seriesServerId)
            }
            await mergeEpisodeBackdropsFromCache()
        } catch {
            VanmoLogger.library.error("[MediaServer] Failed to load episodes: \(error.localizedDescription)")
            episodes = []
        }
    }

    @MainActor
    private func mergeEpisodeBackdropsFromCache() async {
        let key = MetadataCacheKey.from(item)
        guard let record = await MetadataCache.shared.load(for: key),
              !record.episodes.isEmpty else { return }

        let root = (try? await MetadataCache.shared.rootDirectoryURL()) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let cachedByID = Dictionary(uniqueKeysWithValues: record.episodes.map { ($0.id, $0) })

        episodes = episodes.map { episode in
            guard episode.backdropURL == nil, let cached = cachedByID[episode.id] else {
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
                backdropURL: cached.makeEpisodeInfo(rootDirectory: root).backdropURL
            )
        }
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

@MainActor
private final class MediaDetailRatingStore: ObservableObject {
    @Published private(set) var rating: Double?

    func updateRating(_ newRating: Double?) {
        guard rating != newRating else { return }
        rating = newRating
    }
}

@MainActor
private final class MediaDetailRefreshStore: ObservableObject {
    @Published private(set) var isRefreshingMetadata = false
    @Published var refreshErrorMessage: String?

    func beginRefreshing() {
        guard !isRefreshingMetadata else { return }
        isRefreshingMetadata = true
    }

    func finishRefreshing() {
        guard isRefreshingMetadata else { return }
        isRefreshingMetadata = false
    }

    func failRefreshing(_ message: String) {
        refreshErrorMessage = message
    }
}

@MainActor
private final class MediaDetailCastStore: ObservableObject {
    @Published private(set) var members: [CastMemberDisplay] = []

    func update(_ newMembers: [CastMemberDisplay]) {
        guard members != newMembers else { return }
        members = newMembers
    }
}

private struct MediaDetailRefreshErrorPresenter: ViewModifier {
    @ObservedObject var store: MediaDetailRefreshStore

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

private struct MediaDetailPanelHeader: View {
    let title: String
    let logoURL: URL?
    let metaItems: [String]
    @ObservedObject var store: MediaDetailRatingStore
    let starYellow: Color

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            MediaTitleLogoView(
                title: title,
                logoURL: logoURL,
                maxLogoHeight: 72
            )

            if !metaItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(metaItems.enumerated()), id: \.offset) { index, value in
                        if index > 0 {
                            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                        }
                        Text(value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 6) {
                tagView("TV-MA")
                tagView("4K")
                tagView("DOLBY")
            }

            if let rating = store.rating {
                ratingRow(rating)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func ratingRow(_ rating: Double) -> some View {
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

private struct MediaDetailPanelActions: View {
    let accentBlue: Color
    @ObservedObject var store: MediaDetailRefreshStore
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
                    .disabled(store.isRefreshingMetadata)
                }
            } label: {
                circleActionLabel(icon: "ellipsis")
            }
            .disabled(store.isRefreshingMetadata || !supportsMetadataRefresh)
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
    @ObservedObject var store: MediaDetailCastStore
    let fallbackNames: [String]

    private var members: [CastMemberDisplay] {
        if !store.members.isEmpty {
            return store.members
        }
        return fallbackNames.map { name in
            CastMemberDisplay(id: name, name: name, role: nil, profileURL: nil)
        }
    }

    var body: some View {
        let members = members

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
