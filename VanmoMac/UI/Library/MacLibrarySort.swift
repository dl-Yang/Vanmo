import Foundation
import VanmoCore

enum MacLibrarySortOption: String, CaseIterable, Identifiable, Sendable {
    case addedDate
    case title
    case year
    case rating

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .addedDate: L10n.tr("添加日期")
        case .title: L10n.tr("标题")
        case .year: L10n.tr("年份")
        case .rating: L10n.tr("评分")
        }
    }
}

enum MacLibrarySorting {
    static func sorted(_ items: [MediaItem], by option: MacLibrarySortOption) -> [MediaItem] {
        switch option {
        case .addedDate:
            return items.sorted { $0.addedAt > $1.addedAt }
        case .title:
            return items.sorted {
                $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
            }
        case .year:
            return items.sorted { lhs, rhs in
                switch (lhs.year, rhs.year) {
                case let (left?, right?):
                    return left > right
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }
            }
        case .rating:
            return items.sorted { lhs, rhs in
                switch (lhs.rating, rhs.rating) {
                case let (left?, right?):
                    return left > right
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return lhs.displayTitle.localizedStandardCompare(rhs.displayTitle) == .orderedAscending
                }
            }
        }
    }

    static func embySortParameters(for option: MacLibrarySortOption) -> (sortBy: String, sortOrder: String) {
        switch option {
        case .addedDate:
            return ("DateCreated", "Descending")
        case .title:
            return ("SortName", "Ascending")
        case .year:
            return ("ProductionYear", "Descending")
        case .rating:
            return ("CommunityRating", "Descending")
        }
    }
}
