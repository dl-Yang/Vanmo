import SwiftUI
import UIKit

/// Black Cat Redesign (`node-id: 656:2`) 全局设计令牌。
/// 夜间模式 100% 映射 Figma 变量（#0B0C0E + #FFB547）；日间模式基于 `14 · Appearance & Subtitles` 中的 Day Mode 卡片（#FAF7F2 + #E5DEC9）衍生并保证文本对比度 ≥ 4.5:1。
enum CatDesign {
    // MARK: - Dynamic Color Helper

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    // MARK: - Core Surfaces & Backgrounds

    /// 主画布底色：夜间 `#0B0C0E` / 日间 `#FAF7F2`
    static let bgObsidian = dynamic(
        light: rgba(0xFA, 0xF7, 0xF2),
        dark: rgba(0x0B, 0x0C, 0x0E)
    )

    /// 常规玻璃表面：夜间 `rgba(18,19,22,0.82)` / 日间 `rgba(255,255,255,0.86)`
    static let surfaceGlass = dynamic(
        light: rgba(255, 255, 255, 0.86),
        dark: rgba(18, 19, 22, 0.82)
    )

    /// 高阶悬浮玻璃表面（Tab Bar、Search Bar、Summary Card）：夜间 `rgba(26,28,33,0.88)` / 日间 `rgba(255,253,249,0.94)`
    static let surfaceGlassElevated = dynamic(
        light: rgba(255, 253, 249, 0.94),
        dark: rgba(26, 28, 33, 0.88)
    )

    /// 药丸/徽标弱填充：夜间 `rgba(244,239,230,0.09)` / 日间 `rgba(24,24,27,0.06)`
    static let surfacePill = dynamic(
        light: rgba(24, 24, 27, 0.06),
        dark: rgba(244, 239, 230, 0.09)
    )

    /// 次级列表行底色：夜间 `rgba(244,239,230,0.03)` / 日间 `rgba(24,24,27,0.03)`
    static let surfaceRowSubtle = dynamic(
        light: rgba(24, 24, 27, 0.03),
        dark: rgba(244, 239, 230, 0.03)
    )

    /// 详情面板/Modal 玻璃底色：夜间 `rgba(18,19,22,0.87)` / 日间 `rgba(250,247,242,0.93)`
    static let surfacePanel = dynamic(
        light: rgba(250, 247, 242, 0.93),
        dark: rgba(18, 19, 22, 0.87)
    )

    /// 弹窗底部 Sheet 面板底色：夜间 `rgba(18,19,22,0.92)` / 日间 `rgba(250,247,242,0.97)`
    static let surfaceSheet = dynamic(
        light: rgba(250, 247, 242, 0.97),
        dark: rgba(18, 19, 22, 0.92)
    )

    /// 媒体海报/缩略图占位底色
    static let mediaPlaceholder = dynamic(
        light: rgba(0xEB, 0xE5, 0xDA),
        dark: rgba(18, 19, 22, 0.90)
    )

    // MARK: - Typography Colors

    /// 主标题与正文：夜间 `#F4EFE6` / 日间 `#18181B`
    static let textIvory = dynamic(
        light: rgba(0x18, 0x18, 0x1B),
        dark: rgba(0xF4, 0xEF, 0xE6)
    )

    /// 次级描述文案：夜间 `#A8A59E` / 日间 `#57534E`
    static let textMuted = dynamic(
        light: rgba(0x57, 0x53, 0x4E),
        dark: rgba(0xA8, 0xA5, 0x9E)
    )

    /// 弱提示/分组眉标文案：夜间 `#72706B` / 日间 `#78716C`
    static let textDim = dynamic(
        light: rgba(0x78, 0x71, 0x6C),
        dark: rgba(0x72, 0x70, 0x6B)
    )

    // MARK: - Brand Amber & Cat Accents

    /// 主题琥珀强调色：夜间 `#FFB547` / 日间 `#B86A08`（保证暖米白底上的高可读对比度）
    static let accentAmber = dynamic(
        light: rgba(0xB8, 0x6A, 0x08),
        dark: rgba(0xFF, 0xB5, 0x47)
    )

    /// 纯粹发光琥珀金 `#FFB547`（用于进度条高亮、猫咪发光眼、深色播放器/灵动岛等）
    static let glowAmber = Color(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255)

    /// 琥珀微透底色（高亮卡片/按钮底）
    static let amberTintFill = dynamic(
        light: rgba(0xC8, 0x7A, 0x19, 0.12),
        dark: rgba(0xFF, 0xB5, 0x47, 0.12)
    )

    /// 琥珀较强透底色（Active Pill / 按钮）
    static let amberTintStrong = dynamic(
        light: rgba(0xC8, 0x7A, 0x19, 0.16),
        dark: rgba(0xFF, 0xB5, 0x47, 0.15)
    )

    /// 黑猫剪影实体黑 `#0A0A0C`
    static let catSilhouette = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0C / 255)

    /// 危险/删除/失败提示红
    static let dangerRed = dynamic(
        light: rgba(0xDC, 0x26, 0x26),
        dark: rgba(0xFF, 0x64, 0x67)
    )

    // MARK: - Strokes & Separators

    /// 玻璃描边：夜间 `rgba(244,239,230,0.14)` / 日间 `#E5DEC9`
    static let strokeGlass = dynamic(
        light: rgba(0xE5, 0xDE, 0xC9),
        dark: rgba(244, 239, 230, 0.14)
    )

    /// 弱描边（Standby 卡片 / 虚线框）：夜间 `rgba(244,239,230,0.08)` / 日间 `rgba(24,24,27,0.08)`
    static let strokeSubtle = dynamic(
        light: rgba(24, 24, 27, 0.08),
        dark: rgba(244, 239, 230, 0.08)
    )

    /// 琥珀描边：夜间 `rgba(255,181,71,0.45)` / 日间 `rgba(200,122,25,0.45)`
    static let strokeAmber = dynamic(
        light: rgba(0xC8, 0x7A, 0x19, 0.45),
        dark: rgba(0xFF, 0xB5, 0x47, 0.45)
    )

    /// 列表细分隔线
    static let hairSeparator = dynamic(
        light: rgba(24, 24, 27, 0.08),
        dark: rgba(244, 239, 230, 0.07)
    )

    /// 进度条底轨
    static let progressTrack = dynamic(
        light: rgba(24, 24, 27, 0.14),
        dark: rgba(244, 239, 230, 0.20)
    )

    /// 拖拽把手/Home 指示条颜色
    static let grabberFill = dynamic(
        light: rgba(24, 24, 27, 0.22),
        dark: rgba(244, 239, 230, 0.24)
    )

    // MARK: - Shadows & Glows

    static let cardShadow = dynamic(
        light: rgba(24, 24, 27, 0.08),
        dark: rgba(0, 0, 0, 0.60)
    )

    static let amberGlowShadow = dynamic(
        light: rgba(0xC8, 0x7A, 0x19, 0.14),
        dark: rgba(0xFF, 0xB5, 0x47, 0.16)
    )

    // MARK: - Corner Radii

    static let radiusSquircleLg: CGFloat = 24
    static let radiusSquircleMd: CGFloat = 16
    static let radiusSquircleSm: CGFloat = 12
    static let radiusSheetTop: CGFloat = 28
    static let radiusPill: CGFloat = 999
    static let horizontalMargin: CGFloat = 24

    // MARK: - Player & Dynamic Island Dark Constants (始终暗黑电影表面)

    enum Cinema {
        static let surfaceGlass = Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.82)
        static let surfaceGlassElevated = Color(red: 26 / 255, green: 28 / 255, blue: 33 / 255).opacity(0.88)
        static let surfacePill = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.09)
        static let textIvory = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
        static let textMuted = Color(red: 168 / 255, green: 165 / 255, blue: 158 / 255)
        static let textDim = Color(red: 114 / 255, green: 112 / 255, blue: 107 / 255)
        static let strokeGlass = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.14)
        static let strokeAmber = Color(red: 255 / 255, green: 181 / 255, blue: 71 / 255).opacity(0.45)
        static let track = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.20)
        static let amber = glowAmber
        static let islandShell = Color(red: 5 / 255, green: 5 / 255, blue: 7 / 255)
    }
}
