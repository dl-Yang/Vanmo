import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct ScannedShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let connection: SavedConnection
    let showTitle: String
    let parentDirectory: String

    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            CatAmberHalo(width: 180, height: 70, opacity: 0.22)
                .padding(.top, 12)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                stateContent
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .task(id: taskID) {
            loadEpisodes()
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            CatBackButton { dismiss() }

            VStack(alignment: .leading, spacing: 1) {
                Text(showTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text("\(connection.name) · \(L10n.tr("%d 集", episodes.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            CatStretchingDivider()
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var stateContent: some View {
        if isLoading {
            ScannedShowLoadingView()
        } else if let errorMessage {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: L10n.tr("无法加载分集"),
                message: errorMessage
            )
        } else if episodes.isEmpty {
            EmptyStateView(
                icon: "tv",
                title: L10n.tr("暂无分集"),
                message: L10n.tr("此剧集下没有可显示的分集")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(episodes) { episode in
                        Button {
                            appState.play(episode)
                        } label: {
                            ScannedEpisodeRowCard(episode: episode)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.bottom, 28)
            }
        }
    }

    private var taskID: String {
        "\(connection.id.uuidString)-\(parentDirectory)-\(showTitle)"
    }

    private func loadEpisodes() {
        if !hasLoadedOnce {
            isLoading = true
        }
        errorMessage = nil

        do {
            let descriptor = FetchDescriptor<MediaItem>(
                sortBy: [
                    SortDescriptor(\.seasonNumber),
                    SortDescriptor(\.episodeNumber),
                    SortDescriptor(\.title),
                ]
            )
            episodes = ScannedShowGrouping.episodes(
                from: try modelContext.fetch(descriptor),
                connectionId: connection.id,
                showTitle: showTitle,
                parentDirectory: parentDirectory
            )
            hasLoadedOnce = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct ScannedEpisodeRowCard: View {
    let episode: MediaItem

    private var badgeText: String {
        if let ep = episode.episodeNumber {
            return String(format: "E%02d", ep)
        }
        return L10n.tr("分集")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                KFImage(episode.backdropURL ?? episode.posterURL)
                    .placeholder {
                        ZStack {
                            CatDesign.mediaPlaceholder
                            Image(systemName: "play.rectangle")
                                .foregroundStyle(CatDesign.textMuted.opacity(0.45))
                        }
                    }
                    .fade(duration: 0.2)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 112, height: 64)
                    .clipped()

                Text(badgeText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(CatDesign.Cinema.textIvory)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
                    .padding(5)
            }
            .frame(width: 112, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(episode.episodeTitle ?? episode.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                if episode.duration > 0 {
                    Text(episode.duration.shortDuration)
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                }

                if episode.playbackProgress > 0, !episode.isWatched {
                    CatPawProgressBar(progress: episode.playbackProgress, showPawDot: false)
                }
            }

            Spacer(minLength: 4)

            if episode.isWatched {
                CatSleepingPillBadge()
            } else {
                Image("CatPlaySmall")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .padding(7)
                    .background(CatDesign.amberTintFill, in: Circle())
                    .overlay(Circle().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.8))
            }
        }
        .padding(10)
        .catGlassCard(cornerRadius: 16)
    }
}

private struct ScannedShowLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(CatDesign.surfacePill)
                    .frame(height: 84)
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .redacted(reason: .placeholder)
    }
}

#Preview {
    NavigationStack {
        ScannedShowDetailView(
            connection: SavedConnection(
                name: "NAS",
                type: .smb,
                host: "192.168.1.2",
                port: 445
            ),
            showTitle: "示例剧集",
            parentDirectory: "/TV/示例剧集"
        )
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
