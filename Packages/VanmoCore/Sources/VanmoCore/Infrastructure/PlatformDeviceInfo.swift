import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum PlatformDeviceInfo {
    public static var model: String {
        #if os(iOS)
        switch machineIdentifier {
        case let id where id.hasPrefix("iPad"):
            return "iPad"
        case let id where id.hasPrefix("iPhone"):
            return "iPhone"
        case let id where id.hasPrefix("iPod"):
            return "iPod touch"
        default:
            return "iOS"
        }
        #elseif os(macOS)
        return "Mac"
        #else
        return "Unknown"
        #endif
    }

    public static var systemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    /// 跨平台持久化设备标识，首次访问生成并写入 UserDefaults。
    /// 注意：iOS 升级后不再使用 `UIDevice.identifierForVendor`，Emby/Jellyfin 可能将其识别为新设备；
    /// Plex 使用独立的 `PlexCredentialStore.clientIdentifier`，不受此字段影响。
    public static var deviceIdentifier: String {
        if let id = UserDefaults.standard.string(forKey: deviceIdentifierKey) {
            return id
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceIdentifierKey)
        return new
    }

    private static let deviceIdentifierKey = "vanmo.deviceIdentifier"

    #if os(iOS)
    private static var machineIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }
    #endif
}
