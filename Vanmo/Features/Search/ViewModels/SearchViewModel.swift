import SwiftUI
import SwiftData
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published private(set) var results: [MediaItem] = []
    @Published private(set) var isSearching = false

    private var modelContext: ModelContext?
    private var searchTask: Task<Void, Never>?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func search() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            return
        }

        searchTask = Task {
            isSearching = true
            defer { isSearching = false }
            await searchLibrary(query)
        }
    }

    private func searchLibrary(_ query: String) async {
        guard let context = modelContext else { return }
        do {
            let descriptor = FetchDescriptor<MediaItem>()
            let allItems = try context.fetch(descriptor)
            let lowered = query.lowercased()
            results = allItems.filter { item in
                item.title.lowercased().contains(lowered) ||
                (item.originalTitle?.lowercased().contains(lowered) ?? false) ||
                (item.director?.lowercased().contains(lowered) ?? false) ||
                item.cast.contains { $0.lowercased().contains(lowered) } ||
                item.genres.contains { $0.lowercased().contains(lowered) }
            }
        } catch {
            results = []
        }
    }
}
