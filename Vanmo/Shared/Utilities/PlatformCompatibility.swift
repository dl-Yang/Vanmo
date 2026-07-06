import Foundation
#if os(iOS)
import UIKit
import VanmoCore
#endif

enum PlatformHaptics {
    static func impactLight() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func impactMedium(intensity: CGFloat = 1.0) {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: intensity)
        #endif
    }
}
