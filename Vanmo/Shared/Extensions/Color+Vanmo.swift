import SwiftUI

extension Color {
    static let vanmoPrimary = Color.orange
    static let vanmoBackground = Color(.systemBackground)
    static let vanmoSurface = Color(.secondarySystemBackground)
    static let vanmoOnSurface = Color(.label)
    static let vanmoSubtext = Color(.secondaryLabel)
    static let vanmoOverlay = Color.black.opacity(0.6)
}

extension LinearGradient {
    static let posterOverlay = LinearGradient(
        colors: [.clear, .black.opacity(0.8)],
        startPoint: .center,
        endPoint: .bottom
    )

    static let headerOverlay = LinearGradient(
        colors: [.clear, .clear, .black.opacity(0.9)],
        startPoint: .top,
        endPoint: .bottom
    )
}
