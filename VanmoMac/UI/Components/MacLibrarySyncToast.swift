import SwiftUI
import VanmoCore

struct MacLibrarySyncToast: View {
    @Environment(\.macTheme) private var theme

    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(MacDesignTokens.accentBlue)
                .symbolEffect(.bounce, value: message)

            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(theme.sidebarBorder.opacity(0.6), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}
