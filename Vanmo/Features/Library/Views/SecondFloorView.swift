import SwiftUI

struct SecondFloorView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool
    let recentlyPlayed: [MediaItem]

    @State private var selectedIndex: Int = 0
    @State private var dominantColor: Color = .black.opacity(0.9)
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .gesture(dismissGesture)
        .statusBarHidden()
        .onAppear {
            if let first = recentlyPlayed.first {
                extractDominantColor(from: first)
            }
        }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        ZStack {
            dominantColor.ignoresSafeArea()

            LinearGradient(
                colors: [
                    dominantColor,
                    dominantColor.opacity(0.6),
                    .black.opacity(0.9),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.5), value: dominantColor.description)
    }

    // MARK: - Content

    private var contentLayer: some View {
        VStack(spacing: 0) {
            topBar
            pagerContent
            pageIndicator
                .padding(.bottom, 32)
        }
        .offset(y: dragOffset)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("继续观看")
                .font(.headline)
                .foregroundStyle(.white)

            Spacer()

            Color.clear.frame(width: 28, height: 28)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Pager

    private var pagerContent: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(recentlyPlayed.enumerated()), id: \.element.id) { index, item in
                SecondFloorItemView(item: item) {
                    appState.play(item)
                    dismiss()
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: selectedIndex) { _, newIndex in
            guard newIndex >= 0, newIndex < recentlyPlayed.count else { return }
            extractDominantColor(from: recentlyPlayed[newIndex])
            let generator = UISelectionFeedbackGenerator()
            generator.selectionChanged()
        }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        let count = recentlyPlayed.count
        let maxVisible = 6
        let dotSlot: CGFloat = 8
        let spacing: CGFloat = 8
        let step = dotSlot + spacing
        let visibleCount = min(count, maxVisible)
        let containerWidth = CGFloat(visibleCount) * dotSlot + CGFloat(max(visibleCount - 1, 0)) * spacing
        let needsScroll = count > maxVisible
        let windowStart: Int = {
            guard needsScroll else { return 0 }
            let target = selectedIndex - (maxVisible / 2 - 1)
            return max(0, min(count - maxVisible, target))
        }()

        return ZStack(alignment: .leading) {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { i in
                    let isSelected = i == selectedIndex
                    Circle()
                        .fill(isSelected ? Color.white : Color.white.opacity(0.3))
                        .frame(width: isSelected ? 8 : 6, height: isSelected ? 8 : 6)
                        .frame(width: dotSlot, height: dotSlot)
                }
            }
            .offset(x: -CGFloat(windowStart) * step)
        }
        .frame(width: containerWidth, height: dotSlot, alignment: .leading)
        .clipped()
        .animation(.easeInOut(duration: 0.25), value: selectedIndex)
    }

    // MARK: - Dismiss Gesture

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .global)
            .onChanged { value in
                if value.translation.height < 0 {
                    dragOffset = value.translation.height * 0.4
                }
            }
            .onEnded { value in
                if value.translation.height < -120 {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: - Helpers

    private func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isPresented = false
        }
    }

    private func extractDominantColor(from item: MediaItem) {
        Task {
            let color = await DominantColorExtractor.cachedColor(for: item.posterURL)
            withAnimation(.easeInOut(duration: 0.5)) {
                dominantColor = color
            }
        }
    }
}

#Preview {
    SecondFloorView(
        isPresented: .constant(true),
        recentlyPlayed: [
            MediaItem(
                title: "Inception",
                fileURL: URL(fileURLWithPath: "/test.mkv"),
                mediaType: .movie,
                fileSize: 4_500_000_000,
                duration: 8880
            ),
        ]
    )
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
