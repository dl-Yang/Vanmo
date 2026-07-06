import SwiftUI

#if canImport(Lottie)
import Lottie
import VanmoCore
#endif

/// 加载指示器。优先播放 Figma/LottieFiles 设计稿对应的 Lottie 动画 `loadingSpinner`；
/// 若未集成 lottie-ios（SPM），自动回退到系统 `ProgressView`，保证可编译可运行。
struct LoadingIndicatorView: View {
    var size: CGFloat = 56

    var body: some View {
        #if canImport(Lottie)
        LottieView(animation: .named("loadingSpinner"))
            .playing(loopMode: .loop)
            .frame(width: size, height: size)
            .accessibilityLabel("加载中")
        #else
        ProgressView()
            .controlSize(.large)
            .tint(Color.vanmoPrimary)
            .frame(width: size, height: size)
            .accessibilityLabel("加载中")
        #endif
    }
}

#Preview {
    LoadingIndicatorView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vanmoBackground)
}
