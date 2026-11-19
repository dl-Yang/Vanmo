import SwiftUI
import SwiftData
import VanmoCore

struct MacSearchResultsView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @Environment(\.macTheme) private var theme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacCatAmbientHalo()
                .offset(x: -70, y: -30)

            Group {
                if searchViewModel.searchText.isEmpty {
                    emptySearchState
                } else if searchViewModel.isSearching {
                    loadingState
                } else if searchViewModel.sections.isEmpty {
                    noResultsState
                } else {
                    resultsList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.appBackground)
    }

    private var emptySearchState: some View {
        VStack(spacing: 14) {
            Image("MacSearchCat")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(theme.accentAmber.opacity(0.75))
            Text(L10n.tr("搜索你的媒体库"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(L10n.tr("使用左侧搜索栏或按下 ⌘F 开始搜索本地与远程媒体"))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.tr("搜索中..."))
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image("MacCatFolderCurious")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 56)
            Text(L10n.tr("未找到「%@」相关结果", searchViewModel.searchText))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 8) {
                    Text(L10n.tr("搜索结果"))
                        .font(MacDesignTokens.Typography.headerTitle)
                        .foregroundStyle(theme.primaryText)

                    Text(searchSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.surfacePill, in: Capsule())
                }

                ForEach(searchViewModel.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        MacCatSectionHeaderRow(
                            title: section.title,
                            badgeText: section.subtitle.map { "\($0) · \(section.items.count)" } ?? "\(section.items.count)",
                            showsStretchingCat: false
                        )

                        ForEach(section.items) { result in
                            Button {
                                appState.openDetail(result.item)
                            } label: {
                                MacSearchResultRow(item: result.item, isRemoteResult: result.isRemoteResult)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
            .padding(.top, 22)
            .padding(.bottom, 32)
        }
    }

    private var searchSummary: String {
        let count = searchViewModel.results.count
        let sourceCount = searchViewModel.searchedSourceCount
        return L10n.tr("%d 个结果 · 覆盖 %d 个来源", count, sourceCount)
    }
}

private struct MacSearchResultRow: View {
    @Environment(\.macTheme) private var theme

    let item: MediaItem
    let isRemoteResult: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            MacRemoteImage(url: item.posterURL)
                .frame(width: 52, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.75)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let year = item.year {
                        Text(String(year))
                            .font(.system(size: 11.5))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Text(item.mediaType.displayName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(theme.accentAmber)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.amberTintFill, in: Capsule())
                }
            }

            Spacer(minLength: 0)

            if isRemoteResult {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.accentAmber)
                    .help(L10n.tr("远程实时结果"))
            }
        }
        .padding(12)
        .macCatGlassCard(theme: theme, cornerRadius: 14, isHighlighted: isHovered)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

#Preview {
    MacSearchResultsView()
        .environmentObject(MacAppState())
        .environmentObject(MacSearchViewModel())
        .macTheme(.dark)
        .frame(width: 900, height: 600)
}
