import SwiftUI
import SwiftData

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
        .navigationTitle("搜索")
        .searchable(text: $viewModel.searchText, prompt: "搜索电影、剧集...")
        .searchScopes($viewModel.searchScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.search()
        }
        .onChange(of: viewModel.searchScope) { _, _ in
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
            Text("搜索你的媒体库或在线数据库")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results

    private var searchResults: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if viewModel.searchScope == .library {
                    libraryResults
                } else {
                    onlineResults
                }
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

    @ViewBuilder
    private var onlineResults: some View {
        if viewModel.tmdbMovies.isEmpty && viewModel.tmdbShows.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchText)
        } else {
            if !viewModel.tmdbMovies.isEmpty {
                Text("电影")
                    .font(.headline)

                ForEach(viewModel.tmdbMovies) { movie in
                    TMDbResultRow(
                        title: movie.title,
                        subtitle: movie.releaseDate,
                        posterPath: movie.posterPath,
                        rating: movie.voteAverage
                    )
                }
            }

            if !viewModel.tmdbShows.isEmpty {
                Text("剧集")
                    .font(.headline)
                    .padding(.top, 8)

                ForEach(viewModel.tmdbShows) { show in
                    TMDbResultRow(
                        title: show.name,
                        subtitle: show.firstAirDate,
                        posterPath: show.posterPath,
                        rating: show.voteAverage
                    )
                }
            }
        }
    }
}

// MARK: - TMDb Result Row

struct TMDbResultRow: View {
    let title: String
    let subtitle: String?
    let posterPath: String?
    let rating: Double?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: TMDbService.shared.posterURL(posterPath, size: .w92)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle()
                        .fill(Color.vanmoSurface)
                        .overlay {
                            Image(systemName: "film")
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: 50, height: 75)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let rating {
                RatingBadge(rating)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
