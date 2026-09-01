import Foundation
import VanmoCore

enum CountryMapper {

    private static let map: [String: String] = [
        "CN": "中国", "US": L10n.tr("美国"), "GB": L10n.tr("英国"), "JP": L10n.tr("日本"),
        "KR": L10n.tr("韩国"), "FR": L10n.tr("法国"), "DE": L10n.tr("德国"), "IN": L10n.tr("印度"),
        "IT": L10n.tr("意大利"), "ES": L10n.tr("西班牙"), "CA": L10n.tr("加拿大"), "AU": L10n.tr("澳大利亚"),
        "TW": L10n.tr("中国台湾"), "HK": L10n.tr("中国香港"), "RU": L10n.tr("俄罗斯"), "TH": L10n.tr("泰国"),
        "BR": "巴西", "MX": "墨西哥", "SE": "瑞典", "DK": "丹麦",
        "NO": "挪威", "NL": "荷兰", "PL": "波兰", "TR": "土耳其",
        "AR": "阿根廷", "NZ": "新西兰", "IE": "爱尔兰", "IL": L10n.tr("以色列"),
    ]

    static func displayName(for code: String) -> String {
        map[code.uppercased()] ?? code
    }

    static func regionGroup(for codes: [String]) -> String {
        guard let first = codes.first else { return L10n.tr("其他") }
        return displayName(for: first)
    }
}
