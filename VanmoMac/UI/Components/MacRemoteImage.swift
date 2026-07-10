import Kingfisher
import SwiftUI
import VanmoCore

struct MacRemoteImage: View {
    let url: URL?
    var contentMode: SwiftUI.ContentMode = .fill

    // 注意：本组件自身不提供固有尺寸，调用方必须通过 .frame 等方式给出尺寸约束；
    // 否则 Color.clear 会占满可用空间。
    var body: some View {
        // 用一个尺寸中立的容器（Color.clear）承接父布局给定的尺寸，
        // 图片作为 overlay 渲染。overlay 永远不会反向影响父视图尺寸，
        // 因此“父布局先确定尺寸、再裁剪图片”，避免远端图片尺寸引起的布局抖动。
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
                .fill(Color.gray.opacity(0.25))
            Image(systemName: "film")
                .font(.largeTitle)
                .contentShape(Rectangle())
        }
    }
}
