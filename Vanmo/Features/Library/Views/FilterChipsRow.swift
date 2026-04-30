import SwiftUI

struct FilterChipsRow: View {
    let title: String
    let options: [String]
    @Binding var selection: Set<String>

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded {
                expandedChips
//                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                collapsedSummary
//                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
    }

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if !selection.isEmpty {
                    Text("\(selection.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.vanmoPrimary)
                        .clipShape(Circle())
                }

                Spacer()

                Text(selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .buttonStyle(.plain)
    }

    private var collapsedSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                let visibleOptions = selection.isEmpty ? [LibraryFilters.allTitle] : Array(selection).sorted()
                ForEach(visibleOptions, id: \.self) { option in
                    FilterChip(
                        title: option,
                        isSelected: true,
                        action: { isExpanded = true }
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var expandedChips: some View {
        FilterFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(options, id: \.self) { option in
                FilterChip(
                    title: option,
                    isSelected: isSelected(option),
                    action: { toggle(option) }
                )
            }
        }
        .padding(.vertical, 2)
    }

    private var selectionSummary: String {
        guard !selection.isEmpty else { return "全部" }
        let sortedSelection = Array(selection).sorted()
        guard let first = sortedSelection.first else { return "全部" }
        return sortedSelection.count == 1 ? first : "\(first) +\(sortedSelection.count - 1)"
    }

    private func isSelected(_ option: String) -> Bool {
        option == LibraryFilters.allTitle ? selection.isEmpty : selection.contains(option)
    }

    private func toggle(_ option: String) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            if option == LibraryFilters.allTitle {
                selection.removeAll()
            } else if selection.contains(option) {
                selection.remove(option)
            } else {
                selection.insert(option)
            }
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(isSelected ? Color.vanmoPrimary : Color.vanmoSurface)
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 18) {
        FilterChipsRow(
            title: "类型",
            options: LibraryFilters.genres,
            selection: .constant(["动作", "科幻"])
        )
        FilterChipsRow(
            title: "地区",
            options: LibraryFilters.regions.map(\.title),
            selection: .constant([])
        )
    }
    .padding(.vertical)
    .background(Color.vanmoBackground)
    .preferredColorScheme(.dark)
}
