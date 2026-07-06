import SwiftUI
import UIKit
import VanmoCore

struct PlayerProgressBar: View {
    let progress: Double
    let bufferProgress: Double
    @Binding var isSeeking: Bool
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double = 0
    @State private var pendingSeekProgress: Double?
    @State private var settleSeekTask: Task<Void, Never>?
    @State private var lastHapticStep: Int?

    private let hapticStepCount = 20

    private var displayProgress: Double {
        if isSeeking {
            return dragProgress
        }
        return pendingSeekProgress ?? progress
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(.white.opacity(0.2))

                // Buffer progress
                Rectangle()
                    .fill(.white.opacity(0.3))
                    .frame(width: geometry.size.width * bufferProgress)

                // Playback progress
                Rectangle()
                    .fill(Color.vanmoPrimary)
                    .frame(width: geometry.size.width * displayProgress)

                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: isSeeking ? 16 : 10, height: isSeeking ? 16 : 10)
                    .shadow(radius: 2)
                    .offset(x: geometry.size.width * displayProgress - (isSeeking ? 8 : 5))
            }
            .frame(height: isSeeking ? 6 : 3)
            .clipShape(Capsule())
            .contentShape(Rectangle().inset(by: -20))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        settleSeekTask?.cancel()
                        pendingSeekProgress = nil
                        isSeeking = true
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = fraction
                        triggerHapticIfNeeded(for: fraction)
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = fraction
                        pendingSeekProgress = fraction
                        onSeek(fraction)
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
            )
            .animation(.easeInOut(duration: 0.15), value: isSeeking)
        }
        .frame(height: 20)
        .onChange(of: progress) { _, newProgress in
            guard let pendingSeekProgress else { return }
            if abs(newProgress - pendingSeekProgress) < 0.01 {
                settleSeekTask?.cancel()
                self.pendingSeekProgress = nil
            }
        }
        .onDisappear {
            settleSeekTask?.cancel()
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
        bufferProgress: 0.7,
        isSeeking: .constant(false),
        onSeek: { _ in }
    )
    .padding()
    .background(.black)
}
