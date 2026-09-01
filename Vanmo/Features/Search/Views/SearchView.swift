import SwiftUI
import SwiftData
import Kingfisher
import VanmoCore

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var connectionsViewModel: ConnectionsViewModel
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        Group {
            if viewModel.searchText.isEmpty {
                emptySearchState
            } else if viewModel.isSearching {
                LoadingView(L10n.tr("搜索中..."))
            } else {
                searchResults
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vanmoBackground)
        .navigationTitle(L10n.tr("搜索"))
        .searchable(text: $viewModel.searchText, prompt: L10n.tr("搜索电影、剧集..."))
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
    }

    // MARK: - Empty State

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(L10n.tr("搜索你的媒体库"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                groupedResults
            }
            .padding()
        }
    }

    @ViewBuilder
    private var groupedResults: some View {
        if viewModel.sections.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Text(searchSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(viewModel.sections) { section in
                Section {
                    VStack(spacing: 10) {
                        ForEach(section.items) { result in
                            NavigationLink {
                                MediaDetailView(item: result.item)
                            } label: {
                                HStack(spacing: 10) {
                                    MediaListRow(item: result.item)
                                    if result.isRemoteResult {
                                        Image(systemName: "bolt.horizontal.circle")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel(L10n.tr("远程实时结果"))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    searchSectionHeader(section)
                }
            }
        }
    }

    private func searchSectionHeader(_ section: SearchResultSection) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .foregroundStyle(.primary)

            if let subtitle = section.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text("\(section.items.count)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private var searchSummary: String {
        if viewModel.searchedSourceCount > 0 {
            return "\(viewModel.results.count) 个结果 · 覆盖 \(viewModel.searchedSourceCount) 个来源"
        }
        return "\(viewModel.results.count) 个结果"
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}
