import Kingfisher
import SwiftUI
import VanmoCore

struct MacRemoteImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    var body: some View {
        Group {
            if let url {
                KFImage(url)
                    .placeholder {
                        placeholder.overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .fade(duration: 0.25)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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
