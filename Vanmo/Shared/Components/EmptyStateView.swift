import SwiftUI
import VanmoCore

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let action: (() -> Void)?

    init(
        icon: String = "tray",
        title: String,
        message: String,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(CatDesign.accentAmber)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(CatDesign.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            if let action {
                Button(action: action) {
                    Text(L10n.tr("添加媒体源"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .catGlassCard(cornerRadius: CatDesign.radiusPill, elevated: true, amberStroke: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(
        icon: "film.stack",
        title: "暂无媒体",
        message: "添加网络共享或本地文件以开始浏览",
        action: {}
    )
    .background(CatDesign.bgObsidian)
    .preferredColorScheme(.dark)
}
