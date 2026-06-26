import SwiftUI
import Kingfisher

struct MediaTitleLogoView: View {
    let title: String
    let logoURL: URL?
    var titleFont: Font = .system(size: 28, weight: .bold)
    var collapsedStyle: Bool = false
    var maxLogoHeight: CGFloat = 72

    @State private var isLogoLoaded = false
    @State private var displayedLogoURL: URL?

    var body: some View {
        ZStack(alignment: .center) {
            Text(displayTitle)
                .font(collapsedStyle ? .system(size: 36, weight: .black, design: .rounded) : titleFont)
                .kerning(collapsedStyle ? -0.5 : 0)
                .multilineTextAlignment(.center)
                .foregroundStyle(collapsedStyle ? .white : .primary)
                .shadow(color: collapsedStyle ? .black.opacity(0.35) : .clear, radius: collapsedStyle ? 18 : 0, y: collapsedStyle ? 8 : 0)
                .frame(maxWidth: .infinity, alignment: .center)
                .opacity(isLogoLoaded ? 0 : 1)

            if let currentLogoURL = displayedLogoURL ?? logoURL {
                KFImage(currentLogoURL)
                    .onSuccess { _ in
                        displayedLogoURL = currentLogoURL
                        withAnimation(.easeOut(duration: 0.35)) {
                            isLogoLoaded = true
                        }
                    }
                    .onFailure { _ in
                        if displayedLogoURL == nil {
                            isLogoLoaded = false
                        }
                    }
                    .fade(duration: 0.35)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxLogoHeight, alignment: .center)
                    .opacity(isLogoLoaded ? 1 : 0)
            }

            if let logoURL, logoURL != displayedLogoURL {
                KFImage(logoURL)
                    .onSuccess { _ in
                        displayedLogoURL = logoURL
                        withAnimation(.easeOut(duration: 0.2)) {
                            isLogoLoaded = true
                        }
                    }
                    .onFailure { _ in
                        if displayedLogoURL == nil {
                            isLogoLoaded = false
                        }
                    }
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: maxLogoHeight, alignment: .center)
                    .opacity(0.001)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: logoURL) { _, newLogoURL in
            if newLogoURL == nil {
                displayedLogoURL = nil
                isLogoLoaded = false
            }
        }
    }

    private var displayTitle: String {
        collapsedStyle ? title.uppercased() : title
    }
}

#Preview {
    VStack(spacing: 24) {
        MediaTitleLogoView(
            title: "DUNE: PART TWO",
            logoURL: nil
        )
        MediaTitleLogoView(
            title: "Breaking Bad",
            logoURL: nil,
            collapsedStyle: true
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
