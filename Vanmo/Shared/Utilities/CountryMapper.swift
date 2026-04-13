import Foundation

enum CountryMapper {

    private static let map: [String: String] = [
        "CN": "中国", "US": "美国", "GB": "英国", "JP": "日本",
        "KR": "韩国", "FR": "法国", "DE": "德国", "IN": "印度",
        "IT": "意大利", "ES": "西班牙", "CA": "加拿大", "AU": "澳大利亚",
        "TW": "中国台湾", "HK": "中国香港", "RU": "俄罗斯", "TH": "泰国",
        "BR": "巴西", "MX": "墨西哥", "SE": "瑞典", "DK": "丹麦",
        "NO": "挪威", "NL": "荷兰", "PL": "波兰", "TR": "土耳其",
        "AR": "阿根廷", "NZ": "新西兰", "IE": "爱尔兰", "IL": "以色列",
    ]

    static func displayName(for code: String) -> String {
        map[code.uppercased()] ?? code
    }

    static func regionGroup(for codes: [String]) -> String {
        guard let first = codes.first else { return "其他" }
        return displayName(for: first)
    }
}
