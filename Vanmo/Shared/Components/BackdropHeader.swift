import SwiftUI
import Kingfisher

struct BackdropHeader: View {
    let imageURL: URL?
    let height: CGFloat

    init(imageURL: URL?, height: CGFloat = 300) {
        self.imageURL = imageURL
        self.height = height
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            KFImage(imageURL)
                .placeholder {
                    Rectangle()
                        .fill(Color.vanmoSurface)
                }
                .fade(duration: 0.25)
                .resizable()
                .aspectRatio(contentMode: .fill)
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
