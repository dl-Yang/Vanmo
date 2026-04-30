import Foundation

enum LibrarySection: String, CaseIterable, Identifiable, Sendable {
    case movie
    case tvShow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movie: return "电影"
        case .tvShow: return "电视剧"
        }
    }

    var mediaType: MediaType {
        switch self {
        case .movie: return .movie
        case .tvShow: return .tvShow
        }
    }
}

struct LibraryRegionFilter: Identifiable, Hashable, Sendable {
    let title: String
    let isoCodes: Set<String>
    let isOther: Bool

    var id: String { title }
}

enum LibraryFilters {
    static let allTitle = "全部"

    static let genres: [String] = [
        allTitle,
        "戏剧",
        "爱情",
        "动作",
        "科幻",
        "动画",
        "悬疑",
        "犯罪",
        "惊悚",
        "冒险",
        "音乐",
        "历史",
        "奇幻",
        "恐怖",
        "战争",
        "传记",
        "歌舞",
        "武侠",
        "情色",
        "灾难",
        "西部",
        "纪录片",
        "短片",
    ]

    static let regions: [LibraryRegionFilter] = [
        LibraryRegionFilter(title: allTitle, isoCodes: [], isOther: false),
        LibraryRegionFilter(title: "中国大陆", isoCodes: ["CN"], isOther: false),
        LibraryRegionFilter(title: "中国台湾", isoCodes: ["TW"], isOther: false),
        LibraryRegionFilter(title: "中国香港", isoCodes: ["HK"], isOther: false),
        LibraryRegionFilter(title: "美国", isoCodes: ["US"], isOther: false),
        LibraryRegionFilter(title: "韩国", isoCodes: ["KR"], isOther: false),
        LibraryRegionFilter(title: "日本", isoCodes: ["JP"], isOther: false),
        LibraryRegionFilter(title: "英国", isoCodes: ["GB", "UK"], isOther: false),
        LibraryRegionFilter(title: "德国", isoCodes: ["DE"], isOther: false),
        LibraryRegionFilter(title: "意大利", isoCodes: ["IT"], isOther: false),
        LibraryRegionFilter(title: "法国", isoCodes: ["FR"], isOther: false),
        LibraryRegionFilter(title: "西班牙", isoCodes: ["ES"], isOther: false),
        LibraryRegionFilter(title: "印度", isoCodes: ["IN"], isOther: false),
        LibraryRegionFilter(title: "泰国", isoCodes: ["TH"], isOther: false),
        LibraryRegionFilter(title: "俄罗斯", isoCodes: ["RU"], isOther: false),
        LibraryRegionFilter(title: "加拿大", isoCodes: ["CA"], isOther: false),
        LibraryRegionFilter(title: "澳大利亚", isoCodes: ["AU"], isOther: false),
        LibraryRegionFilter(title: "爱尔兰", isoCodes: ["IE"], isOther: false),
        LibraryRegionFilter(title: "瑞典", isoCodes: ["SE"], isOther: false),
        LibraryRegionFilter(title: "巴西", isoCodes: ["BR"], isOther: false),
        LibraryRegionFilter(title: "丹麦", isoCodes: ["DK"], isOther: false),
        LibraryRegionFilter(title: "其他", isoCodes: [], isOther: true),
    ]

    static let genreAliases: [String: Set<String>] = [
        "戏剧": ["戏剧", "剧情", "Drama"],
        "爱情": ["爱情", "Romance"],
        "动作": ["动作", "Action"],
        "科幻": ["科幻", "Sci-Fi", "Science Fiction"],
        "动画": ["动画", "Animation"],
        "悬疑": ["悬疑", "Mystery"],
        "犯罪": ["犯罪", "Crime"],
        "惊悚": ["惊悚", "Thriller"],
        "冒险": ["冒险", "Adventure"],
        "音乐": ["音乐", "Music"],
        "历史": ["历史", "History"],
        "奇幻": ["奇幻", "Fantasy"],
        "恐怖": ["恐怖", "Horror"],
        "战争": ["战争", "War"],
        "传记": ["传记", "Biography"],
        "歌舞": ["歌舞", "Musical"],
        "武侠": ["武侠"],
        "情色": ["情色"],
        "灾难": ["灾难"],
        "西部": ["西部", "Western"],
        "纪录片": ["纪录片", "Documentary"],
        "短片": ["短片", "Short"],
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
