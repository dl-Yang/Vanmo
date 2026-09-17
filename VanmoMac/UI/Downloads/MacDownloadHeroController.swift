import SwiftUI

@MainActor
final class MacDownloadHeroController: ObservableObject {
    static let shared = MacDownloadHeroController()

    @Published private(set) var isFlying = false
    @Published private(set) var title = ""
    @Published private(set) var posterURL: URL?
    @Published var sourceFrame: CGRect = .zero
    @Published var destinationFrame: CGRect = .zero
    @Published var capsuleCenter: CGPoint = .zero
    @Published var capsuleScale: CGFloat = 1
    @Published var capsuleOpacity: Double = 0
    @Published var destinationScale: CGFloat = 1

    private var playTask: Task<Void, Never>?

    func requestFlight(title: String, posterURL: URL?, reduceMotion: Bool) {
        playTask?.cancel()
        self.title = title
        self.posterURL = posterURL
        destinationScale = 1
        capsuleScale = 1

        guard !reduceMotion, sourceFrame.width > 1, destinationFrame.width > 1 else { return }

        let start = sourceFrame
        let dest = destinationFrame
        isFlying = true
        capsuleOpacity = 1
        capsuleCenter = CGPoint(x: start.midX, y: start.midY)

        playTask = Task { [weak self] in
            guard let self else { return }
            let detach = CGPoint(x: start.midX + 12, y: start.midY + 10)
            await self.animate(.spring(response: 0.28, dampingFraction: 0.86)) {
                self.capsuleCenter = detach
            }
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard !Task.isCancelled else { return }
            await self.animate(.spring(response: 0.50, dampingFraction: 0.78)) {
                self.capsuleCenter = CGPoint(x: dest.midX, y: dest.midY)
            }
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard !Task.isCancelled else { return }
            await self.animate(.spring(response: 0.28, dampingFraction: 0.45)) {
                self.destinationScale = 1.22
                self.capsuleScale = 0.16
                self.capsuleOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await self.animate(.spring(response: 0.32, dampingFraction: 0.62)) {
                self.destinationScale = 1
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            self.isFlying = false
            self.capsuleScale = 1
            self.capsuleOpacity = 0
            self.destinationScale = 1
        }
    }

    private func animate(_ animation: Animation, _ updates: @escaping () -> Void) async {
        await withCheckedContinuation { continuation in
            withAnimation(animation) {
                updates()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                continuation.resume()
            }
        }
    }

    static func request(title: String, posterURL: URL?) {
        NotificationCenter.default.post(
            name: .macDownloadHeroRequested,
            object: MacDownloadHeroRequest(title: title, posterURL: posterURL)
        )
    }
}

struct MacDownloadHeroRequest {
    let title: String
    let posterURL: URL?
}

extension Notification.Name {
    static let macDownloadHeroRequested = Notification.Name("vanmo.macDownloadHeroRequested")
}

enum MacDownloadHeroLayout {
    static func localPoint(_ global: CGPoint, in globalFrame: CGRect) -> CGPoint {
        CGPoint(x: global.x - globalFrame.minX, y: global.y - globalFrame.minY)
    }
}

enum MacDownloadHeroFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func macDownloadHeroFrame(_ id: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: MacDownloadHeroFrameKey.self,
                    value: [id: geo.frame(in: .global)]
                )
            }
        }
    }
}
