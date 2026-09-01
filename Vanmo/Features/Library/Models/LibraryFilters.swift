import Foundation
import VanmoCore

struct LibraryRegionFilter: Identifiable, Hashable, Sendable {
    let title: String
    let isoCodes: Set<String>
    let isOther: Bool

    var id: String { title }
}

enum LibraryFilters {
    static let allTitle = L10n.tr("全部")

    static let genres: [String] = [
        allTitle,
        L10n.tr("戏剧"),
        L10n.tr("爱情"),
        L10n.tr("动作"),
        L10n.tr("科幻"),
        L10n.tr("动画"),
        L10n.tr("悬疑"),
        L10n.tr("犯罪"),
        L10n.tr("惊悚"),
        L10n.tr("冒险"),
        L10n.tr("音乐"),
        L10n.tr("历史"),
        L10n.tr("奇幻"),
        L10n.tr("恐怖"),
        L10n.tr("战争"),
        L10n.tr("传记"),
        L10n.tr("歌舞"),
        "武侠",
        "情色",
        "灾难",
        L10n.tr("西部"),
        L10n.tr("纪录片"),
        L10n.tr("短片"),
    ]

    static let regions: [LibraryRegionFilter] = [
        LibraryRegionFilter(title: allTitle, isoCodes: [], isOther: false),
        LibraryRegionFilter(title: L10n.tr("中国大陆"), isoCodes: ["CN"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("中国台湾"), isoCodes: ["TW"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("中国香港"), isoCodes: ["HK"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("美国"), isoCodes: ["US"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("韩国"), isoCodes: ["KR"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("日本"), isoCodes: ["JP"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("英国"), isoCodes: ["GB", "UK"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("德国"), isoCodes: ["DE"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("意大利"), isoCodes: ["IT"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("法国"), isoCodes: ["FR"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("西班牙"), isoCodes: ["ES"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("印度"), isoCodes: ["IN"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("泰国"), isoCodes: ["TH"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("俄罗斯"), isoCodes: ["RU"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("加拿大"), isoCodes: ["CA"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("澳大利亚"), isoCodes: ["AU"], isOther: false),
        LibraryRegionFilter(title: "爱尔兰", isoCodes: ["IE"], isOther: false),
        LibraryRegionFilter(title: "瑞典", isoCodes: ["SE"], isOther: false),
        LibraryRegionFilter(title: "巴西", isoCodes: ["BR"], isOther: false),
        LibraryRegionFilter(title: "丹麦", isoCodes: ["DK"], isOther: false),
        LibraryRegionFilter(title: L10n.tr("其他"), isoCodes: [], isOther: true),
    ]

    static let genreAliases: [String: Set<String>] = [
        L10n.tr("戏剧"): [L10n.tr("戏剧"), "剧情", "Drama"],
        L10n.tr("爱情"): [L10n.tr("爱情"), "Romance"],
        L10n.tr("动作"): [L10n.tr("动作"), "Action"],
        L10n.tr("科幻"): [L10n.tr("科幻"), "Sci-Fi", "Science Fiction"],
        L10n.tr("动画"): [L10n.tr("动画"), "Animation"],
        L10n.tr("悬疑"): [L10n.tr("悬疑"), "Mystery"],
        L10n.tr("犯罪"): [L10n.tr("犯罪"), "Crime"],
        L10n.tr("惊悚"): [L10n.tr("惊悚"), "Thriller"],
        L10n.tr("冒险"): [L10n.tr("冒险"), "Adventure"],
        L10n.tr("音乐"): [L10n.tr("音乐"), "Music"],
        L10n.tr("历史"): [L10n.tr("历史"), "History"],
        L10n.tr("奇幻"): [L10n.tr("奇幻"), "Fantasy"],
        L10n.tr("恐怖"): [L10n.tr("恐怖"), "Horror"],
        L10n.tr("战争"): [L10n.tr("战争"), "War"],
        L10n.tr("传记"): [L10n.tr("传记"), "Biography"],
        L10n.tr("歌舞"): [L10n.tr("歌舞"), "Musical"],
        "武侠": ["武侠"],
        "情色": ["情色"],
        "灾难": ["灾难"],
        L10n.tr("西部"): [L10n.tr("西部"), "Western"],
        L10n.tr("纪录片"): [L10n.tr("纪录片"), "Documentary"],
        L10n.tr("短片"): [L10n.tr("短片"), "Short"],
    ]

    static var allRegionCodes: Set<String> {
        regions.reduce(into: Set<String>()) { result, region in
            guard !region.isOther else { return }
            result.formUnion(region.isoCodes.map { $0.uppercased() })
        }
    }

    static func aliases(for genre: String) -> Set<String> {
        genreAliases[genre] ?? [genre]
    }

    static func region(for title: String) -> LibraryRegionFilter? {
        regions.first { $0.title == title }
    }
}
