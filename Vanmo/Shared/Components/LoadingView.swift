import SwiftUI
import VanmoCore

struct LoadingView: View {
    let message: String

    init(_ message: String = L10n.tr("加载中...")) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 14) {
            LoadingIndicatorView()
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CatDesign.textIvory)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 260)
        .catGlassCard(cornerRadius: 22, elevated: true, amberStroke: true)
        .shadow(color: CatDesign.cardShadow, radius: 18, y: 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LoadingView()
        .background(CatDesign.bgObsidian)
        .preferredColorScheme(.dark)
}
