import SwiftUI
import VanmoCore

// MARK: - Ambient Amber Halo

struct MacCatAmbientHalo: View {
    @Environment(\.macTheme) private var theme

    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        MacDesignTokens.glowAmber.opacity(theme.isDark ? 0.16 : 0.10),
                        MacDesignTokens.glowAmber.opacity(0.0),
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 190
                )
            )
            .frame(width: 380, height: 220)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Paw Dot Indicator

struct MacPawDotIndicator: View {
    @Environment(\.macTheme) private var theme
    var size: CGFloat = 10
    var useCinemaGlow: Bool = false

    var body: some View {
        Image("MacPawDot")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(useCinemaGlow ? MacDesignTokens.glowAmber : theme.accentAmber)
            .shadow(color: MacDesignTokens.glowAmber.opacity(0.8), radius: 2.5)
            .accessibilityHidden(true)
    }
}

// MARK: - Sleeping Cat Watched Pill

struct MacSleepingCatWatchedPill: View {
    @Environment(\.macTheme) private var theme

    var body: some View {
        Image("MacSleepingCatBadge")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 16)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 0.75)
            )
            .accessibilityLabel(L10n.tr("已看完"))
    }
}

// MARK: - Amber Progress Track with Paw Dot

struct MacCatProgressTrack: View {
    @Environment(\.macTheme) private var theme

    let progress: Double
    var trackColor: Color?
    var fillColor: Color = MacDesignTokens.glowAmber
    var height: CGFloat = 3
    var showsPawThumb: Bool = true
    var pawSize: CGFloat = 10

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fillWidth = max(clampedProgress > 0 ? 4 : 0, width * clampedProgress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor ?? Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.21))
                    .frame(height: height)

                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth, height: height)

                if showsPawThumb && clampedProgress > 0 {
                    MacPawDotIndicator(size: pawSize, useCinemaGlow: true)
                        .offset(x: min(max(fillWidth - pawSize / 2, 0), max(0, width - pawSize)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: max(height, showsPawThumb ? pawSize : height))
    }
}

// MARK: - Section Header with Stretching Cat & See All

struct MacCatSectionHeaderRow: View {
    @Environment(\.macTheme) private var theme

    let title: String
    var badgeText: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var showsStretchingCat: Bool = true

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(MacDesignTokens.Typography.sectionTitle)
                .foregroundStyle(theme.primaryText)

            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Spacer(minLength: 8)

            HStack(spacing: 10) {
                if showsStretchingCat {
                    Image("MacStretchingCat")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 14)
                        .foregroundStyle(theme.secondaryText.opacity(0.75))
                        .accessibilityHidden(true)
                }

                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(spacing: 3) {
                            Text(actionTitle)
                            Text("›")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isHovered ? theme.accentAmber : theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering && !isHovered {
                            NSCursor.pointingHand.push()
                        } else if !hovering && isHovered {
                            NSCursor.pop()
                        }
                        isHovered = hovering
                    }
                    .onDisappear {
                        if isHovered {
                            NSCursor.pop()
                            isHovered = false
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Button Styles

struct MacCatAmberButtonStyle: ButtonStyle {
    var height: CGFloat = 38
    var horizontalPadding: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(MacDesignTokens.catSilhouette)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .background(
                MacDesignTokens.glowAmber.opacity(configuration.isPressed ? 0.86 : 1),
                in: Capsule()
            )
            .shadow(color: MacDesignTokens.glowAmber.opacity(0.18), radius: 8, y: 4)
    }
}

struct MacCatAmberGlassButtonStyle: ButtonStyle {
    var height: CGFloat = 46
    var horizontalPadding: CGFloat = 22

    func makeBody(configuration: Configuration) -> some View {
        BodyView(configuration: configuration, height: height, horizontalPadding: horizontalPadding)
    }

    private struct BodyView: View {
        @Environment(\.macTheme) private var theme
        let configuration: Configuration
        let height: CGFloat
        let horizontalPadding: CGFloat

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accentAmber)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background(
                    theme.amberTintStrong.opacity(configuration.isPressed ? 0.75 : 1),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(theme.strokeAmber, lineWidth: 1.2)
                )
                .shadow(color: MacDesignTokens.glowAmber.opacity(0.16), radius: 10, y: 4)
        }
    }
}

struct MacCatGlassButtonStyle: ButtonStyle {
    var height: CGFloat = 38
    var horizontalPadding: CGFloat = 16
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        BodyView(
            configuration: configuration,
            height: height,
            horizontalPadding: horizontalPadding,
            isActive: isActive
        )
    }

    private struct BodyView: View {
        @Environment(\.macTheme) private var theme
        let configuration: Configuration
        let height: CGFloat
        let horizontalPadding: CGFloat
        let isActive: Bool

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(isActive ? theme.accentAmber : theme.primaryText)
                .padding(.horizontal, horizontalPadding)
                .frame(height: height)
                .background(
                    (isActive ? theme.amberTintFill : theme.surfaceGlass)
                        .opacity(configuration.isPressed ? 0.82 : 1),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isActive ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.9)
                )
        }
    }
}

// MARK: - Glass Surface Helper

extension View {
    func macCatGlassCard(
        theme: MacThemeColors,
        cornerRadius: CGFloat = MacDesignTokens.Radius.poster,
        isHighlighted: Bool = false
    ) -> some View {
        self
            .background(
                isHighlighted ? theme.amberTintFill : theme.surfaceGlass,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? theme.strokeAmber : theme.strokeGlass,
                        lineWidth: isHighlighted ? 1.15 : 0.9
                    )
            )
    }
}

// MARK: - Previews

#Preview("Cat UI Components Dark") {
    VStack(spacing: 18) {
        MacCatSectionHeaderRow(
            title: "Continue Watching",
            badgeText: "Emby · NAS · 142 Titles",
            actionTitle: "See All"
        ) {}

        MacCatProgressTrack(progress: 0.62)
            .frame(width: 240)

        HStack(spacing: 12) {
            Button("Play Movie") {}
                .buttonStyle(MacCatAmberButtonStyle())
            Button("Inspect Details") {}
                .buttonStyle(MacCatGlassButtonStyle())
            Button("Play Now") {}
                .buttonStyle(MacCatAmberGlassButtonStyle())
        }
    }
    .padding(24)
    .background(MacThemeColors.dark.appBackground)
    .macTheme(.dark)
}

#Preview("Cat UI Components Light") {
    VStack(spacing: 18) {
        MacCatSectionHeaderRow(
            title: "Continue Watching",
            badgeText: "Emby · NAS · 142 Titles",
            actionTitle: "See All"
        ) {}

        MacCatProgressTrack(progress: 0.62, trackColor: MacThemeColors.light.progressTrack)
            .frame(width: 240)

        HStack(spacing: 12) {
            Button("Play Movie") {}
                .buttonStyle(MacCatAmberButtonStyle())
            Button("Inspect Details") {}
                .buttonStyle(MacCatGlassButtonStyle())
            Button("Play Now") {}
                .buttonStyle(MacCatAmberGlassButtonStyle())
        }
    }
    .padding(24)
    .background(MacThemeColors.light.appBackground)
    .macTheme(.light)
}
