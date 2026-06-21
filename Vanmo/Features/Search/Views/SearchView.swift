import SwiftUI
import SwiftData
import Kingfisher

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = SearchViewModel()

    var body: some View {
        Group {
            if viewModel.searchText.isEmpty {
                emptySearchState
            } else if viewModel.isSearching {
                LoadingView("搜索中...")
            } else {
                searchResults
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vanmoBackground)
        .navigationTitle("搜索")
        .searchable(text: $viewModel.searchText, prompt: "搜索电影、剧集...")
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.search()
        }
        .task {
            viewModel.setModelContext(modelContext)
        }
    }

    // MARK: - Empty State

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("搜索你的媒体库")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                libraryResults
            }
            .padding()
        }
    }

    @ViewBuilder
    private var libraryResults: some View {
        if viewModel.results.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            Text("\(viewModel.results.count) 个结果")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(viewModel.results) { item in
                NavigationLink {
                    MediaDetailView(item: item)
                } label: {
                    MediaListRow(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
