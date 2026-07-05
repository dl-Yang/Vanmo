import Foundation
#if os(iOS)
import UIKit
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

enum PlatformDeviceInfo {
    static var model: String {
        #if os(iOS)
        UIDevice.current.model
        #elseif os(macOS)
        "Mac"
        #else
        "Unknown"
        #endif
    }

    static var systemVersion: String {
        #if os(iOS)
        UIDevice.current.systemVersion
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        "0"
        #endif
    }

    static var deviceIdentifier: String {
        #if os(iOS)
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        UUID().uuidString
        #endif
    }
}
