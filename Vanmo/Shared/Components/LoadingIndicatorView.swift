import SwiftUI

#if canImport(Lottie)
import Lottie
#endif

/// 加载指示器。优先播放 Lottie 动画 `loadingSpinner`；
/// 若未集成 lottie-ios（SPM）或资源缺失，回退到系统 `ProgressView`。
struct LoadingIndicatorView: View {
    var size: CGFloat = 56

    var body: some View {
        #if canImport(Lottie)
        if let animation = LottieAnimation.named("loadingSpinner") {
            LottieView(animation: animation)
                .playing(loopMode: .loop)
                .frame(width: size, height: size)
                .accessibilityLabel("加载中")
        } else {
            systemProgressView
        }
        #else
        systemProgressView
        #endif
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
