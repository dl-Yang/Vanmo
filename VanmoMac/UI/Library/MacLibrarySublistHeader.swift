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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MacDesignTokens.Typography.headerTitle)
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer()

            MacHeaderToolbar(title: title, showsTitle: false, showsControlsOnly: true)
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .frame(height: MacDesignTokens.Layout.headerHeight)
        .background(theme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.headerBorder).frame(height: 1)
        }
    }
}
