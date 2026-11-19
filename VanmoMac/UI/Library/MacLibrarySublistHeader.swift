import SwiftUI

struct MacLibrarySublistHeader: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme

    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Button {
                appState.backFromLibrarySubRoute()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 34, height: 34)
                    .background(theme.surfaceGlass, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacDesignTokens.Typography.headerTitle)
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            MacLibraryViewControls()
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
}
