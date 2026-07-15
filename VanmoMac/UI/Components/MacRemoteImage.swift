import Kingfisher
import SwiftUI
import VanmoCore

struct MacRemoteImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    // 注意：本组件自身不提供固有尺寸，调用方必须通过 .frame 等方式给出尺寸约束；
    // 否则 Color.clear 会占满可用空间。
    var body: some View {
        Color.clear
            .overlay {
                imageContent
            }
            .clipped()
    }

    @ViewBuilder
    private var imageContent: some View {
        if let url {
            KFImage(url)
                .placeholder {
                    placeholder.overlay {
                        LoadingIndicatorView(size: 24)
                    }
                }
                .fade(duration: 0.25)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack{
            Rectangle()
                .fill(Color.white)
            Image(systemName: "film")
                .font(.largeTitle)
                .contentShape(Rectangle())
        }
    }
}
