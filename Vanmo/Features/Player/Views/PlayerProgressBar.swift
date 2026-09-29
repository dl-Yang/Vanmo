import SwiftUI
import UIKit
import VanmoCore

struct PlayerProgressBar: View {
    let progress: Double
    let bufferProgress: Double
    let previewImage: UIImage?
    let previewTimeText: String
    @Binding var isSeeking: Bool
    let onScrub: (Double?) -> Void
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double = 0
    @State private var pendingSeekProgress: Double?
    @State private var settleSeekTask: Task<Void, Never>?
    @State private var lastHapticStep: Int?

    private let hapticStepCount = 20
    private let previewWidth: CGFloat = 160

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
            .overlay(alignment: .bottomLeading) {
                GeometryReader { geometry in
                    if isSeeking {
                        previewCard
                            .offset(
                                x: previewOffset(
                                    in: geometry.size.width,
                                    thumbX: geometry.size.width * displayProgress
                                ),
                                y: -28
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .allowsHitTesting(false)
                    }
                }
                .allowsHitTesting(false)
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
        .onDisappear {
            settleSeekTask?.cancel()
        }
    }

    private var previewCard: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.08))
                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: previewWidth, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(previewTimeText)
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(width: previewWidth + 12)
    }

    private func track(in size: CGSize) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.2))

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: size.width * bufferProgress)

            Rectangle()
                .fill(Color.vanmoPrimary)
                .frame(width: size.width * displayProgress)

            Circle()
                .fill(.white)
                .frame(width: isSeeking ? 16 : 10, height: isSeeking ? 16 : 10)
                .shadow(radius: 2)
                .offset(x: size.width * displayProgress - (isSeeking ? 8 : 5))
        }
        .frame(height: isSeeking ? 6 : 3)
        .clipShape(Capsule())
    }

    private func scrubGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                settleSeekTask?.cancel()
                pendingSeekProgress = nil
                isSeeking = true
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

    private func previewOffset(in width: CGFloat, thumbX: CGFloat) -> CGFloat {
        let cardWidth = previewWidth + 12
        return max(0, min(width - cardWidth, thumbX - cardWidth / 2))
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
        previewImage: nil,
        previewTimeText: "12:34",
        isSeeking: .constant(true),
        onScrub: { _ in },
        onSeek: { _ in }
    )
    .padding()
    .background(.black)
}
