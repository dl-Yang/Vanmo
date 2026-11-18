import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            ambientHalos

            VStack(spacing: 0) {
                topFloatingSearchBar
                    .padding(.top, 10)

                contentBody
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.search()
        }
        .onChange(of: connectionsViewModel.savedConnections.map(\.id)) { _, _ in
            viewModel.setConnections(connectionsViewModel.savedConnections)
            viewModel.search()
        }
        .task {
            viewModel.setModelContext(modelContext)
            await connectionsViewModel.loadSavedConnections()
            viewModel.setConnections(connectionsViewModel.savedConnections)
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionLocalMediaWillDelete)) { notification in
            guard let connectionId = notification.object as? UUID else { return }
            viewModel.removeResults(forConnectionId: connectionId)
        }
    }

    // MARK: - Ambient Glows

    @ViewBuilder
    private var ambientHalos: some View {
        if viewModel.searchText.isEmpty {
            VStack {
                CatAmberHalo(width: 250, height: 80, opacity: 0.16)
                    .padding(.top, 42)
                Spacer()
                CatAmberHalo(width: 170, height: 90, opacity: 0.22)
                    .padding(.bottom, 128)
            }
            .ignoresSafeArea()
        } else {
            HStack {
                Spacer()
                CatAmberHalo(width: 200, height: 180, opacity: 0.16)
                    .padding(.top, 220)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Top Floating Search Bar (`680:560` / `680:651`)

    private var topFloatingSearchBar: some View {
        HStack(spacing: 10) {
            Image("CatTabSearchActive")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)

            TextField(
                "",
                text: $viewModel.searchText,
                prompt: Text(L10n.tr("搜索电影、剧集、文件...")).foregroundStyle(CatDesign.textMuted)
            )
            .font(.system(size: 13.5, weight: viewModel.searchText.isEmpty ? .regular : .semibold))
            .foregroundStyle(CatDesign.textIvory)
            .submitLabel(.search)
            .focused($isSearchFocused)
            .autocorrectionDisabled()
            .onSubmit {
                viewModel.recordRecentSearch(viewModel.searchText)
            }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image("CatClearCircle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("清除"))
            } else if isSearchFocused {
                Button(L10n.tr("取消")) {
                    isSearchFocused = false
                    viewModel.searchText = ""
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CatDesign.textMuted)
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 14)
        .frame(height: 46)
        .catGlassCard(cornerRadius: 23, elevated: true, amberStroke: true, strokeWidth: 1.15)
        .shadow(color: CatDesign.amberGlowShadow, radius: 14, y: 6)
        .padding(.horizontal, CatDesign.horizontalMargin)
    }

    // MARK: - Content Switching

    @ViewBuilder
    private var contentBody: some View {
        if viewModel.searchText.isEmpty {
            idleStateView
        } else if viewModel.isSearching && viewModel.sections.isEmpty {
            LoadingView(L10n.tr("搜索中..."))
        } else {
            searchResultsView
        }
    }

    // MARK: - `05 · Search Idle State`

    private var idleStateView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text(L10n.tr("搜索 Vanmo"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)

                    Text(L10n.tr("搜索电影、剧集与远程服务器"))
                        .font(.system(size: 13))
                        .foregroundStyle(CatDesign.textMuted)
                        .multilineTextAlignment(.center)
                }

                if !viewModel.recentSearches.isEmpty {
                    recentSearchesBlock
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)

            Spacer(minLength: 24)

            VStack(spacing: 0) {
                Image("CatSittingLookingUp")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 118)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, CatDesign.strokeGlass, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 154, height: 1)
            }
            .padding(.bottom, 108)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentSearchesBlock: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(L10n.tr("最近搜索"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CatDesign.textDim)

                Button {
                    viewModel.clearRecentSearches()
                } label: {
                    Text(L10n.tr("清除"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CatDesign.accentAmber)
                }
                .buttonStyle(.plain)
            }

            FilterFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(viewModel.recentSearches, id: \.self) { query in
                    Button {
                        viewModel.searchText = query
                        viewModel.recordRecentSearch(query)
                        isSearchFocused = false
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(CatDesign.glowAmber)
                                .frame(width: 4, height: 4)
                            Text(query)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(CatDesign.textIvory)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .catGlassCard(cornerRadius: CatDesign.radiusPill)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 320)
        }
        .padding(.top, 8)
    }

    // MARK: - `06 · Search Results`

    private var localResultRows: [(item: SearchResultItem, sourceName: String)] {
        viewModel.sections.flatMap { section in
            section.items
                .filter { !$0.isRemoteResult }
                .map { ($0, section.title) }
        }
    }

    private var remoteResultRows: [(item: SearchResultItem, sourceName: String)] {
        viewModel.sections.flatMap { section in
            section.items
                .filter(\.isRemoteResult)
                .map { ($0, section.title) }
        }
    }

    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text(searchSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)

                    if viewModel.isSearching {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(CatDesign.accentAmber)
                    }
                }
                .padding(.top, 8)

                if viewModel.sections.isEmpty {
                    noResultsCard
                } else {
                    if !localResultRows.isEmpty {
                        localResultsSection
                    }
                    if !remoteResultRows.isEmpty {
                        remoteResultsSection
                    }
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.bottom, 110)
        }
    }

    private var localResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("本地与已扫描媒体库"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)

                Spacer()

                Text("\(localResultRows.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(CatDesign.surfacePill, in: Capsule())
            }

            ForEach(localResultRows, id: \.item.id) { entry in
                NavigationLink {
                    MediaDetailView(item: entry.item.item)
                } label: {
                    CatSearchResultRow(
                        item: entry.item.item,
                        sourceLabel: entry.sourceName,
                        isRemote: false
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    viewModel.recordRecentSearch(viewModel.searchText)
                })
            }
        }
    }

    private var remoteResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(L10n.tr("远程实时结果"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)

                    Circle()
                        .fill(CatDesign.glowAmber)
                        .frame(width: 5, height: 5)
                }

                Spacer()

                Text(L10n.tr("%d 实时", remoteResultRows.count))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CatDesign.accentAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(CatDesign.amberTintFill, in: Capsule())
                    .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.75))
            }
            .padding(.top, 4)

            ForEach(remoteResultRows, id: \.item.id) { entry in
                NavigationLink {
                    MediaDetailView(item: entry.item.item)
                } label: {
                    CatSearchResultRow(
                        item: entry.item.item,
                        sourceLabel: entry.sourceName,
                        isRemote: true
                    )
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    viewModel.recordRecentSearch(viewModel.searchText)
                })
            }
        }
    }

    private var noResultsCard: some View {
        HStack(spacing: 12) {
            Image("CatLyingYarnBall")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("没有匹配的媒体"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)

                Text(L10n.tr("请尝试其他关键词，或检查离线/休眠的服务器。"))
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CatDesign.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(CatDesign.strokeGlass, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .padding(.top, 8)
    }

    private var searchSummary: String {
        if viewModel.searchedSourceCount > 0 {
            return L10n.tr("%d 个结果 · 覆盖 %d 个来源", viewModel.results.count, viewModel.searchedSourceCount)
        }
        return L10n.tr("%d 个结果", viewModel.results.count)
    }
}

// MARK: - Search Result Row (`Card / Search Result Row`)

private struct CatSearchResultRow: View {
    let item: MediaItem
    let sourceLabel: String
    let isRemote: Bool

    private var metaText: String {
        if let year = item.year {
            return "\(year) · \(item.mediaType.displayName)"
        }
        return item.mediaType.displayName
    }

    private var qualityText: String? {
        let upper = (item.originalFileName ?? item.title).uppercased()
        if (item.videoWidth ?? 0) >= 3600 || upper.contains("2160") || upper.contains("4K") {
            if let dr = item.dynamicRange, !dr.isEmpty {
                return "4K \(dr)"
            }
            return "4K"
        }
        if (item.videoWidth ?? 0) >= 1800 || upper.contains("1080") {
            return "1080p"
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            KFImage(item.posterURL)
                .placeholder {
                    ZStack {
                        CatDesign.mediaPlaceholder
                        Image(systemName: item.mediaType.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(CatDesign.textMuted)
                    }
                }
                .fade(duration: 0.2)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(metaText)
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)

                    if let qualityText {
                        Text(qualityText)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CatDesign.textIvory)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(CatDesign.surfacePill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75)
                            )
                    }
                }

                Text(isRemote ? "\(L10n.tr("实时")) · \(sourceLabel)" : "\(L10n.tr("本地")) · \(sourceLabel)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isRemote ? CatDesign.accentAmber : CatDesign.textDim)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if isRemote {
                    Image("CatLightningBadge")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .catGlassCard(cornerRadius: 18)
    }
}

#Preview("Idle") {
    NavigationStack {
        SearchView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}
