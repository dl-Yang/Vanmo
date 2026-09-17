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
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .frame(maxWidth: 240)
    }
}
