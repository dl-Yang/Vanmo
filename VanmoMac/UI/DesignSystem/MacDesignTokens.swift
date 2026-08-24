import SwiftUI

/// macOS Figma 设计 token（Vanmo-MacOS fileKey: O75W1XT1Q0btSrepDwEx39）
enum MacDesignTokens {
    enum Layout {
        static let sidebarWidth: CGFloat = 256
        static let sidebarMinWidth: CGFloat = 240
        static let sidebarMaxWidth: CGFloat = 400
        /// 交通灯区域宽度，侧边栏顶部控件需从此处起排
        static let trafficLightsLeadingInset: CGFloat = 78
        static let trafficLightsTopInset: CGFloat = 8
        /// 顶部悬浮的展开/折叠控制行高度（顶部 2 + 按钮 28 + 底部 12），供侧边栏内容避让
        static let sidebarControlRowHeight: CGFloat = 42
        static let headerHeight: CGFloat = 56
        static let contentPadding: CGFloat = 24
        static let detailContentPadding: CGFloat = 40
        static let sidebarRowHeight: CGFloat = 32
        static let sidebarRowRadius: CGFloat = 8
        static let sidebarHorizontalPadding: CGFloat = 8
        static let sidebarItemPadding: CGFloat = 12
        static let filterPillHeight: CGFloat = 32
        static let continueWatchingWidth: CGFloat = 320
        static let continueWatchingThumbHeight: CGFloat = 180
        static let posterWidth: CGFloat = 174 * 0.7
        static let posterHeight: CGFloat = 261 * 0.7
        static let posterSpacing: CGFloat = 24
        static let heroHeight: CGFloat = 460
        static let heroLinearHeight: CGFloat = 200
        static let playerControlPanelWidth: CGFloat = 896
        static let playerControlPanelHeight: CGFloat = 124
        static let playerControlPanelRadius: CGFloat = 32
        static let addConnectionWidth: CGFloat = 720
        static let addConnectionHeight: CGFloat = 540
        static let addConnectionSidebarWidth: CGFloat = 220
        static let settingsSidebarWidth: CGFloat = 184
        static let settingsContentMaxWidth: CGFloat = 760
        static let settingsWindowWidth: CGFloat = 920
        static let settingsWindowHeight: CGFloat = 620
        static let addConnectionContentWidth: CGFloat = 500
        static let addConnectionRadius: CGFloat = 10
        static let downloadWidth: CGFloat = 96
        static let downloadHeight: CGFloat = 54
        static let downloadRowSpacing: CGFloat = 12
        static let downloadContentPadding: CGFloat = 20
    }

    enum Radius {
        static let searchField: CGFloat = 8
        static let segmentedControl: CGFloat = 8
        static let segmentedSegment: CGFloat = 6
        static let poster: CGFloat = 12
        static let continueWatching: CGFloat = 12
        static let downloadCard: CGFloat = 16
        static let downloadPoster: CGFloat = 10
        static let chip: CGFloat = 6
        static let circularButton: CGFloat = 20
        static let playButton: CGFloat = 22
    }

    enum Typography {
        static let headerTitle = Font.system(size: 18, weight: .semibold)
        static let sectionTitle = Font.system(size: 22, weight: .semibold)
        static let sidebarItem = Font.system(size: 14, weight: .medium)
        static let sidebarSection = Font.system(size: 12, weight: .semibold)
        static let filterPill = Font.system(size: 14, weight: .medium)
        static let cardTitle = Font.system(size: 18, weight: .semibold)
        static let cardSubtitle = Font.system(size: 14, weight: .regular)
        static let cardAction = Font.system(size: 15, weight: .semibold)
        static let detailHeroTitle = Font.system(size: 60, weight: .heavy)
        static let detailSectionTitle = Font.system(size: 22, weight: .semibold)
        static let playerTitle = Font.system(size: 20, weight: .semibold)
        static let playerTime = Font.system(size: 12, weight: .semibold)
    }

    static let accentBlue = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let ctaBlue = Color(red: 20 / 255, green: 92 / 255, blue: 255 / 255)
    static let ratingRed = Color(red: 255 / 255, green: 95 / 255, blue: 86 / 255)
}

struct MacThemeColors {
    let appBackground: Color
    let sidebarBackground: Color
    let sidebarBorder: Color
    let headerBackground: Color
    let headerBorder: Color
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

    static let light = MacThemeColors(
        appBackground: Color.white,
        sidebarBackground: Color.clear,
        sidebarBorder: Color.clear,
        headerBackground: Color.clear,
        headerBorder: Color.clear,
        primaryText: .black,
        secondaryText: Color(red: 54 / 255, green: 65 / 255, blue: 83 / 255),
        tertiaryText: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        sidebarItemText: Color(red: 54 / 255, green: 65 / 255, blue: 83 / 255),
        sidebarSelectedBackground: MacDesignTokens.accentBlue,
        sidebarSelectedText: .white,
        searchBackground: Color.black.opacity(0.05),
        searchBorder: .clear,
        searchPlaceholder: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        filterSelectedBackground: .black,
        filterSelectedText: .white,
        filterUnselectedBackground: Color.black.opacity(0.05),
        filterUnselectedText: Color(red: 54 / 255, green: 65 / 255, blue: 83 / 255),
        segmentedBackground: Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255),
        segmentedSelectedBackground: .white,
        cardSubtitle: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        sectionHeader: Color(red: 153 / 255, green: 161 / 255, blue: 175 / 255),
        chipBackground: Color.black.opacity(0.05),
        chipBorder: Color.black.opacity(0.08),
        chipText: Color(red: 54 / 255, green: 65 / 255, blue: 83 / 255),
        secondaryButtonBackground: Color.black.opacity(0.05),
        playerPanelBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.6),
        playerScrubberTrack: Color.white.opacity(0.2),
        progressTrack: Color.black.opacity(0.08),
        emptyDescriptionText: Color(red: 113 / 255, green: 113 / 255, blue: 123 / 255),
        emptyIconBackground: Color.white.opacity(0.6),
        emptyIconBorder: Color.black.opacity(0.05)
    )

    static let emptyDark = MacThemeColors(
        appBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
        sidebarBackground: Color.clear,
        sidebarBorder: Color.clear,
        headerBackground: Color.clear,
        headerBorder: Color.clear,
        primaryText: .white,
        secondaryText: Color(red: 153 / 255, green: 161 / 255, blue: 175 / 255),
        tertiaryText: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        sidebarItemText: Color(red: 153 / 255, green: 161 / 255, blue: 175 / 255),
        sidebarSelectedBackground: MacDesignTokens.ctaBlue,
        sidebarSelectedText: .white,
        searchBackground: Color.white.opacity(0.05),
        searchBorder: Color.white.opacity(0.05),
        searchPlaceholder: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        filterSelectedBackground: MacDesignTokens.ctaBlue,
        filterSelectedText: .white,
        filterUnselectedBackground: Color.white.opacity(0.08),
        filterUnselectedText: Color(red: 153 / 255, green: 161 / 255, blue: 175 / 255),
        segmentedBackground: Color(red: 21 / 255, green: 21 / 255, blue: 24 / 255),
        segmentedSelectedBackground: Color(red: 42 / 255, green: 42 / 255, blue: 46 / 255),
        cardSubtitle: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        sectionHeader: Color(red: 74 / 255, green: 85 / 255, blue: 101 / 255),
        chipBackground: Color.white.opacity(0.08),
        chipBorder: Color.white.opacity(0.12),
        chipText: Color(red: 153 / 255, green: 161 / 255, blue: 175 / 255),
        secondaryButtonBackground: Color.white.opacity(0.08),
        playerPanelBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.6),
        playerScrubberTrack: Color.white.opacity(0.2),
        progressTrack: Color.white.opacity(0.12),
        emptyDescriptionText: Color(red: 159 / 255, green: 159 / 255, blue: 169 / 255),
        emptyIconBackground: Color.white.opacity(0.05),
        emptyIconBorder: Color.white.opacity(0.1)
    )

    static let dark = MacThemeColors(
        appBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
        sidebarBackground: Color.clear,
        sidebarBorder: Color.clear,
        headerBackground: Color.clear,
        headerBorder: Color.clear,
        primaryText: .white,
        secondaryText: Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255),
        tertiaryText: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        sidebarItemText: Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255),
        sidebarSelectedBackground: MacDesignTokens.accentBlue,
        sidebarSelectedText: .white,
        searchBackground: Color.black.opacity(0.2),
        searchBorder: Color.white.opacity(0.1),
        searchPlaceholder: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        filterSelectedBackground: MacDesignTokens.accentBlue,
        filterSelectedText: .white,
        filterUnselectedBackground: Color.white.opacity(0.08),
        filterUnselectedText: Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255),
        segmentedBackground: Color.white.opacity(0.08),
        segmentedSelectedBackground: Color.white.opacity(0.12),
        cardSubtitle: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        sectionHeader: Color(red: 106 / 255, green: 114 / 255, blue: 130 / 255),
        chipBackground: Color.white.opacity(0.08),
        chipBorder: Color.white.opacity(0.12),
        chipText: Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255),
        secondaryButtonBackground: Color.white.opacity(0.08),
        playerPanelBackground: Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255).opacity(0.6),
        playerScrubberTrack: Color.white.opacity(0.2),
        progressTrack: Color.white.opacity(0.12),
        emptyDescriptionText: Color(red: 159 / 255, green: 159 / 255, blue: 169 / 255),
        emptyIconBackground: Color.white.opacity(0.05),
        emptyIconBorder: Color.white.opacity(0.1)
    )
}

private struct MacThemeColorsKey: EnvironmentKey {
    static let defaultValue = MacThemeColors.light
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
