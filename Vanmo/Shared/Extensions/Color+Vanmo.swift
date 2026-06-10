import SwiftUI

// MARK: - Hex 初始化

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 3 || s.count == 6 else { return nil }
        if s.count == 3 {
            s = s.map { String([$0, $0]) }.joined()
        }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - 配色主题

/// 全局配色主题。每套主题定义 primary / background / surface 三色组合，
/// 并影响整体 ColorScheme（浅色 / 深色 / 跟随系统）。
enum ColorTheme: String, CaseIterable, Identifiable {
    /// 跟随系统：浅色 / 深色随 iOS 设置自动切换
    case system
    /// 系统级浅色系
    case light
    /// 系统级深色系
    case dark
    /// 撞色 1：栗咖 / 米色 / 薄荷
    case warmEarth
    /// 撞色 2：墨蓝 / 奶油 / 橄榄
    case forestCream
    /// 撞色 3：胭脂 / 雪粉 / 丁香紫
    case roseLilac

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:       return "跟随系统"
        case .light:        return "系统浅色"
        case .dark:         return "系统深色"
        case .warmEarth:    return "栗咖薄荷"
        case .forestCream:  return "墨蓝橄榄"
        case .roseLilac:    return "胭脂丁香"
        }
    }

    var subtitle: String {
        switch self {
        case .system:       return "随系统外观自动切换浅 / 深色"
        case .light:        return "标准浅色界面 · 暖咖主色"
        case .dark:         return "标准深色界面 · 柔咖主色"
        case .warmEarth:    return "深咖 · 米色 · 薄荷绿"
        case .forestCream:  return "墨蓝 · 奶油 · 橄榄绿"
        case .roseLilac:    return "胭脂 · 雪粉 · 丁香紫"
        }
    }

    /// 用于 `.preferredColorScheme(_:)`，nil 代表跟随系统
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:                                   return nil
        case .light, .warmEarth, .forestCream, .roseLilac: return .light
        case .dark:                                     return .dark
        }
    }

    /// 是否为内置撞色配置（用于 UI 上区分系统主题与自定义主题）
    var isContrastTheme: Bool {
        switch self {
        case .warmEarth, .forestCream, .roseLilac: return true
        default: return false
        }
    }

    // MARK: - 三色

    var primary: Color {
        switch self {
        case .system:
            return Color(uiColor: UIColor { trait in
                trait.userInterfaceStyle == .dark
                    ? UIColor(red: 0xA7 / 255, green: 0x84 / 255, blue: 0x82 / 255, alpha: 1)
                    : UIColor(red: 0x5C / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
            })
        case .light:        return Color(hex: "#5C4444")!
        case .dark:         return Color(hex: "#A78482")!
        case .warmEarth:    return Color(hex: "#5C4444")!
        case .forestCream:  return Color(hex: "#393C54")!
        case .roseLilac:    return Color(hex: "#6E3537")!
        }
    }

    var background: Color {
        switch self {
        case .system:
            return Color(uiColor: .systemBackground)
        case .light:
            return Color(uiColor: UIColor { _ in .white })
        case .dark:
            return Color(uiColor: UIColor { _ in
                UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
            })
        case .warmEarth:    return Color(hex: "#EDE7D5")!
        case .forestCream:  return Color(hex: "#F8FAEC")!
        case .roseLilac:    return Color(hex: "#FCEFF5")!
        }
    }

    var surface: Color {
        switch self {
        case .system:
            return Color(uiColor: .secondarySystemBackground)
        case .light:
            return Color(uiColor: UIColor { _ in
                UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            })
        case .dark:
            return Color(uiColor: UIColor { _ in
                UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            })
        case .warmEarth:    return Color(hex: "#B4CFCB")!
        case .forestCream:  return Color(hex: "#97B077")!
        case .roseLilac:    return Color(hex: "#A79EC9")!
        }
    }

    // MARK: - 当前主题

    static let storageKey = "appearance.theme"

    /// 当前 UserDefaults 中保存的主题，未设置时回落到 `.system`
    static var current: ColorTheme {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let theme = ColorTheme(rawValue: raw)
        else {
            return .system
        }
        return theme
    }
}

// MARK: - Vanmo 全局色

extension Color {
    /// 主品牌色，按当前主题动态变化
    static var vanmoPrimary: Color { ColorTheme.current.primary }

    /// 整体页面背景色，按当前主题动态变化
    static var vanmoBackground: Color { ColorTheme.current.background }

    /// 卡片 / 控件背景色，按当前主题动态变化
    static var vanmoSurface: Color { ColorTheme.current.surface }

    /// 次级文本色，跟随系统
    static let vanmoSubtext = Color(.secondaryLabel)

    /// 半透明遮罩
    static let vanmoOverlay = Color.black.opacity(0.6)
}

// MARK: - 渐变

extension LinearGradient {
    static let posterOverlay = LinearGradient(
        colors: [.clear, .black.opacity(0.8)],
        startPoint: .center,
        endPoint: .bottom
    )

    static let headerOverlay = LinearGradient(
        colors: [.clear, .clear, .black.opacity(0.9)],
        startPoint: .top,
        endPoint: .bottom
    )
}
