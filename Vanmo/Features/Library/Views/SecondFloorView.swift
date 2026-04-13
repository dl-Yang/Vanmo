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
        HStack(spacing: 8) {
            ForEach(0..<recentlyPlayed.count, id: \.self) { i in
                Circle()
                    .fill(i == selectedIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == selectedIndex ? 8 : 6, height: i == selectedIndex ? 8 : 6)
                    .animation(.easeInOut(duration: 0.2), value: selectedIndex)
            }
        }
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
