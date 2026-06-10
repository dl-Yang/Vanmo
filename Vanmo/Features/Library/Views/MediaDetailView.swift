import SwiftUI
import SwiftData
import Kingfisher

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
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

    private let heroViewportHeight: CGFloat = 500

    var body: some View {
        ZStack {
            fixedPosterBackground
                .allowsHitTesting(false)

            ScrollView {
                foregroundContent
                    .containerRelativeFrame(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                favoriteButton
            }
        }
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

    private var fixedPosterBackground: some View {
        GeometryReader { proxy in
            ZStack {
                dominantColor

                heroBackdropImage(width: proxy.size.width, height: proxy.size.height)

//                LinearGradient(
//                    colors: [
//                        .black.opacity(0.72),
//                        .black.opacity(0.24),
//                        .black.opacity(0.56),
//                        .black.opacity(0.94),
//                    ],
//                    startPoint: .top,
//                    endPoint: .bottom
//                )
//
//                LinearGradient(
//                    colors: [
//                        .black.opacity(0.34),
//                        .clear,
//                        dominantColor.opacity(0.34),
//                    ],
//                    startPoint: .leading,
//                    endPoint: .trailing
//                )
            }
        }
        .ignoresSafeArea()
    }

    private var favoriteButton: some View {
        Button {
            Task {
                await setFavorite(!item.isFavorite)
            }
        } label: {
            Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.isFavorite ? .red : .white)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFavorite)
        .opacity(activeSheet == nil ? 1 : 0)
        .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")
    }

    private var favoriteErrorBinding: Binding<Bool> {
        Binding {
            favoriteErrorMessage != nil
        } set: { isPresented in
            if !isPresented {
                favoriteErrorMessage = nil
            }
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

    /// 判断条目是否来自当前 Emby/Jellyfin 服务器：
    /// 电影/分集的流地址 host 即服务器域名；电视剧/容器使用 `vanmo://series|emby-container|emby-item`。
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

    // MARK: - Header

    private var foregroundContent: some View {
        VStack(spacing: 0) {
            heroHeader

            VStack(spacing: 14) {
                playButton

                if item.mediaType == .tvShow {
                    currentEpisodeProgress
                }

                buttonActionList

                if item.mediaType == .tvShow {
                    episodeBrowser
                    synopsisSection(title: "本集简介")
                    castSection(title: "演职人员")
                } else {
                    synopsisSection(title: "简介")
                    castSection(title: "演职人员")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, item.mediaType == .tvShow ? 44 : 34)
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.displayTitle)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .kerning(-0.72)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .shadow(color: .black.opacity(0.62), radius: 10, y: 4)

                    Text(heroMetaItems.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                directorAvatar
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 96)
        .frame(height: heroViewportHeight, alignment: .top)
    }

    private var directorAvatar: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 128 / 255, green: 219 / 255, blue: 1.0),
                                Color(red: 1.0, green: 140 / 255, blue: 97 / 255),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.54), lineWidth: 1)
                    }

                Text(directorInitial)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                Text(directorDisplayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.mediaType == .tvShow ? "主创" : "导演")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .frame(width: 128, height: 60)
        .liquidGlass(cornerRadius: 28)
    }

    @ViewBuilder
    private func heroBackdropImage(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
            // 首屏：复用列表已缓存的低质量小图并加模糊，减少等待时间
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

            // 高质量大图加载完成后切换为清晰背景，去掉模糊效果
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

    private var heroMetaItems: [String] {
        var values: [String] = []
        if item.mediaType == .tvShow, !episodes.isEmpty {
            values.append("\(seasonNumbers.count)季 · \(episodes.count)集")
            if !displayGenres.isEmpty {
                values.append(displayGenres.prefix(2).joined(separator: " / "))
            }
        } else {
            if let year = item.year {
                values.append("\(year)")
            }
            if let genre = displayGenres.first {
                values.append(genre)
            }
            if item.duration > 0 {
                values.append(item.duration.shortDuration)
            }
        }
        return values
    }

    private var playButton: some View {
        Button {
            if item.mediaType == .tvShow {
                if let ep = nextEpisodeToPlay {
                    playEpisode(ep)
                }
            } else {
                appState.play(item)
            }
        } label: {
            ZStack {
                if isLoadingEpisodes {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 82, height: 82)
            .liquidGlass(cornerRadius: 41, opacity: 0.30)
        }
        .disabled(item.mediaType == .tvShow && episodes.isEmpty)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Episodes

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

    @ViewBuilder
    private var currentEpisodeProgress: some View {
        if item.mediaType == .tvShow {
            Text(currentEpisodeProgressText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .frame(height: 38)
                .liquidGlass(cornerRadius: 19, opacity: 0.16)
                .frame(maxWidth: .infinity)
        }
    }

    private var currentEpisodeProgressText: String {
        if isLoadingEpisodes {
            return "正在加载剧集"
        } else if let ep = nextEpisodeToPlay {
            return "继续观看 · S\(ep.seasonNumber) E\(episodeCode(ep.episodeNumber)) · \(tvProgressText)"
        } else {
            return "暂无可播放剧集"
        }
    }

    private var episodeBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("剧集")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize()

                if !episodes.isEmpty, seasonNumbers.count > 1 {
                    seasonPicker
                } else {
                    Spacer(minLength: 0)
                }

                if !episodes.isEmpty {
                    Button {
                        activeSheet = .episodes
                    } label: {
                        Text("全部剧集 ›")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }

            if isLoadingEpisodes {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.white)

                    Text("加载剧集...")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .frame(maxWidth: .infinity, minHeight: 72)
            } else if episodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(.tertiary)

                    Text("暂无剧集信息")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                }
                .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(currentSeasonEpisodes.prefix(8)) { episode in
                            episodeCard(episode)
                        }
                    }
                    .padding(.horizontal, 1)
                    .padding(.bottom, 2)
                }
                .scrollClipDisabled()
            }
        }
        .padding(18)
        .liquidGlass(cornerRadius: 30, opacity: 0.16)
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seasonNumbers, id: \.self) { season in
                    seasonPill(season)
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private func seasonPill(_ season: Int) -> some View {
        let isSelected = (selectedSeason ?? seasonNumbers.first) == season
        return Button {
            withAnimation(.spring(response: 0.3)) {
                selectedSeason = season
            }
        } label: {
            Text("第 \(season) 季")
                .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.7))
                .padding(.horizontal, 14)
                .frame(height: 24)
                .background(.white.opacity(isSelected ? 0.26 : 0.14), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private func episodeCard(_ episode: EpisodeInfo) -> some View {
        let isCurrent = episode.id == nextEpisodeToPlay?.id
        return Button {
            playEpisode(episode)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(episodeThumbnailGradient(isCurrent: isCurrent))
                    .frame(width: 80, height: 48)

                HStack(spacing: 4) {
                    Text("E\(episodeCode(episode.episodeNumber))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))

                    Text(episode.title.isEmpty ? "第 \(episode.episodeNumber) 集" : episode.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .padding(.top, 9)

                if isCurrent {
                    Capsule()
                        .fill(.white.opacity(0.75))
                        .frame(width: 64, height: 3)
                        .padding(.top, 7)
                }

                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(width: 98, height: 96, alignment: .topLeading)
            .liquidGlass(cornerRadius: 24, opacity: isCurrent ? 0.24 : 0.15)
        }
        .buttonStyle(.plain)
    }

    private func episodeThumbnailGradient(isCurrent: Bool) -> LinearGradient {
        let colors: [Color] = isCurrent
            ? [Color(red: 123 / 255, green: 185 / 255, blue: 1.0),
               Color(red: 1.0, green: 143 / 255, blue: 106 / 255)]
            : [Color(red: 70 / 255, green: 90 / 255, blue: 112 / 255),
               Color(red: 26 / 255, green: 32 / 255, blue: 42 / 255)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func episodeRow(_ episode: EpisodeInfo) -> some View {
        Button {
            playEpisode(episode)
        } label: {
            HStack(spacing: 14) {
                Text("E\(episodeCode(episode.episodeNumber))")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .liquidGlass(cornerRadius: 14, opacity: 0.1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title.isEmpty ? "第 \(episode.episodeNumber) 集" : episode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if episode.duration > 0 {
                        Text(episode.duration.shortDuration)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .padding(12)
            .liquidGlass(cornerRadius: 18, opacity: 0.08)
        }
        .buttonStyle(.plain)
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
            // 按 streamURL host 区分 series 来源:
            // - "plex-series" → Plex Media Server
            // - 其他（包括 "series" 或缺失）→ Emby/Jellyfin（共享 fetcher）
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

    // MARK: - Info

    private var buttonActionList: some View {
        HStack(spacing: 8) {
            detailActionButton(
                title: "收藏",
                subtitle: "收藏",
                icon: item.isFavorite ? "heart.fill" : "heart",
                isActive: item.isFavorite
            ) {
                Task {
                    await setFavorite(!item.isFavorite)
                }
            }

            detailActionButton(title: "播放列表", subtitle: "片单", icon: "plus") {}

            detailActionButton(
                title: "评分",
                subtitle: item.rating.map { String(format: "%.1f", $0) } ?? "评分",
                icon: "star.fill"
            ) {}
        }
    }

    private func detailActionButton(
        title: String,
        subtitle: String,
        icon: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isActive ? Color.red.opacity(0.95) : .white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.36), lineWidth: 1)
                    }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.40))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 100)
            .liquidGlass(cornerRadius: 24, opacity: 0.14)
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingFavorite && title == "收藏")
    }

    private func synopsisSection(title: String) -> some View {
        let isTV = item.mediaType == .tvShow
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: isTV ? 16 : 15, weight: .bold))
                .foregroundStyle(.white)

            HStack(alignment: .bottom, spacing: 10) {
                Text(displayOverview ?? "暂无简介")
                    .font(.system(size: isTV ? 12 : 11))
                    .lineSpacing(isTV ? 5 : 3)
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(isTV ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if displayOverview != nil {
                    moreButton("查看更多") {
                        activeSheet = .synopsis
                    }
                }
            }
        }
        .padding(isTV ? 19 : 17)
        .liquidGlass(cornerRadius: isTV ? 28 : 24, opacity: 0.16)
    }

    private func castSection(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize()

            if displayCast.isEmpty {
                Spacer(minLength: 0)
                Text("暂无演职人员信息")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                HStack(spacing: 22) {
                    ForEach(Array(displayCast.prefix(3).enumerated()), id: \.offset) { _, name in
                        castAvatarCompact(name)
                    }
                }
                Spacer(minLength: 0)
                moreButton(item.mediaType == .tvShow ? "全部" : "查看更多") {
                    activeSheet = .cast
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .padding(.horizontal, 17)
        .liquidGlass(cornerRadius: 24, opacity: 0.15)
    }

    private func castAvatarCompact(_ name: String) -> some View {
        VStack(spacing: 4) {
            castAvatarCircle(name, diameter: 34, initialSize: 14, borderOpacity: 0.38)

            Text(name)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .frame(width: 52)
        }
    }

    private func castAvatarCircle(
        _ name: String,
        diameter: CGFloat,
        initialSize: CGFloat,
        borderOpacity: Double
    ) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            accentColor.opacity(0.94),
                            .orange.opacity(0.78),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(borderOpacity), lineWidth: 1)
                }

            Text(initial(for: name))
                .font(.system(size: initialSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
    }

    private func moreButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.white.opacity(0.16), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(.white.opacity(0.32), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Modal Overlay

    private func modalOverlay(for sheet: MediaDetailSheet) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { activeSheet = nil }
                .transition(.opacity)

            modalCard(for: sheet)
                .padding(.horizontal, 24)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }

    private func modalCard(for sheet: MediaDetailSheet) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.42))
                .frame(width: 66, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 13)

            Text(modalTitle(for: sheet))
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .padding(.top, 20)

            modalBody(for: sheet)
                .padding(.top, 18)
        }
        .padding(.horizontal, 23)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 34, opacity: 0.24)
        .overlay(alignment: .topTrailing) {
            modalCloseButton
                .padding(.top, 29)
                .padding(.trailing, 23)
        }
    }

    private var modalCloseButton: some View {
        Button {
            activeSheet = nil
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .frame(width: 34, height: 34)
                .liquidGlass(cornerRadius: 17, opacity: 0.18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭")
    }

    private func modalTitle(for sheet: MediaDetailSheet) -> String {
        switch sheet {
        case .synopsis:
            return item.mediaType == .tvShow ? "本集简介" : "简介"
        case .cast:
            return "演职人员"
        case .episodes:
            return "全部剧集"
        }
    }

    @ViewBuilder
    private func modalBody(for sheet: MediaDetailSheet) -> some View {
        switch sheet {
        case .synopsis:
            VStack(alignment: .leading, spacing: 18) {
                Text(displayOverview ?? "暂无简介")
                    .font(.system(size: 13))
                    .lineSpacing(8)
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("点击空白处或右上角关闭")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }
        case .cast:
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                spacing: 20
            ) {
                ForEach(displayCast, id: \.self) { name in
                    VStack(spacing: 6) {
                        castAvatarCircle(name, diameter: 42, initialSize: 17, borderOpacity: 0.40)

                        Text(name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(1)
                            .frame(width: 64)
                    }
                }
            }
        case .episodes:
            ScrollView {
                VStack(spacing: 10) {
                    if seasonNumbers.count > 1 {
                        seasonPicker
                    }

                    ForEach(currentSeasonEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 420)
        }
    }

    private var directorDisplayName: String {
        displayDirector ?? (item.mediaType == .tvShow ? "主创" : "导演")
    }

    private var directorInitial: String {
        initial(for: directorDisplayName)
    }

    private var tvProgressText: String {
        let progress = Int(max(min(item.playbackProgress, 1), 0) * 100)
        return progress > 0 ? "已观看 \(progress)%" : "未观看"
    }

    private func episodeCode(_ value: Int) -> String {
        String(format: "%02d", value)
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
}

private enum MediaDetailSheet: Identifiable, Equatable {
    case synopsis
    case cast
    case episodes

    var id: String {
        switch self {
        case .synopsis:
            return "synopsis"
        case .cast:
            return "cast"
        case .episodes:
            return "episodes"
        }
    }
}

private struct LiquidGlassModifier: ViewModifier {
    let cornerRadius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(opacity))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 30, x: 0, y: 14)
            .shadow(color: .white.opacity(0.08), radius: 1, x: 0, y: 1)
    }
}

private extension View {
    func liquidGlass(cornerRadius: CGFloat, opacity: Double = 0.12) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, opacity: opacity))
    }
}

#Preview {
    NavigationStack {
        MediaDetailView(item: MediaItem(
            title: "Inception",
            fileURL: URL(fileURLWithPath: "/test.mkv"),
            mediaType: .movie,
            fileSize: 4_500_000_000,
            duration: 8880
        ))
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
