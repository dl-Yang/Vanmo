import SwiftUI
import VanmoCore

// MARK: - Tab Bar Visibility Preference

struct CatTabBarHiddenPreferenceKey: PreferenceKey {
    static var defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func catTabBarHidden(_ hidden: Bool = true) -> some View {
        preference(key: CatTabBarHiddenPreferenceKey.self, value: hidden)
    }
}

// MARK: - Liquid Glass Surface Helper

extension View {
    @ViewBuilder
    func catLiquidGlass<S: InsettableShape>(
        in shape: S,
        tint: Color,
        fallbackFill: Color? = nil,
        stroke: Color,
        strokeWidth: CGFloat = 1,
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background {
                    shape
                        .fill(Color.clear)
                        .glassEffect(
                            interactive ? .regular.tint(tint).interactive() : .regular.tint(tint),
                            in: shape
                        )
                }
                .overlay {
                    shape.strokeBorder(stroke, lineWidth: strokeWidth)
                }
        } else {
            self
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(fallbackFill ?? tint))
                }
                .overlay {
                    shape.strokeBorder(stroke, lineWidth: strokeWidth)
                }
        }
    }
}

// MARK: - Floating Cat Glass Tab Bar

struct CatGlassTabBar: View {
    @Binding var selectedTab: AppTab
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var activePillNamespace

    var body: some View {
        tabItemsRow
            .padding(6)
            .frame(maxWidth: 366)
            .frame(height: 68)
            .catLiquidGlass(
                in: Capsule(),
                tint: barTint,
                fallbackFill: barFallbackFill,
                stroke: barStroke,
                strokeWidth: 1
            )
            .shadow(
                color: colorScheme == .dark
                    ? Color.black.opacity(0.60)
                    : Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.16),
                radius: 13,
                y: 12
            )
            .padding(.horizontal, 12)
    }

    private var tabItemsRow: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                tabItemButton(for: tab)
            }
        }
    }

    private func tabItemButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            guard selectedTab != tab else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.80)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: isSelected ? 2 : 3) {
                Image(tab.lgIconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? CatDesign.accentAmber : inactiveColor)

                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CatDesign.accentAmber : inactiveColor)
                    .lineLimit(1)

                if isSelected {
                    Image("CatPawDot")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 9)
                        .foregroundStyle(CatDesign.accentAmber)
                        .shadow(
                            color: colorScheme == .dark
                                ? CatDesign.glowAmber.opacity(0.85)
                                : CatDesign.accentAmber.opacity(0.40),
                            radius: 2.5
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if isSelected {
                    activePillBackground
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.accessibilityID)
    }

    private var activePillBackground: some View {
        Capsule()
            .fill(activePillSecondaryTint)
            .overlay(Capsule().fill(activePillTint))
            .overlay(Capsule().strokeBorder(activePillStroke, lineWidth: 1))
            .shadow(color: activePillShadow, radius: 12, y: 4)
            .matchedGeometryEffect(id: "activeTabPill", in: activePillNamespace)
    }

    private var barTint: Color {
        colorScheme == .dark
            ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.21)
            : Color.white.opacity(0.25)
    }

    private var barFallbackFill: Color {
        colorScheme == .dark
            ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.45)
            : Color.white.opacity(0.55)
    }

    private var barStroke: Color {
        colorScheme == .dark
            ? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.40)
            : Color.white.opacity(0.90)
    }

    private var activePillTint: Color {
        colorScheme == .dark
            ? Color(red: 255 / 255, green: 181 / 255, blue: 71 / 255).opacity(0.141)
            : Color.white.opacity(0.451)
    }

    private var activePillSecondaryTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.078)
            : Color(red: 184 / 255, green: 106 / 255, blue: 8 / 255).opacity(0.11)
    }

    private var activePillStroke: Color {
        colorScheme == .dark
            ? Color(red: 255 / 255, green: 181 / 255, blue: 71 / 255).opacity(0.60)
            : Color.white.opacity(0.95)
    }

    private var activePillShadow: Color {
        colorScheme == .dark
            ? Color(red: 255 / 255, green: 181 / 255, blue: 71 / 255).opacity(0.22)
            : Color(red: 184 / 255, green: 106 / 255, blue: 8 / 255).opacity(0.14)
    }

    private var inactiveColor: Color {
        colorScheme == .dark
            ? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.65)
            : Color(red: 24 / 255, green: 24 / 255, blue: 27 / 255).opacity(0.60)
    }
}

private extension AppTab {
    var lgIconAssetName: String {
        switch self {
        case .library: return "CatLGTabLibrary"
        case .connections: return "CatLGTabFiles"
        case .search: return "CatLGTabSearch"
        case .settings: return "CatLGTabSettings"
        }
    }

    var accessibilityID: String {
        switch self {
        case .library: return "tab.library"
        case .connections: return "tab.connections"
        case .search: return "tab.search"
        case .settings: return "tab.settings"
        }
    }
}

struct CatBottomBarScrim: View {
    var height: CGFloat = 114

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: CatDesign.bgObsidian.opacity(0), location: 0),
                .init(color: CatDesign.bgObsidian.opacity(0.55), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: - Ambient Amber Halo

struct CatAmberHalo: View {
    var width: CGFloat = 180
    var height: CGFloat = 110
    var opacity: Double = 0.22
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        CatDesign.glowAmber.opacity(colorScheme == .dark ? opacity : opacity * 0.65),
                        CatDesign.glowAmber.opacity(0)
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: max(width, height) * 0.55
                )
            )
            .frame(width: width, height: height)
            .blur(radius: 26)
            .allowsHitTesting(false)
    }
}

// MARK: - Glass Card & Pill Modifiers

struct CatGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = CatDesign.radiusSquircleMd
    var elevated: Bool = false
    var amberStroke: Bool = false
    var strokeWidth: CGFloat = 1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(elevated ? CatDesign.surfaceGlassElevated : CatDesign.surfaceGlass))
            }
            .overlay(
                shape.strokeBorder(amberStroke ? CatDesign.strokeAmber : CatDesign.strokeGlass, lineWidth: strokeWidth)
            )
            .clipShape(shape)
    }
}

extension View {
    func catGlassCard(
        cornerRadius: CGFloat = CatDesign.radiusSquircleMd,
        elevated: Bool = false,
        amberStroke: Bool = false,
        strokeWidth: CGFloat = 1
    ) -> some View {
        modifier(CatGlassCardModifier(
            cornerRadius: cornerRadius,
            elevated: elevated,
            amberStroke: amberStroke,
            strokeWidth: strokeWidth
        ))
    }
}

// MARK: - Cat Paw Progress Bar

struct CatPawProgressBar: View {
    let progress: Double
    var trackHeight: CGFloat = 3
    var showPawDot: Bool = true
    var isPaused: Bool = false
    var trackColor: Color = CatDesign.progressTrack

    private var clamped: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fillWidth = max(trackHeight, width * clamped)
            let dotOffset = min(max(fillWidth - 6, 0), max(width - 12, 0))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)
                    .frame(height: trackHeight)

                Capsule()
                    .fill(isPaused ? CatDesign.textMuted : CatDesign.glowAmber)
                    .frame(width: fillWidth, height: trackHeight)

                if showPawDot {
                    Image("CatPawDot")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(isPaused ? CatDesign.textMuted : CatDesign.glowAmber)
                        .shadow(color: isPaused ? .clear : CatDesign.glowAmber.opacity(0.85), radius: 2.5)
                        .offset(x: dotOffset)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: showPawDot ? 12 : trackHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - Badges & Decorative Icons

struct CatWatchedEarBadge: View {
    var padding: CGFloat = 4

    var body: some View {
        Image("CatEarCheck")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .padding(padding)
            .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
            .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeAmber, lineWidth: 0.75))
    }
}

struct CatSleepingPillBadge: View {
    var body: some View {
        Image("CatSleepingBadge")
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 18)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(CatDesign.Cinema.surfaceGlass, in: Capsule())
            .overlay(Capsule().strokeBorder(CatDesign.Cinema.strokeAmber, lineWidth: 0.75))
    }
}

struct CatStretchingDivider: View {
    var tint: Color = CatDesign.textMuted

    var body: some View {
        Image("CatStretchingDivider")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 38, height: 16)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }
}

struct CatBackButton: View {
    var size: CGFloat = 36
    var cinemaStyle: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(cinemaStyle ? CatDesign.Cinema.textIvory : CatDesign.textIvory)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().fill(cinemaStyle ? CatDesign.Cinema.surfaceGlass : CatDesign.surfaceGlass)
                        )
                }
                .overlay(
                    Circle().strokeBorder(
                        cinemaStyle ? CatDesign.Cinema.strokeGlass : CatDesign.strokeGlass,
                        lineWidth: 1
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tr("返回"))
    }
}

// MARK: - Filter Chip & Sync Toast

struct CatFilterChipPill: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isActive {
                    Image("CatPawDot")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(CatDesign.accentAmber)
                        .shadow(color: CatDesign.glowAmber.opacity(0.65), radius: 2)
                }

                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? CatDesign.accentAmber : CatDesign.textMuted)
                    .lineLimit(1)
            }
            .padding(.leading, isActive ? 10 : 13)
            .padding(.trailing, 13)
            .frame(height: 32)
            .background(isActive ? CatDesign.amberTintFill : CatDesign.surfaceGlass, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isActive ? CatDesign.strokeAmber : CatDesign.strokeGlass,
                        lineWidth: isActive ? 1 : 0.85
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct CatSyncToastPill: View {
    enum StateKind {
        case syncing
        case synced
    }

    let kind: StateKind
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            if kind == .syncing {
                Image("CatEyeBlink")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 10)
                    .shadow(color: CatDesign.glowAmber.opacity(0.8), radius: 2.5)
            } else {
                Image("CatEarCheck")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            }

            Text(message)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
                .lineLimit(1)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .frame(height: 38)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(CatDesign.surfaceGlassElevated))
        }
        .overlay(
            Capsule().strokeBorder(
                kind == .syncing ? CatDesign.strokeAmber : CatDesign.strokeGlass,
                lineWidth: 1
            )
        )
        .shadow(color: CatDesign.cardShadow, radius: 11, y: 8)
    }
}

// MARK: - Preview

#Preview("TabBar & Components") {
    ZStack(alignment: .bottom) {
        CatDesign.bgObsidian.ignoresSafeArea()
        VStack(spacing: 24) {
            CatSyncToastPill(kind: .syncing, message: "Syncing Library...")
            CatSyncToastPill(kind: .synced, message: "Synced · 3 Servers")
            HStack(spacing: 8) {
                CatFilterChipPill(title: "All", isActive: false) {}
                CatFilterChipPill(title: "Movies", isActive: true) {}
            }
            CatPawProgressBar(progress: 0.64)
                .frame(width: 240)
            Spacer()
            CatGlassTabBar(selectedTab: .constant(.library))
        }
        .padding(.top, 40)
    }
    .preferredColorScheme(.dark)
}
