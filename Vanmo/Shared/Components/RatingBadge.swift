import SwiftUI

struct RatingBadge: View {
    let rating: Double
    let maxRating: Double

    init(_ rating: Double, maxRating: Double = 10.0) {
        self.rating = rating
        self.maxRating = maxRating
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.caption2)
            Text(String(format: "%.1f", rating))
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(ratingColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ratingColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var ratingColor: Color {
        let normalized = rating / maxRating
        if normalized >= 0.7 { return .green }
        if normalized >= 0.4 { return .orange }
        return .red
    }
}

#Preview {
    HStack {
        RatingBadge(8.5)
        RatingBadge(5.2)
        RatingBadge(3.1)
    }
    .preferredColorScheme(.dark)
}
