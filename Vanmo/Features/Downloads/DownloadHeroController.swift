import SwiftUI

@MainActor
final class DownloadHeroController: ObservableObject {
    static let shared = DownloadHeroController()

    @Published private(set) var isFlying = false
    @Published private(set) var title = ""
    @Published private(set) var posterURL: URL?
    @Published var sourceFrame: CGRect = .zero
    @Published var destinationFrame: CGRect = .zero
    @Published var capsuleCenter: CGPoint = .zero
    @Published var capsuleScale: CGFloat = 1
    @Published var capsuleSize = CGSize(width: 180, height: 36)
    @Published var capsuleOpacity: Double = 0
    @Published var morphProgress: CGFloat = 0
    @Published var destinationScale: CGFloat = 1
    @Published private(set) var revealsDestinationChrome = true
    @Published private(set) var landedAt: Date?

    var showsDestinationChrome: Bool {
        revealsDestinationChrome || !isFlying
    }

    private var playTask: Task<Void, Never>?

    func requestFlight(title: String, posterURL: URL?, reduceMotion: Bool) {
        playTask?.cancel()
        self.title = title
        self.posterURL = posterURL
        destinationScale = 1
        capsuleScale = 1
        capsuleSize = DownloadIslandCapability.estimatedHeroCapsuleSize(title: title)
        morphProgress = 0
        revealsDestinationChrome = false
        landedAt = nil
        isFlying = true

        guard !reduceMotion, sourceFrame.width > 1 else {
            revealsDestinationChrome = true
            isFlying = false
            landedAt = Date()
            return
        }

        playTask = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<8 where self.destinationFrame.width <= 1 {
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            guard !Task.isCancelled else { return }
            let start = self.sourceFrame
            let dest = self.resolvedDestination
#if DEBUG
            print("[Debug][Downloads] hero dest=\(Int(dest.width))x\(Int(dest.height)) y=\(Int(dest.minY)) source=\(Int(start.midX)),\(Int(start.midY))")
#endif
            self.capsuleOpacity = 1
            self.capsuleCenter = CGPoint(x: start.midX, y: start.midY)
            let detach = CGPoint(x: start.midX + 10, y: start.midY + 14)
            await self.animate(.spring(response: 0.28, dampingFraction: 0.86), duration: 0.32) {
                self.capsuleCenter = detach
            }
            guard !Task.isCancelled else { return }
            await self.animate(.spring(response: 0.50, dampingFraction: 0.78), duration: 0.56) {
                self.capsuleCenter = CGPoint(x: dest.midX, y: dest.midY)
            }
            guard !Task.isCancelled else { return }
            if DownloadIslandCapability.hasDynamicIsland {
                await self.playIslandMorph(island: dest)
            } else {
                await self.playFallbackLanding()
            }
        }
    }

    private func playIslandMorph(island: CGRect) async {
        let aligned = CGSize(
            width: island.width > 1 ? island.width : DownloadIslandCapability.islandWidth,
            height: island.height > 1 ? island.height : DownloadIslandCapability.islandHeight
        )
        let compact = CGSize(
            width: DownloadIslandCapability.compactWidth,
            height: DownloadIslandCapability.compactHeight
        )
        await animate(DownloadIslandMotion.dismiss, duration: 0.36) {
            self.capsuleSize = aligned
            self.capsuleCenter = DownloadIslandCapability.topAlignedCenter(for: aligned, in: island)
        }
        guard !Task.isCancelled else { return }
        await animate(DownloadIslandMotion.appear, duration: 0.50) {
            self.capsuleSize = compact
            self.capsuleCenter = DownloadIslandCapability.topAlignedCenter(for: compact, in: island)
            self.morphProgress = 1
        }
        guard !Task.isCancelled else { return }
        finishFlight(revealChrome: true)
    }

    private func playFallbackLanding() async {
        await animate(.spring(response: 0.26, dampingFraction: 0.42), duration: 0.30) {
            self.capsuleScale = 1.10
        }
        guard !Task.isCancelled else { return }
        await animate(.spring(response: 0.28, dampingFraction: 0.62), duration: 0.32) {
            self.capsuleScale = 1
        }
        guard !Task.isCancelled else { return }
        revealsDestinationChrome = true
        await animate(.easeOut(duration: 0.22), duration: 0.22) {
            self.capsuleOpacity = 0
            self.capsuleScale = 0.22
            self.destinationScale = 1.06
        }
        guard !Task.isCancelled else { return }
        await animate(.spring(response: 0.30, dampingFraction: 0.70), duration: 0.34) {
            self.destinationScale = 1
        }
        guard !Task.isCancelled else { return }
        finishFlight(revealChrome: true)
    }

    private func finishFlight(revealChrome: Bool) {
        if revealChrome {
            revealsDestinationChrome = true
        }
        if DownloadIslandCapability.hasDynamicIsland, destinationFrame.width > 1 {
            let compact = CGSize(
                width: DownloadIslandCapability.compactWidth,
                height: DownloadIslandCapability.compactHeight
            )
            capsuleSize = compact
            capsuleCenter = DownloadIslandCapability.topAlignedCenter(for: compact, in: destinationFrame)
        }
        isFlying = false
        landedAt = Date()
        capsuleScale = 1
        capsuleOpacity = 0
        morphProgress = 0
        destinationScale = 1
    }

    private var resolvedDestination: CGRect {
        destinationFrame.width > 1 ? destinationFrame : sourceFrame
    }

    private func animate(
        _ animation: Animation,
        duration: TimeInterval,
        _ updates: @escaping () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            withAnimation(animation) {
                updates()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                continuation.resume()
            }
        }
    }
}

enum DownloadHeroLayout {
    static func localPoint(_ global: CGPoint, in globalFrame: CGRect) -> CGPoint {
        CGPoint(x: global.x - globalFrame.minX, y: global.y - globalFrame.minY)
    }
}

enum DownloadHeroFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func downloadHeroFrame(_ id: String) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: DownloadHeroFrameKey.self,
                    value: [id: geo.frame(in: .global)]
                )
            }
        }
    }
}
