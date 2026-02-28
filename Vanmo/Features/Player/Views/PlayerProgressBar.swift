import SwiftUI

struct PlayerProgressBar: View {
    let progress: Double
    let bufferProgress: Double
    @Binding var isSeeking: Bool
    let onSeek: (Double) -> Void

    @State private var dragProgress: Double = 0

    private var displayProgress: Double {
        isSeeking ? dragProgress : progress
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
                        isSeeking = true
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = fraction
                    }
                    .onEnded { value in
                        let fraction = max(0, min(1, value.location.x / geometry.size.width))
                        onSeek(fraction)
                        isSeeking = false
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: isSeeking)
        }
        .frame(height: 20)
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
