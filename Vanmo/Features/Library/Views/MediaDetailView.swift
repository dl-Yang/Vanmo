import SwiftUI
import SwiftData
import Kingfisher

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
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

    /// 面板的三种形态：收起（不可见）/ 展开（固定 3/4 屏高）
    private enum PanelState { case collapsed, expanded }
    @State private var panelState: PanelState = .collapsed
    /// 拖拽过程中实时的手势位移
    @State private var dragOffset: CGFloat = 0

    /// 媒体信息布局占屏高比例（不超过 3/4）
    private let panelHeightRatio: CGFloat = 0.75

    private let accentBlue = Color(red: 21/255, green: 93/255, blue: 252/255)
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
        .task {
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
        .alert("收藏失败", isPresented: favoriteErrorBinding) {
            Button("确定") {}
        } message: {
            Text(favoriteErrorMessage ?? "")
        }
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
                    .init(color: Color.black.opacity(0.55), location: 0.0),
                    .init(color: Color.black.opacity(0.15), location: 0.45),
                    .init(color: Color.black.opacity(0.85), location: 1.0)
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
                Text((item.mediaType == .tvShow ? (item.showTitle ?? item.title) : item.displayTitle).uppercased())
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .kerning(-0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

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

    /// 媒体信息布局的毛玻璃背景（顶部圆角矩形 + 暗色玻璃质感 + 顶部高光边）
    private var panelGlassBackground: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
        let isDark = colorScheme == .dark
        let bgColor = isDark ? Color(red: 9/255, green: 9/255, blue: 11/255).opacity(0.6) : Color.white.opacity(0.6)
        let borderColor = isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.2)
        let shadowColor = isDark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
        
        return shape
            .fill(bgColor)
            .background(.ultraThinMaterial, in: shape)
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
        VStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            
            if !collapsedMetaItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(collapsedMetaItems.enumerated()), id: \.offset) { index, value in
                        if index > 0 {
                            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                        }
                        Text(value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Tags like [TV-MA] [4K] [DOLBY] can be added here if model supports them in the future
            HStack(spacing: 6) {
                tagView("TV-MA")
                tagView("4K")
                tagView("DOLBY")
            }

            if let rating = item.rating {
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
            }
        }
        .frame(maxWidth: .infinity)
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
            circleAction(icon: "ellipsis") {}
        }
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
        if !displayCast.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text("主演")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(displayCast, id: \.self) { name in
                            castAvatar(name)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.horizontal, -24)
            }
        }
    }

    private func castAvatar(_ name: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                Text(initial(for: name))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, height: 80)

            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 80)
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
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.secondarySystemBackground))
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.15), in: Circle())
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

    // MARK: - 状态逻辑

    private var favoriteButton: some View {
        Button {
            Task { await setFavorite(!item.isFavorite) }
        } label: {
            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.isFavorite ? .red : .white.opacity(0.95))
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFavorite)
        .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")
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
        } catch {
            VanmoLogger.library.error("[MediaServer] Failed to load episodes: \(error.localizedDescription)")
            episodes = []
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
