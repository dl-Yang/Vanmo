import Foundation
import SwiftData
import VanmoCore

@MainActor
final class MacLibraryViewModel: ObservableObject {
    @Published private(set) var continueWatching: [MacLibraryDisplayItem] = []
    @Published private(set) var recentlyAdded: [MacLibraryDisplayItem] = []
    @Published private(set) var isLibraryEmpty = true

    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        reload()
    }

    func reload(filter: MacLibraryFilter = .all, section: MacSidebarSection = .home) {
        guard let modelContext else {
            clearLibraryContent()
            return
        }

        do {
            let allItems = try modelContext.fetch(FetchDescriptor<MediaItem>())
            isLibraryEmpty = allItems.isEmpty

            let items = try fetchItems(from: modelContext, filter: filter, section: section)
            let continueItems = items
                .filter { $0.lastPlaybackPosition > 0 && !$0.isWatched }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
                .prefix(12)

            let recentItems = items
                .sorted { $0.addedAt > $1.addedAt }
                .prefix(24)

            continueWatching = continueItems.map(displayItem(from:))
            recentlyAdded = recentItems.map(displayItem(from:))
        } catch {
            clearLibraryContent()
        }
    }

    private func clearLibraryContent() {
        continueWatching = []
        recentlyAdded = []
        isLibraryEmpty = true
    }

    private func fetchItems(
        from context: ModelContext,
        filter: MacLibraryFilter,
        section: MacSidebarSection
    ) throws -> [MediaItem] {
        var items = try context.fetch(FetchDescriptor<MediaItem>())

        switch section {
        case .home:
            break
        case .movies:
            items = items.filter { $0.mediaType == .movie }
        case .tvShows:
            items = items.filter { $0.mediaType == .tvShow }
        case .favorites:
            items = items.filter(\.isFavorite)
        }

        switch filter {
        case .all:
            break
        case .unwatched:
            items = items.filter { !$0.isWatched }
        case .recentlyAdded:
            items = items.sorted { $0.addedAt > $1.addedAt }
        case .movies:
            items = items.filter { $0.mediaType == .movie }
        case .tvShows:
            items = items.filter { $0.mediaType == .tvShow }
        }

        return items
    }

    private func displayItem(from item: MediaItem) -> MacLibraryDisplayItem {
        let progress = item.duration > 0 ? item.lastPlaybackPosition / item.duration : 0
        let subtitle: String
        if item.lastPlaybackPosition > 0, item.duration > 0 {
            subtitle = MacFormatters.remainingDuration(position: item.lastPlaybackPosition, total: item.duration)
        } else if let year = item.year {
            subtitle = String(year)
        } else {
            subtitle = item.mediaType == .movie ? "Movie" : "TV Show"
        }

        return MacLibraryDisplayItem(
            id: item.id,
            title: item.displayTitle,
            subtitle: subtitle,
            posterURL: item.posterURL ?? item.backdropURL,
            progress: progress,
            mediaItem: item
        )
    }

    func resolveMediaItem(for displayItem: MacLibraryDisplayItem) -> MediaItem? {
        displayItem.mediaItem
    }
}
