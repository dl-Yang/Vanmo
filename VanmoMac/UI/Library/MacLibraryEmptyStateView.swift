import SwiftUI
import VanmoCore

struct MacLibraryEmptyStateView: View {
    @Environment(\.macTheme) private var theme

    var onAddServer: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(MacDesignTokens.glowAmber.opacity(theme.isDark ? 0.16 : 0.10))
                    .frame(width: 170, height: 170)
                    .blur(radius: 36)

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(theme.surfaceGlass)
                    .frame(width: 132, height: 132)
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(theme.strokeGlass, lineWidth: 1)
                    }

                Image("MacCatFolderCurious")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 76)
            }
            .padding(.bottom, 26)

            Text(L10n.tr("没有找到媒体内容"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .padding(.bottom, 10)

            Text(L10n.tr("您的媒体库目前空空如也。请先连接您的 NAS 或 Emby 服务器以同步您的媒体库内容。"))
                .font(.system(size: 13.5))
                .foregroundStyle(theme.emptyDescriptionText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.bottom, 26)

            Button(action: onAddServer) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text(L10n.tr("添加服务器"))
                        .font(.system(size: 13.5, weight: .bold))
                }
            }
            .buttonStyle(MacCatAmberButtonStyle(height: 42, horizontalPadding: 24))
            .help(L10n.tr("添加服务器"))

            Spacer(minLength: 0)
        }
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty Dark") {
    MacLibraryEmptyStateView()
        .macTheme(.dark)
        .frame(width: 1199, height: 800)
        .background(MacThemeColors.dark.appBackground)
}

#Preview("Empty Light") {
    MacLibraryEmptyStateView()
        .macTheme(.light)
        .frame(width: 1199, height: 800)
        .background(MacThemeColors.light.appBackground)
}
