import SwiftUI
import SwiftData
import Kingfisher

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem

    @State private var showAllCast = false
    @State private var dominantColor: Color = .black.opacity(0.0)
    @State private var accentColor: Color = Color(hue: 0, saturation: 0.05, brightness: 0.88)
    @State private var scrollOffset: CGFloat = 0
    @State private var headerGlobalMinY: CGFloat = 0
    @State private var heroRestMinY: CGFloat?
    @State private var episodes: [EpisodeInfo] = []
    @State private var isLoadingEpisodes = false
    @State private var selectedSeason: Int?

    private let heroHeight: CGFloat = 540
    private let backdropHeight: CGFloat = 300

    /// 合并下拉（named 坐标探针）与上滑（global 坐标 header）的滚动增量。
    private var heroScrollDelta: CGFloat {
        let pullDown = max(scrollOffset, 0)
        guard let rest = heroRestMinY else { return pullDown }
        let headerDelta = headerGlobalMinY - rest
        if headerDelta < 0 { return headerDelta }
        return max(pullDown, headerDelta)
    }

    var body: some View {
        ZStack(alignment: .top) {
            stretchyBackdropLayer
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        let minY = proxy.frame(in: .named("detailScroll")).minY
                        Color.clear
                            .onChange(of: minY) { _, newValue in
                                scrollOffset = newValue
                            }
                    }
                    .frame(height: 0)

                    headerForeground

                    VStack(alignment: .leading, spacing: 24) {
                        infoSection

                        if item.mediaType == .tvShow {
                            episodeSection
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .coordinateSpace(name: "detailScroll")
        }
        .background(detailBackground)
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
            async let dominant = DominantColorExtractor.cachedColor(for: item.posterURL)
            async let accent = DominantColorExtractor.cachedAccentColor(for: item.posterURL)
            let (d, a) = await (dominant, accent)
            dominantColor = d
            accentColor = a
        }
        .task {
            if item.mediaType == .tvShow {
                await loadEpisodes()
            }
        }
    }

    private var detailBackground: some View {
        Color.vanmoBackground
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [
                        dominantColor.opacity(0.28),
                        Color.vanmoBackground.opacity(0.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: backdropHeight)
                .ignoresSafeArea()
            }
    }

    private var stretchyBackdropLayer: some View {
        GeometryReader { geometry in
            let delta = heroScrollDelta
            let extra = max(delta, 0)
            let yOffset = min(delta, 0)
            let opacity = max(0, min(1, 1 + (delta / 180)))

            heroBackdrop(width: geometry.size.width, height: backdropHeight + extra)
                .frame(width: geometry.size.width, height: backdropHeight + extra, alignment: .top)
                .offset(y: yOffset)
                .opacity(opacity)
        }
        .frame(height: backdropHeight, alignment: .top)
    }

    private var favoriteButton: some View {
        Button {
            item.isFavorite.toggle()
            try? modelContext.save()
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
        .accessibilityLabel(item.isFavorite ? "取消收藏" : "收藏")
    }

    // MARK: - Header

    private var headerForeground: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 16) {
                heroPoster

                mediaInfoOverlay
                    .layoutPriority(1)
            }

            playButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .frame(height: heroHeight)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        let minY = proxy.frame(in: .global).minY
                        headerGlobalMinY = minY
                        if heroRestMinY == nil {
                            heroRestMinY = minY
                        }
                    }
                    .onChange(of: proxy.frame(in: .global).minY) { _, newValue in
                        headerGlobalMinY = newValue
                        if heroRestMinY == nil {
                            heroRestMinY = newValue
                        }
                    }
            }
        }
    }

    private func heroBackdrop(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        ZStack {
            dominantColor

            heroBackdropImage(width: width, height: height)

            LinearGradient(
                colors: [
                    .black.opacity(0.22),
                    .black.opacity(0.38),
                    .black.opacity(0.88),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    .black.opacity(0.54),
                    .clear,
                    .black.opacity(0.34),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            VStack{
                Spacer()
                LinearGradient(
                    colors: [
                        .clear,
                        Color.vanmoBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ).frame(height:300)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func heroBackdropImage(
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        if let backdropURL = item.backdropURL {
            KFImage(backdropURL)
                .placeholder {
                    Rectangle()
                        .fill(dominantColor)
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: width)
                .frame(width: width, height: height, alignment: .top)
                .clipped()
        } else {
            KFImage(item.posterURL)
                .placeholder {
                    Rectangle()
                        .fill(dominantColor)
                }
                .fade(duration: 0.25)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .blur(radius: 16)
                .scaleEffect(1.08)
                .clipped()
        }
    }

    private var heroPoster: some View {
        KFImage(item.posterURL)
            .placeholder {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.vanmoSurface)
                    .overlay {
                        Image(systemName: item.mediaType.icon)
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                    }
            }
            .fade(duration: 0.25)
            .resizable()
            .scaledToFill()
            .frame(width: 122, height: 183)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.42), radius: 22, x: 0, y: 14)
    }

    private var heroMetaItems: [String] {
        var values: [String] = []
        if let year = item.year {
            values.append("\(year)")
        }
        if item.mediaType == .tvShow, !episodes.isEmpty {
            values.append("\(seasonNumbers.count)季 · \(episodes.count)集")
        } else if item.duration > 0 {
            values.append(item.duration.shortDuration)
        }
        values.append(item.mediaType.displayName)
        return values
    }

    private var mediaInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .shadow(color: .black.opacity(0.55), radius: 8, y: 3)

            Text(heroMetaItems.joined(separator: "  ·  "))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)

            HStack(spacing: 8) {
                if let rating = item.rating {
                    RatingBadge(rating)
                }

                MediaDetailPill(
                    text: item.mediaType.displayName,
                    icon: item.mediaType.icon,
                    tint: .white
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack(spacing: 8) {
                if isLoadingEpisodes {
                    ProgressView()
                        .tint(playButtonForeground)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(playButtonTitle)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(accentColor)
            .foregroundStyle(playButtonForeground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
        }
        .disabled(item.mediaType == .tvShow && episodes.isEmpty)
        .shadow(color: accentColor.opacity(0.28), radius: 18, x: 0, y: 10)
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
    }

    /// 按钮前景色根据按钮背景亮度自适应：浅色背景用深色字，深色背景用白字。
    private var playButtonForeground: Color {
        DominantColorExtractor.relativeLuminance(of: accentColor) > 0.55
            ? Color.black.opacity(0.85)
            : .white
    }

    private var playButtonTitle: String {
        if item.mediaType == .tvShow {
            if isLoadingEpisodes { return "加载中..." }
            if let ep = nextEpisodeToPlay {
                return "播放 S\(String(format: "%02d", ep.seasonNumber))E\(String(format: "%02d", ep.episodeNumber))"
            }
            return "播放"
        }
        return item.lastPlaybackPosition > 0 ? "继续播放" : "播放"
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

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.vanmoPrimary)
                    .frame(width: 26, height: 26)
                    .background(Color.vanmoPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text("剧集")
                    .font(.headline)

                Spacer()

                if !episodes.isEmpty {
                    Text("\(episodes.count) 集")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.vanmoBackground, in: Capsule())
                }
            }

            if isLoadingEpisodes {
                HStack(spacing: 10) {
                    ProgressView()

                    Text("加载剧集...")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
            } else if episodes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack.badge.questionmark")
                        .font(.title3)
                        .foregroundStyle(.tertiary)

                    Text("暂无剧集信息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                if seasonNumbers.count > 1 {
                    seasonPicker
                }

                VStack(spacing: 10) {
                    ForEach(currentSeasonEpisodes) { episode in
                        episodeRow(episode)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.vanmoSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 20)
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seasonNumbers, id: \.self) { season in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedSeason = season
                        }
                    } label: {
                        Text("第 \(season) 季")
                            .font(.subheadline)
                            .fontWeight((selectedSeason ?? seasonNumbers.first) == season ? .semibold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                (selectedSeason ?? seasonNumbers.first) == season
                                    ? Color.vanmoPrimary.opacity(0.16)
                                    : Color.vanmoBackground
                            )
                            .foregroundStyle(
                                (selectedSeason ?? seasonNumbers.first) == season
                                    ? Color.vanmoPrimary
                                    : .secondary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func episodeRow(_ episode: EpisodeInfo) -> some View {
        Button {
            playEpisode(episode)
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("E\(String(format: "%02d", episode.episodeNumber))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.vanmoPrimary)

                    Text("S\(String(format: "%02d", episode.seasonNumber))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 46, height: 46)
                .background(Color.vanmoPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title.isEmpty ? "第 \(episode.episodeNumber) 集" : episode.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if episode.duration > 0 {
                        Text(episode.duration.shortDuration)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(playButtonForeground)
                    .frame(width: 32, height: 32)
                    .background(accentColor, in: Circle())
            }
            .padding(12)
            .background(Color.vanmoBackground, in: RoundedRectangle(cornerRadius: 14))
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

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let overview = item.overview, !overview.isEmpty {
                detailSection(title: "简介", icon: "text.alignleft") {
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !item.genres.isEmpty {
                detailSection(title: "类型", icon: "tag") {
                    genreTags
                }
            }

            if item.director != nil || !item.cast.isEmpty {
                creditsSection
            }

            if item.mediaType != .tvShow {
                fileInfoSection
            }

            if !item.audioTracks.isEmpty || !item.subtitleTracks.isEmpty {
                trackInfoSection
            }
        }
        .padding(.horizontal, 20)
    }

    private var genreTags: some View {
        FlowLayout(spacing: 8) {
            ForEach(item.genres, id: \.self) { genre in
                MediaDetailPill(text: genre, icon: nil, tint: Color.vanmoPrimary)
            }
        }
    }

    private var creditsSection: some View {
        detailSection(title: "演职员", icon: "person.2") {
            VStack(alignment: .leading, spacing: 12) {
                if let director = item.director {
                    infoRow("导演", value: director)
                }

                if !item.cast.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(
                            "演员",
                            value: item.cast.prefix(showAllCast ? item.cast.count : 5).joined(separator: "、")
                        )

                        if item.cast.count > 5 {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAllCast.toggle()
                                }
                            } label: {
                                Text(showAllCast ? "收起" : "显示全部")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.vanmoPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var fileInfoSection: some View {
        detailSection(title: "文件信息", icon: "doc.text.magnifyingglass") {
            VStack(spacing: 10) {
                if let fileName = displayFileName {
                    infoRow("文件名", value: fileName)
                }
                if item.fileSize > 0 {
                    infoRow("大小", value: item.fileSize.formattedFileSize)
                }
                if item.duration > 0 {
                    infoRow("时长", value: item.duration.formattedDuration)
                }
                if let format = displayFormat {
                    infoRow("格式", value: format)
                }
            }
        }
    }

    /// 文件名优先取持久化的原始文件名；远程流式 URL 没有可读文件名时返回 nil。
    private var displayFileName: String? {
        if let name = item.originalFileName, !name.isEmpty { return name }
        if item.fileURL.isFileURL {
            let last = item.fileURL.lastPathComponent
            return last.isEmpty ? nil : last
        }
        return nil
    }

    /// 容器格式优先取持久化字段；本地文件回退到扩展名。
    private var displayFormat: String? {
        if let container = item.container, !container.isEmpty {
            return container.uppercased()
        }
        let ext = item.fileURL.pathExtension
        return ext.isEmpty ? nil : ext.uppercased()
    }

    private var trackInfoSection: some View {
        detailSection(title: "轨道信息", icon: "waveform") {
            VStack(spacing: 10) {
                ForEach(item.audioTracks) { track in
                    infoRow("音频 \(track.id + 1)", value: track.displayName)
                }

                ForEach(item.subtitleTracks) { track in
                    infoRow("字幕 \(track.id + 1)", value: track.displayName)
                }
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.vanmoPrimary)
                    .frame(width: 24, height: 24)
                    .background(Color.vanmoPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vanmoSurface.opacity(0.86), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MediaDetailPill: View {
    let text: String
    let icon: String?
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .fontWeight(.semibold)
            }

            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(tint.opacity(0.12), lineWidth: 1)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                subview.place(
                    at: CGPoint(
                        x: bounds.minX + result.positions[index].x,
                        y: bounds.minY + result.positions[index].y
                    ),
                    proposal: .unspecified
                )
            }
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
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
