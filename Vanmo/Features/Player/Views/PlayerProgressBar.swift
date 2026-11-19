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
    @GestureState private var isDragging = false

    private let hapticStepCount = 20

    private var displayProgress: Double {
        let raw = isSeeking ? dragProgress : (pendingSeekProgress ?? progress)
        return min(max(raw, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            track(in: geometry.size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(scrubGesture(in: geometry.size))
        }
        .frame(height: 22)
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
        let width = max(size.width, 1)
        let fillWidth = max(3, width * displayProgress)
        let thumbOffset = min(max(fillWidth - 10, 0), max(width - 20, 0))
        let cacheSpan = max(0, width * (cacheEnd - cacheStart))

        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255).opacity(0.30))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.22),
                            lineWidth: 0.75
                        )
                )
                .frame(height: 5)

            if cacheSpan > 0 {
                Capsule()
                    .fill(Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.26))
                    .frame(width: cacheSpan, height: 3)
                    .offset(x: width * cacheStart)
            }

            Capsule()
                .fill(CatDesign.glowAmber)
                .frame(width: fillWidth, height: 3)

            ZStack {
                Circle()
                    .fill(Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.15))
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        CatDesign.glowAmber.opacity(0.28),
                                        Color.white.opacity(0.06)
                                    ],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: 10
                                )
                            )
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(CatDesign.glowAmber.opacity(0.60), lineWidth: 1)
                    )
                    .shadow(color: CatDesign.glowAmber.opacity(0.80), radius: 8)

                Image("CatPawDot")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(CatDesign.glowAmber)
            }
            .frame(width: 20, height: 20)
            .offset(x: thumbOffset)
        }
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
                let fraction = max(0, min(1, value.location.x / max(size.width, 1)))
                dragProgress = fraction
                onScrub(fraction)
                triggerHapticIfNeeded(for: fraction)
            }
            .onEnded { value in
                let fraction = max(0, min(1, value.location.x / max(size.width, 1)))
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
