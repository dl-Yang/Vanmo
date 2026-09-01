import SwiftUI
import VanmoCore

/// LibraryHome 空状态（Figma `Empty-Light` / `Empty-Dark`）
struct MacLibraryEmptyStateView: View {
    @Environment(\.macTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var onAddServer: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            iconGraphic
                .padding(.bottom, 32)

            Text(L10n.tr("没有找到媒体内容"))
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.81)
                .foregroundStyle(theme.primaryText)
                .padding(.bottom, 16)

            VStack(spacing: 0) {
                Text(L10n.tr("您的媒体库目前空空如也。"))
                    .font(.system(size: 14))
                    .tracking(-0.15)
                    .foregroundStyle(theme.emptyDescriptionText)
                    .multilineTextAlignment(.center)

                Text(L10n.tr("请先连接您的 NAS 或 Emby 服务器以同步您的媒体库内容。"))
                    .font(.system(size: 14))
                    .tracking(-0.15)
                    .foregroundStyle(theme.emptyDescriptionText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(.bottom, 32)

            Button(action: onAddServer) {
                HStack(spacing: 8) {
                    Text(L10n.tr("添加服务器"))
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.31)

                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 14)
                .background(MacDesignTokens.ctaBlue)
                .clipShape(Capsule())
                .shadow(color: MacDesignTokens.ctaBlue.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("添加服务器"))

            Spacer(minLength: 0)
        }
        .padding(.bottom, 80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconGraphic: some View {
        ZStack {
            Circle()
                .fill(MacDesignTokens.ctaBlue.opacity(colorScheme == .dark ? 0.2 : 0.1))
                .frame(width: 160, height: 160)
                .blur(radius: 40)

            ZStack {
                RoundedRectangle(cornerRadius: 40, style: .continuous)
                    .fill(theme.emptyIconBackground)
                    .frame(width: 140, height: 140)
                    .overlay {
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .stroke(theme.emptyIconBorder, lineWidth: 1)
                    }
                    .shadow(
                        color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.1),
                        radius: 12,
                        y: 10
                    )

                Image(systemName: "folder")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(MacDesignTokens.ctaBlue)
            }
            .rotationEffect(.degrees(3))
        }
        .frame(width: 160, height: 160)
    }
}

#Preview("Empty Light") {
    MacLibraryEmptyStateView()
        .macTheme(.light)
        .frame(width: 1214, height: 780)
        .background(Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255))
}

#Preview("Empty Dark") {
    MacLibraryEmptyStateView()
        .macTheme(.emptyDark)
        .frame(width: 1214, height: 780)
        .background(Color(red: 5 / 255, green: 6 / 255, blue: 8 / 255))
}
