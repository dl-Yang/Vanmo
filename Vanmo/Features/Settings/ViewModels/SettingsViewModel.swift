import SwiftUI
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @AppStorage("playback.autoPlay") var autoPlayNext = true
    @AppStorage("playback.resumePlayback") var resumePlayback = true
    @AppStorage("playback.defaultRate") var defaultRate: Double = 1.0
    @AppStorage("playback.hardwareDecoding") var hardwareDecoding = true

    @AppStorage("subtitle.autoLoad") var subtitleAutoLoad = true
    @AppStorage("subtitle.fontSize") var subtitleFontSize: Double = 18
    @AppStorage("subtitle.preferredLanguage") var subtitlePreferredLanguage = "zh"

    @AppStorage("library.autoScan") var libraryAutoScan = true
    @AppStorage("library.showUnwatched") var showUnwatchedBadge = true

    @AppStorage("appearance.theme") var appearance: AppearanceMode = .system

    @Published var tmdbAPIKey: String = ""
    @Published var isAPIKeyValid: Bool? = nil
    @Published var cacheSize: String = "计算中..."
    @Published var showClearCacheAlert = false
    @Published var showResetAlert = false

    func loadAPIKey() {
        tmdbAPIKey = (try? KeychainManager.shared.loadString(for: "tmdb.apiKey")) ?? ""
        isAPIKeyValid = tmdbAPIKey.isEmpty ? nil : true
    }

    func saveAPIKey() {
        let trimmed = tmdbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try TMDbService.shared.setAPIKey(trimmed)
            isAPIKeyValid = true
        } catch {
            isAPIKeyValid = false
        }
    }

    func validateAPIKey() async {
        let key = tmdbAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            isAPIKeyValid = nil
            return
        }
        do {
            try TMDbService.shared.setAPIKey(key)
            let results = try await TMDbService.shared.searchMovie(query: "test")
            isAPIKeyValid = true
            _ = results
        } catch {
            isAPIKeyValid = false
        }
    }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    func calculateCacheSize() async {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cachePath else {
            cacheSize = "未知"
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cachePath,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )

            var totalSize: Int64 = 0
            for url in contents {
                let attrs = try url.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(attrs.fileSize ?? 0)
            }

            cacheSize = totalSize.formattedFileSize
        } catch {
            cacheSize = "未知"
        }
    }

    func clearCache() async {
        let cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let cachePath else { return }

        try? FileManager.default.removeItem(at: cachePath)
        try? FileManager.default.createDirectory(at: cachePath, withIntermediateDirectories: true)

        await calculateCacheSize()
    }

    func resetAllSettings() {
        autoPlayNext = true
        resumePlayback = true
        defaultRate = 1.0
        hardwareDecoding = true
        subtitleAutoLoad = true
        subtitleFontSize = 18
        subtitlePreferredLanguage = "zh"
        libraryAutoScan = true
        showUnwatchedBadge = true
        appearance = .system
    }
}

enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
