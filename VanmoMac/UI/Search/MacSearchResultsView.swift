import SwiftUI
import SwiftData
import VanmoCore

struct MacSearchResultsView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @Environment(\.macTheme) private var theme

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.appBackground)
    }

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(theme.tertiaryText)
            Text(L10n.tr("搜索你的媒体库"))
                .font(.subheadline)
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(theme.tertiaryText)
            Text("未找到「\(searchViewModel.searchText)」相关结果")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                Text(searchSummary)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)

                ForEach(searchViewModel.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(theme.primaryText)

                            if let subtitle = section.subtitle {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer(minLength: 8)

                            Text("\(section.items.count)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.secondaryText)
                        }

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
            .padding(MacDesignTokens.Layout.contentPadding)
        }
    }

    private var searchSummary: String {
        let count = searchViewModel.results.count
        let sourceCount = searchViewModel.searchedSourceCount
        return "找到 \(count) 个结果，来自 \(sourceCount) 个来源"
    }
}

private struct MacSearchResultRow: View {
    @Environment(\.macTheme) private var theme

    let item: MediaItem
    let isRemoteResult: Bool

    var body: some View {
        HStack(spacing: 16) {
            MacRemoteImage(url: item.posterURL)
                .frame(width: 56, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let year = item.year {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    Text(item.mediaType.displayName)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if isRemoteResult {
                Image(systemName: "bolt.horizontal.circle")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .help(L10n.tr("远程实时结果"))
            }
        }
        .padding(12)
        .background(theme.secondaryButtonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    MacSearchResultsView()
        .environmentObject(MacAppState())
        .environmentObject(MacSearchViewModel())
        .macTheme(.dark)
        .frame(width: 900, height: 600)
}
