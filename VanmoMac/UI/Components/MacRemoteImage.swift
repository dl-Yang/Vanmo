import SwiftUI
import VanmoCore

struct MacRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder.overlay { ProgressView().controlSize(.small) }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.25))
    }
}
