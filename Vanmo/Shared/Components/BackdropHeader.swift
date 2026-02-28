import SwiftUI

struct BackdropHeader: View {
    let imageURL: URL?
    let height: CGFloat

    init(imageURL: URL?, height: CGFloat = 300) {
        self.imageURL = imageURL
        self.height = height
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Rectangle()
                        .fill(Color.vanmoSurface)
                @unknown default:
                    Rectangle()
                        .fill(Color.vanmoSurface)
                }
            }
            .frame(height: height)
            .clipped()

            LinearGradient.headerOverlay
                .frame(height: height)
        }
    }
}

#Preview {
    BackdropHeader(imageURL: nil)
        .preferredColorScheme(.dark)
}
