import Foundation
#if os(iOS)
import UIKit
#endif

public enum PlatformDeviceInfo {
    public static var model: String {
        #if os(iOS)
        UIDevice.current.model
        #elseif os(macOS)
        "Mac"
        #else
        "Unknown"
        #endif
    }

    public static var systemVersion: String {
        #if os(iOS)
        UIDevice.current.systemVersion
        #elseif os(macOS)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        "0"
        #endif
    }

    public static var deviceIdentifier: String {
        #if os(iOS)
        UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        UUID().uuidString
        #endif
    }
}
