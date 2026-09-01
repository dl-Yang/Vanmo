import Foundation

/// User-selected interface language. Default is Chinese, not system.
public enum AppLanguagePreference: String, CaseIterable, Sendable {
    case chinese
    case english
    case system

    public static let storageKey = "app.interfaceLanguage"
    public static let defaultPreference: AppLanguagePreference = .chinese

    public static var stored: AppLanguagePreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey) else {
                return defaultPreference
            }
            return AppLanguagePreference(rawValue: raw) ?? defaultPreference
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    public var displayName: String {
        switch self {
        case .chinese: L10n.tr("中文")
        case .english: L10n.tr("英文")
        case .system: L10n.tr("跟随系统")
        }
    }

    public func resolvedLanguageCode(preferredLanguages: [String]) -> String {
        AppLanguage.resolve(preference: self, preferredLanguages: preferredLanguages)
    }
}

/// Process-wide interface language. Lock once at launch; changing the
/// preference does not update the lock until the next launch.
public enum AppLanguage {
    public static let chineseCode = "zh-Hans"
    public static let englishCode = "en"

    private static let stateLock = NSLock()
    private static var lockedCode: String?

    public static func lockForCurrentProcess() {
        stateLock.lock()
        defer { stateLock.unlock() }
        if lockedCode == nil {
            lockedCode = resolve(
                preference: AppLanguagePreference.stored,
                preferredLanguages: Locale.preferredLanguages
            )
        }
    }

    public static var resolvedLanguageCode: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        if let lockedCode {
            return lockedCode
        }
        return resolve(
            preference: AppLanguagePreference.stored,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    public static var isChinese: Bool {
        resolvedLanguageCode.hasPrefix("zh")
    }

    public static var locale: Locale {
        Locale(identifier: resolvedLanguageCode)
    }

    public static func resolve(
        preference: AppLanguagePreference,
        preferredLanguages: [String]
    ) -> String {
        switch preference {
        case .chinese:
            return chineseCode
        case .english:
            return englishCode
        case .system:
            return resolveSystemLanguage(preferredLanguages)
        }
    }

    public static func resolveSystemLanguage(_ preferredLanguages: [String]) -> String {
        let identifier = preferredLanguages.first ?? englishCode
        let languageCode: String
        if #available(iOS 17, macOS 14, *) {
            languageCode = Locale.Language(identifier: identifier).languageCode?.identifier ?? identifier
        } else {
            languageCode = Locale(identifier: identifier).languageCode ?? identifier
        }
        if languageCode.lowercased().hasPrefix("zh") || identifier.lowercased().hasPrefix("zh") {
            return chineseCode
        }
        return englishCode
    }
}
