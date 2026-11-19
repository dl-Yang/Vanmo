import Kingfisher
import SwiftUI

struct MacDownloadHeroOverlay: View {
    @EnvironmentObject private var hero: MacDownloadHeroController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if hero.isFlying {
                    MacDownloadHeroCapsule(title: hero.title, posterURL: hero.posterURL)
                        .scaleEffect(hero.capsuleScale)
                        .opacity(hero.capsuleOpacity)
                        .position(MacDownloadHeroLayout.localPoint(hero.capsuleCenter, in: geo.frame(in: .global)))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onReceive(NotificationCenter.default.publisher(for: .macDownloadHeroRequested)) { notification in
            guard let request = notification.object as? MacDownloadHeroRequest else { return }
            hero.requestFlight(
                title: request.title,
                posterURL: request.posterURL,
                reduceMotion: reduceMotion
            )
        }
    }
}

private struct MacDownloadHeroCapsule: View {
    let title: String
    let posterURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let posterURL {
                    KFImage(posterURL)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image("MacDownloadsTray")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                        .foregroundStyle(MacDesignTokens.glowAmber)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(MacDesignTokens.Cinema.textIvory)
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(MacDesignTokens.Cinema.panelGlass, in: Capsule())
        .overlay(Capsule().strokeBorder(MacDesignTokens.Cinema.strokeAmber, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .frame(maxWidth: 240)
    }
}
