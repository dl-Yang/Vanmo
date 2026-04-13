import SwiftUI

struct MediaDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem

    @State private var showAllCast = false
    @State private var dominantColor: Color = .black.opacity(0.0)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerSection

                LinearGradient(
                    colors: [dominantColor, Color.vanmoBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                .animation(.easeInOut(duration: 0.6), value: dominantColor)

                infoSection
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    item.isFavorite.toggle()
                    try? modelContext.save()
                } label: {
                    Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(item.isFavorite ? .red : .white)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            dominantColorBackground
            posterLayer
            mediaInfoOverlay
        }
        .frame(height: 520)
        .clipped()
        .task {
            dominantColor = await DominantColorExtractor.cachedColor(
                for: item.posterURL
            )
        }
    }

    // MARK: - Layer 0: Dominant Color Background

    private var dominantColorBackground: some View {
        ZStack {
            dominantColor
                .ignoresSafeArea()

            RadialGradient(
                colors: [dominantColor, dominantColor.opacity(0.7)],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.6), value: dominantColor)
    }

    // MARK: - Layer 1: Poster + Edge Fade

    private var posterLayer: some View {
        ZStack {
            AsyncImage(url: item.posterURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    Rectangle().fill(Color.vanmoSurface)
                        .overlay {
                            Image(systemName: "film")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(maxWidth: 240)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            .mask(posterEdgeFadeMask)
            .padding(.bottom, 100)

            LinearGradient(
                colors: [.clear, dominantColor],
                startPoint: .init(x: 0.5, y: 0.6),
                endPoint: .bottom
            )
            .animation(.easeInOut(duration: 0.6), value: dominantColor)
        }
    }

    private var posterEdgeFadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .white],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)

            Rectangle().fill(.white)

            LinearGradient(
                colors: [.white, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 80)
        }
    }

    // MARK: - Layer 2: Media Info Overlay

    private var mediaInfoOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer()

            Text(item.title)
                .font(.title2.bold())
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

            HStack(spacing: 8) {
                if let year = item.year {
                    Text("\(year)")
                }
                if item.duration > 0 {
                    Text(item.duration.shortDuration)
                }
                Text(item.mediaType.displayName)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let rating = item.rating {
                RatingBadge(rating)
            }

            playButton
        }
        .padding()
    }

    private var playButton: some View {
        Button {
            appState.play(item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text(item.lastPlaybackPosition > 0 ? "继续播放" : "播放")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.vanmoPrimary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let overview = item.overview, !overview.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("简介")
                        .font(.headline)
                    Text(overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            if !item.genres.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("类型")
                        .font(.headline)
                    genreTags
                }
            }

            if let director = item.director {
                VStack(alignment: .leading, spacing: 4) {
                    Text("导演")
                        .font(.headline)
                    Text(director)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !item.cast.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("演员")
                        .font(.headline)
                    Text(item.cast.prefix(showAllCast ? item.cast.count : 5).joined(separator: "、"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if item.cast.count > 5 {
                        Button(showAllCast ? "收起" : "显示全部") {
                            withAnimation { showAllCast.toggle() }
                        }
                        .font(.caption)
                    }
                }
            }

            fileInfoSection

            if !item.audioTracks.isEmpty || !item.subtitleTracks.isEmpty {
                trackInfoSection
            }
        }
        .padding()
    }

    private var genreTags: some View {
        FlowLayout(spacing: 8) {
            ForEach(item.genres, id: \.self) { genre in
                Text(genre)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.vanmoSurface)
                    .clipShape(Capsule())
            }
        }
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("文件信息")
                .font(.headline)

            VStack(spacing: 6) {
                infoRow("文件名", value: item.fileURL.lastPathComponent)
                infoRow("大小", value: item.fileSize.formattedFileSize)
                infoRow("时长", value: item.duration.formattedDuration)
                infoRow("格式", value: item.fileURL.pathExtension.uppercased())
            }
        }
    }

    private var trackInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("轨道信息")
                .font(.headline)

            ForEach(item.audioTracks) { track in
                infoRow("音频 \(track.id + 1)", value: track.displayName)
            }

            ForEach(item.subtitleTracks) { track in
                infoRow("字幕 \(track.id + 1)", value: track.displayName)
            }
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
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
