import SwiftUI
import UIKit
import VanmoCore

struct PlayerProgressBar: View {
    let progress: Double
    let cacheStart: Double
    let cacheEnd: Double
    @Binding var isSeeking: Bool
    let onScrub: (Double?) -> Void
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double = 0
    @State private var pendingSeekProgress: Double?
    @State private var settleSeekTask: Task<Void, Never>?
    @State private var lastHapticStep: Int?
    /// 系统取消手势（来电、控制中心）时不会调 `onEnded`，靠它把 `isSeeking` 复位。
    @GestureState private var isDragging = false

    private let hapticStepCount = 20

    private var displayProgress: Double {
        if isSeeking {
            return dragProgress
        }
        return pendingSeekProgress ?? progress
    }

    var body: some View {
        Color.clear
            .frame(height: 20)
            .overlay {
                GeometryReader { geometry in
                    track(in: geometry.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .gesture(scrubGesture(in: geometry.size))
                }
            }
            .allowsHitTesting(true)
            .animation(.easeInOut(duration: 0.15), value: isSeeking)
        .onChange(of: progress) { _, newProgress in
            guard let pendingSeekProgress else { return }
            if abs(newProgress - pendingSeekProgress) < 0.01 {
                settleSeekTask?.cancel()
                self.pendingSeekProgress = nil
            }
        }
        .onChange(of: isDragging) { _, dragging in
            guard !dragging else { return }
            cancelScrubIfNeeded()
        }
        .onDisappear {
            settleSeekTask?.cancel()
            cancelScrubIfNeeded()
        }
    }

    private func cancelScrubIfNeeded() {
        guard isSeeking else { return }
        isSeeking = false
        lastHapticStep = nil
        onScrub(nil)
    }

    private func track(in size: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.white.opacity(0.3))

            Capsule()
                .fill(.white.opacity(0.55))
                .frame(width: max(0, size.width * (cacheEnd - cacheStart)))
                .offset(x: size.width * cacheStart)

            Capsule()
                .fill(.white)
                .frame(width: size.width * displayProgress)
        }
        .frame(height: 6)
        .clipShape(Capsule())
    }

    private func scrubGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                settleSeekTask?.cancel()
                pendingSeekProgress = nil
                if !isSeeking {
                    isSeeking = true
                }
                let fraction = max(0, min(1, value.location.x / size.width))
                dragProgress = fraction
                onScrub(fraction)
                triggerHapticIfNeeded(for: fraction)
            }
            .onEnded { value in
                let fraction = max(0, min(1, value.location.x / size.width))
                dragProgress = fraction
                pendingSeekProgress = fraction
                onSeek(fraction)
                onScrub(nil)
                isSeeking = false
                lastHapticStep = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                settleSeekTask = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        pendingSeekProgress = nil
                    }
                }
            }
    }

    private func triggerHapticIfNeeded(for fraction: Double) {
        let step = Int((fraction * Double(hapticStepCount)).rounded())
        guard step != lastHapticStep else { return }
        lastHapticStep = step
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.55)
    }
}

#Preview {
    PlayerProgressBar(
        progress: 0.4,
        cacheStart: 0.2,
        cacheEnd: 0.7,
        isSeeking: .constant(false),
        onScrub: { _ in },
        onSeek: { _ in }
    )
    .padding()
    .background(.black)
}
