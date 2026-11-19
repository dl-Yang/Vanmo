import SwiftUI

/// macOS Black Cat Redesign 设计令牌（Figma `Vanmo-MacOS` fileKey: O75W1XT1Q0btSrepDwEx39，node `144:2`）。
/// 夜间模式 100% 对齐 Obsidian Glass (`#121316` + `#FFB547`)；
/// 日间模式对齐 Preferences Day Mode (`#FAF7F2` Warm Oat Milk + `#E5DEC9` + `#18181B` + `#B86A08`)，保证可读对比度 ≥ 4.5:1。
enum MacDesignTokens {
    enum Layout {
        static let sidebarWidth: CGFloat = 240
        static let sidebarMinWidth: CGFloat = 220
        static let sidebarMaxWidth: CGFloat = 380
        static let trafficLightsLeadingInset: CGFloat = 78
        static let trafficLightsTopInset: CGFloat = 8
        /// 顶部悬浮窗口控制行高度（收起侧边栏时按钮保持原位可用）
        static let sidebarControlRowHeight: CGFloat = 44
        static let headerHeight: CGFloat = 56
        static let contentPadding: CGFloat = 36
        static let compactContentPadding: CGFloat = 24
        static let detailContentPadding: CGFloat = 36
        static let sidebarRowHeight: CGFloat = 34
        static let sidebarRowRadius: CGFloat = 10
        static let sidebarHorizontalPadding: CGFloat = 14
        static let sidebarItemPadding: CGFloat = 10
        static let filterPillHeight: CGFloat = 30
        static let continueWatchingWidth: CGFloat = 267
        static let continueWatchingThumbHeight: CGFloat = 142
        static let posterWidth: CGFloat = 173
        static let posterHeight: CGFloat = 244
        static let posterSpacing: CGFloat = 18
        static let heroHeight: CGFloat = 420
        static let heroBannerHeight: CGFloat = 246
        static let heroLinearHeight: CGFloat = 220
        static let playerControlPanelWidth: CGFloat = 980
        static let playerControlPanelHeight: CGFloat = 92
        static let playerControlPanelRadius: CGFloat = 22
        static let playerDrawerWidth: CGFloat = 300
        static let addConnectionWidth: CGFloat = 540
        static let addConnectionHeight: CGFloat = 600
        static let settingsWindowWidth: CGFloat = 720
        static let settingsWindowHeight: CGFloat = 540
        static let settingsContentMaxWidth: CGFloat = 664
        static let downloadWidth: CGFloat = 46
        static let downloadHeight: CGFloat = 64
        static let downloadRowSpacing: CGFloat = 12
        static let downloadContentPadding: CGFloat = 24
    }

    enum Radius {
        static let searchField: CGFloat = 10
        static let segmentedControl: CGFloat = 17
        static let segmentedSegment: CGFloat = 13
        static let poster: CGFloat = 16
        static let continueWatching: CGFloat = 16
        static let heroBanner: CGFloat = 20
        static let modalDialog: CGFloat = 20
        static let downloadCard: CGFloat = 14
        static let downloadPoster: CGFloat = 8
        static let chip: CGFloat = 10
        static let circularButton: CGFloat = 23
        static let playButton: CGFloat = 23
        static let inputField: CGFloat = 11
    }

    enum Typography {
        static let headerTitle = Font.system(size: 18, weight: .bold)
        static let sectionTitle = Font.system(size: 18, weight: .bold)
        static let sidebarItem = Font.system(size: 13, weight: .medium)
        static let sidebarSection = Font.system(size: 10, weight: .semibold)
        static let filterPill = Font.system(size: 12, weight: .medium)
        static let cardTitle = Font.system(size: 13, weight: .semibold)
        static let cardSubtitle = Font.system(size: 11, weight: .regular)
        static let cardAction = Font.system(size: 12.5, weight: .semibold)
        static let detailHeroTitle = Font.system(size: 34, weight: .bold)
        static let detailSectionTitle = Font.system(size: 17, weight: .bold)
        static let playerTitle = Font.system(size: 13.5, weight: .bold)
        static let playerTime = Font.system(size: 12, weight: .medium)
    }

    // MARK: - Brand Constants

    /// 纯粹发光琥珀金 `#FFB547`（用于进度条、发光猫眼、播放器、深色按钮）
    static let glowAmber = Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255)
    /// 黑猫实体剪影黑 `#0A0A0C`
    static let catSilhouette = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0C / 255)
    /// 兼容旧引用的强调色（已统一为品牌琥珀金）
    static let accentAmber = glowAmber
    static let accentBlue = glowAmber
    static let ctaBlue = glowAmber
    static let ratingRed = Color(red: 0xFF / 255, green: 0x64 / 255, blue: 0x67 / 255)

    // MARK: - Cinema Player Dark Constants (始终暗黑电影表面)

    enum Cinema {
        static let background = Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255)
        static let panelGlass = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.84)
        static let drawerGlass = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.92)
        static let surfacePill = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.08)
        static let surfaceRow = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.03)
        static let textIvory = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
        static let textMuted = Color(red: 168 / 255, green: 165 / 255, blue: 158 / 255)
        static let textDim = Color(red: 112 / 255, green: 110 / 255, blue: 105 / 255)
        static let strokeGlass = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.12)
        static let strokeAmber = glowAmber.opacity(0.45)
        static let amberTint = glowAmber.opacity(0.14)
        static let track = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.20)
        static let amber = glowAmber
    }
}

struct MacThemeColors {
    let isDark: Bool
    let appBackground: Color
    let sidebarBackground: Color
    let sidebarBorder: Color
    let headerBackground: Color
    let headerBorder: Color
    let surfaceGlass: Color
    let surfacePanel: Color
    let surfacePill: Color
    let surfaceRowSubtle: Color
    let strokeGlass: Color
    let strokeSubtle: Color
    let strokeAmber: Color
    let accentAmber: Color
    let amberTintFill: Color
    let amberTintStrong: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let sidebarItemText: Color
    let sidebarSelectedBackground: Color
    let sidebarSelectedText: Color
    let searchBackground: Color
    let searchBorder: Color
    let searchPlaceholder: Color
    let filterSelectedBackground: Color
    let filterSelectedText: Color
    let filterUnselectedBackground: Color
    let filterUnselectedText: Color
    let segmentedBackground: Color
    let segmentedSelectedBackground: Color
    let cardSubtitle: Color
    let sectionHeader: Color
    let chipBackground: Color
    let chipBorder: Color
    let chipText: Color
    let secondaryButtonBackground: Color
    let playerPanelBackground: Color
    let playerScrubberTrack: Color
    let progressTrack: Color
    let emptyDescriptionText: Color
    let emptyIconBackground: Color
    let emptyIconBorder: Color
    let dangerRed: Color
    let successGreen: Color

    static let light = MacThemeColors(
        isDark: false,
        appBackground: Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255), // Warm Oat Milk #FAF7F2
        sidebarBackground: Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE3 / 255).opacity(0.78),
        sidebarBorder: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255),
        headerBackground: Color.clear,
        headerBorder: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255).opacity(0.75),
        surfaceGlass: Color.white.opacity(0.86),
        surfacePanel: Color(red: 0xFA / 255, green: 0xF7 / 255, blue: 0xF2 / 255).opacity(0.96),
        surfacePill: Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.06),
        surfaceRowSubtle: Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.03),
        strokeGlass: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255),
        strokeSubtle: Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.08),
        strokeAmber: Color(red: 0xC8 / 255, green: 0x7A / 255, blue: 0x19 / 255).opacity(0.45),
        accentAmber: Color(red: 0xB8 / 255, green: 0x6A / 255, blue: 0x08 / 255),
        amberTintFill: Color(red: 0xC8 / 255, green: 0x7A / 255, blue: 0x19 / 255).opacity(0.12),
        amberTintStrong: Color(red: 0xC8 / 255, green: 0x7A / 255, blue: 0x19 / 255).opacity(0.16),
        primaryText: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255),
        secondaryText: Color(red: 0x57 / 255, green: 0x53 / 255, blue: 0x4E / 255),
        tertiaryText: Color(red: 0x78 / 255, green: 0x71 / 255, blue: 0x6C / 255),
        sidebarItemText: Color(red: 0x57 / 255, green: 0x53 / 255, blue: 0x4E / 255),
        sidebarSelectedBackground: Color(red: 0xC8 / 255, green: 0x7A / 255, blue: 0x19 / 255).opacity(0.12),
        sidebarSelectedText: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255),
        searchBackground: Color.white.opacity(0.86),
        searchBorder: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255),
        searchPlaceholder: Color(red: 0x6B / 255, green: 0x68 / 255, blue: 0x60 / 255),
        filterSelectedBackground: Color(red: 0xC8 / 255, green: 0x7A / 255, blue: 0x19 / 255).opacity(0.14),
        filterSelectedText: Color(red: 0xB8 / 255, green: 0x6A / 255, blue: 0x08 / 255),
        filterUnselectedBackground: Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.05),
        filterUnselectedText: Color(red: 0x57 / 255, green: 0x53 / 255, blue: 0x4E / 255),
        segmentedBackground: Color.white.opacity(0.86),
        segmentedSelectedBackground: Color(red: 0xC8 / 255, green: 0x7A / 255, blue: 0x19 / 255).opacity(0.14),
        cardSubtitle: Color(red: 0x6B / 255, green: 0x68 / 255, blue: 0x60 / 255),
        sectionHeader: Color(red: 0x78 / 255, green: 0x71 / 255, blue: 0x6C / 255),
        chipBackground: Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.06),
        chipBorder: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255),
        chipText: Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255),
        secondaryButtonBackground: Color.white.opacity(0.86),
        playerPanelBackground: MacDesignTokens.Cinema.panelGlass,
        playerScrubberTrack: MacDesignTokens.Cinema.track,
        progressTrack: Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.14),
        emptyDescriptionText: Color(red: 0x57 / 255, green: 0x53 / 255, blue: 0x4E / 255),
        emptyIconBackground: Color.white.opacity(0.88),
        emptyIconBorder: Color(red: 0xE5 / 255, green: 0xDE / 255, blue: 0xC9 / 255),
        dangerRed: Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255),
        successGreen: Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255)
    )

    static let dark = MacThemeColors(
        isDark: true,
        appBackground: Color(red: 0x12 / 255, green: 0x13 / 255, blue: 0x16 / 255), // Obsidian #121316
        sidebarBackground: Color(red: 23 / 255, green: 25 / 255, blue: 30 / 255).opacity(0.75),
        sidebarBorder: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.10),
        headerBackground: Color.clear,
        headerBorder: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.08),
        surfaceGlass: Color(red: 26 / 255, green: 28 / 255, blue: 34 / 255).opacity(0.73),
        surfacePanel: Color(red: 20 / 255, green: 22 / 255, blue: 26 / 255).opacity(0.95),
        surfacePill: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.08),
        surfaceRowSubtle: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.03),
        strokeGlass: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.12),
        strokeSubtle: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.07),
        strokeAmber: MacDesignTokens.glowAmber.opacity(0.45),
        accentAmber: MacDesignTokens.glowAmber,
        amberTintFill: MacDesignTokens.glowAmber.opacity(0.11),
        amberTintStrong: MacDesignTokens.glowAmber.opacity(0.16),
        primaryText: Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255), // Ivory #F4EFE6
        secondaryText: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255), // Muted #A8A59E
        tertiaryText: Color(red: 0x70 / 255, green: 0x6E / 255, blue: 0x69 / 255), // Dim #706E69
        sidebarItemText: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255),
        sidebarSelectedBackground: MacDesignTokens.glowAmber.opacity(0.11),
        sidebarSelectedText: Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255),
        searchBackground: Color(red: 26 / 255, green: 28 / 255, blue: 34 / 255).opacity(0.73),
        searchBorder: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.12),
        searchPlaceholder: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255),
        filterSelectedBackground: MacDesignTokens.glowAmber.opacity(0.14),
        filterSelectedText: MacDesignTokens.glowAmber,
        filterUnselectedBackground: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.08),
        filterUnselectedText: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255),
        segmentedBackground: Color(red: 26 / 255, green: 28 / 255, blue: 34 / 255).opacity(0.73),
        segmentedSelectedBackground: MacDesignTokens.glowAmber.opacity(0.14),
        cardSubtitle: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255),
        sectionHeader: Color(red: 0x70 / 255, green: 0x6E / 255, blue: 0x69 / 255),
        chipBackground: Color(red: 26 / 255, green: 28 / 255, blue: 34 / 255).opacity(0.73),
        chipBorder: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.12),
        chipText: Color(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255),
        secondaryButtonBackground: Color(red: 26 / 255, green: 28 / 255, blue: 34 / 255).opacity(0.73),
        playerPanelBackground: MacDesignTokens.Cinema.panelGlass,
        playerScrubberTrack: MacDesignTokens.Cinema.track,
        progressTrack: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.20),
        emptyDescriptionText: Color(red: 0xA8 / 255, green: 0xA5 / 255, blue: 0x9E / 255),
        emptyIconBackground: Color(red: 26 / 255, green: 28 / 255, blue: 34 / 255).opacity(0.73),
        emptyIconBorder: Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.12),
        dangerRed: Color(red: 0xFF / 255, green: 0x64 / 255, blue: 0x67 / 255),
        successGreen: Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    )

    static let emptyDark = dark
}

private struct MacThemeColorsKey: EnvironmentKey {
    static let defaultValue = MacThemeColors.dark
}

extension EnvironmentValues {
    var macTheme: MacThemeColors {
        get { self[MacThemeColorsKey.self] }
        set { self[MacThemeColorsKey.self] = newValue }
    }
}

extension View {
    func macTheme(_ theme: MacThemeColors) -> some View {
        environment(\.macTheme, theme)
    }
}
