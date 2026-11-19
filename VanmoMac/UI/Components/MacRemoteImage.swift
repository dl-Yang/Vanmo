import Kingfisher
import SwiftUI
import VanmoCore

struct MacRemoteImage: View {
    @Environment(\.macTheme) private var theme

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
                .fade(duration: url.isFileURL ? 0 : 0.2)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(theme.isDark ? Color(red: 18 / 255, green: 19 / 255, blue: 22 / 255) : Color(red: 0xEB / 255, green: 0xE5 / 255, blue: 0xDA / 255))
            Image(systemName: "film")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(theme.tertiaryText)
                .contentShape(Rectangle())
        }
    }
}
