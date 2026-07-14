import SwiftUI

import Lottie

struct LoadingIndicatorView: View {
    var size: CGFloat = 56

    var body: some View {
        if let animation = LottieAnimation.named("loadingSpinner") {
            LottieView(animation: animation)
                .playing(loopMode: .loop)
                .frame(width: size, height: size)
                .accessibilityLabel("加载中")
        } else {
            systemProgressView
        }

    }

    private var systemProgressView: some View {
        ProgressView()
            .controlSize(size >= 40 ? .large : .small)
            .frame(width: size, height: size)
            .accessibilityLabel("加载中")
    }
}

#Preview {
    LoadingIndicatorView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
}
