import SwiftUI

struct FilterFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        let rows = rows(in: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.height
        } + CGFloat(max(0, rows.count - 1)) * lineSpacing

        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY

        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX

            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }

            y += row.height + lineSpacing
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard !subviews.isEmpty else { return [] }

        let availableWidth = max(maxWidth, 1)
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let item = FlowItem(index: index, size: size)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if proposedWidth > availableWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = [item]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(item)
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }

        return rows
    }
}

private struct FlowRow {
    let items: [FlowItem]
    let height: CGFloat
}

private struct FlowItem {
    let index: Int
    let size: CGSize
}

#Preview {
    FilterFlowLayout(spacing: 8, lineSpacing: 8) {
        ForEach(LibraryFilters.genres, id: \.self) { genre in
            Text(genre)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color.vanmoSurface)
                .clipShape(Capsule())
        }
    }
    .padding()
    .background(Color.vanmoBackground)
    .preferredColorScheme(.dark)
}
