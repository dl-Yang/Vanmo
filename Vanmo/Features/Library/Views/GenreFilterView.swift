import SwiftUI

struct GenreFilterView: View {
    let allGenres: [String]
    @Binding var selectedGenres: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allGenres, id: \.self) { genre in
                    GenreCapsule(
                        title: genre,
                        isSelected: selectedGenres.contains(genre)
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            if selectedGenres.contains(genre) {
                                selectedGenres.remove(genre)
                            } else {
                                selectedGenres.insert(genre)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct GenreCapsule: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.vanmoPrimary : Color.vanmoSurface)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    GenreFilterView(
        allGenres: ["动作", "喜剧", "爱情", "惊悚", "悬疑", "科幻", "动画", "纪录片"],
        selectedGenres: .constant(["动作", "科幻"])
    )
    .preferredColorScheme(.dark)
}
