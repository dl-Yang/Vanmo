import Foundation

/// Looks up user-visible copy. Chinese keys are the source language.
/// English comes from the package catalog, then the embedded table.
public enum L10n {
    public static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = string(for: key)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: AppLanguage.locale, arguments: args)
    }

    public static func string(for key: String) -> String {
        if AppLanguage.isChinese {
            return key
        }
        if let bundled = catalogString(for: key), bundled != key {
            return bundled
        }
        return L10nTable.english[key] ?? key
    }

    private static func catalogString(for key: String) -> String? {
        guard let path = Bundle.module.path(forResource: AppLanguage.englishCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
