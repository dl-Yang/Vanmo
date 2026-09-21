import SwiftUI
import VanmoCore

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

    /// 从 8 位十六进制（#RRGGBBAA）创建颜色，支持透明度。用于字幕样式持久化。
    init?(rgbaHex: String) {
        var s = rgbaHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value >> 24) & 0xFF) / 255
        let g = Double((value >> 16) & 0xFF) / 255
        let b = Double((value >> 8) & 0xFF) / 255
        let a = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// 序列化为 8 位十六进制（#RRGGBBAA），保留透明度。
    var rgbaHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let channel: (CGFloat) -> Int = { max(0, min(255, Int(($0 * 255).rounded()))) }
        return String(format: "#%02X%02X%02X%02X", channel(r), channel(g), channel(b), channel(a))
    }
}

// MARK: - 外观主题

/// 全局外观主题，仅控制浅色、深色或跟随系统。
enum ColorTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.tr("跟随系统")
        case .light: return L10n.tr("日间")
        case .dark: return L10n.tr("夜间")
        }
    }

    var subtitle: String {
        switch self {
        case .system: return L10n.tr("随系统外观自动切换日间 / 夜间")
        case .light: return L10n.tr("始终使用日间外观")
        case .dark: return L10n.tr("始终使用夜间外观")
        }
    }

    /// 用于 `.preferredColorScheme(_:)`，nil 代表跟随系统
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
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
        case .light: return Color(hex: "#5C4444")!
        case .dark: return Color(hex: "#A78482")!
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
        }
    }

    // MARK: - 当前主题

    static let storageKey = "appearance.theme"
    private static let retiredLightThemeValues: Set<String> = [
        "warmEarth",
        "forestCream",
        "roseLilac"
    ]

    static func migrateStoredValue(in defaults: UserDefaults = .standard) {
        guard let rawValue = defaults.string(forKey: storageKey) else { return }
        if retiredLightThemeValues.contains(rawValue) {
            defaults.set(ColorTheme.light.rawValue, forKey: storageKey)
        } else if ColorTheme(rawValue: rawValue) == nil {
            defaults.set(ColorTheme.system.rawValue, forKey: storageKey)
        }
    }

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
    /// 全局蓝色强调色：Navigation Tab / 播放钮 / 进度 / 服务器图标 / 类型药丸等统一使用。
    static let vanmoAccent = Color(red: 0x14 / 255, green: 0x5C / 255, blue: 0xFF / 255)

    /// 主品牌色统一使用蓝色强调色，背景与表面仍按当前主题动态变化。
    static var vanmoPrimary: Color { vanmoAccent }

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
