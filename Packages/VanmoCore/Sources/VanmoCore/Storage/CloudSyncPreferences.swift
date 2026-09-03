import Foundation

public enum CloudSyncPreferences {
    public static let enabledKey = "cloudSync.enabled"
    public static let lastSyncTimestampKey = "cloudSync.lastSyncAt"

    public static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    public static var lastSyncAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: lastSyncTimestampKey)
            guard timestamp > 0 else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastSyncTimestampKey)
        }
    }
}

public enum CloudSyncDevice {
    public static let id: String = {
        let key = "cloudSync.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()
}

public enum CloudSyncAvailability {
    /// Debug 与 Release 均定义 `CLOUDKIT_SYNC_ENABLED`，真机需 Cloud entitlement 与已绑定的 iCloud 容器。
    public static var isCloudKitEnabled: Bool {
        #if CLOUDKIT_SYNC_ENABLED
        return true
        #else
        return false
        #endif
    }

    public static var unavailableMessage: String {
        L10n.tr("当前构建未启用 CloudKit。iCloud 同步需要 Cloud entitlement、付费 Team 与已绑定的 iCloud 容器。")
    }
}
