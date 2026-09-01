import Foundation

/// Locale-aware duration and episode labels.
public enum LocalizedFormat {
    public static func shortDuration(
        _ interval: TimeInterval,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        let totalMinutes = max(0, Int(interval) / 60)
        let chinese = languageCode.hasPrefix("zh")
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            if chinese {
                return minutes > 0 ? "\(hours)小时\(minutes)分钟" : "\(hours)小时"
            }
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return chinese ? "\(totalMinutes)分钟" : "\(totalMinutes)m"
    }

    public static func unknownDuration(languageCode: String = AppLanguage.resolvedLanguageCode) -> String {
        languageCode.hasPrefix("zh") ? "-- 分钟" : "-- min"
    }

    public static func seasonLabel(
        _ season: Int,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        languageCode.hasPrefix("zh") ? "第\(season)季" : "Season \(season)"
    }

    public static func episodeLabel(
        _ episode: Int,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        languageCode.hasPrefix("zh") ? "第\(episode)集" : "Episode \(episode)"
    }

    public static func episodeCode(
        season: Int,
        episode: Int,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        if languageCode.hasPrefix("zh") {
            return "第\(season)季第\(episode)集"
        }
        return String(format: "S%02dE%02d", season, episode)
    }

    public static func showEpisodeTitle(
        showTitle: String,
        season: Int,
        episode: Int,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        "\(showTitle) \(episodeCode(season: season, episode: episode, languageCode: languageCode))"
    }

    public static func compactSeasonCode(
        _ season: Int,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        languageCode.hasPrefix("zh") ? "第\(season)季" : String(format: "S%02d", season)
    }

    public static func compactEpisodeCode(
        _ episode: Int,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        languageCode.hasPrefix("zh") ? "第\(episode)集" : String(format: "E%02d", episode)
    }

    public static func remainingDuration(
        position: TimeInterval,
        total: TimeInterval,
        languageCode: String = AppLanguage.resolvedLanguageCode
    ) -> String {
        let remaining = max(total - position, 0)
        let body = shortDuration(remaining, languageCode: languageCode)
        return languageCode.hasPrefix("zh") ? "剩余 \(body)" : "\(body) remaining"
    }

    public static func relativeDate(
        _ date: Date,
        relativeTo now: Date = Date()
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    public static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.zeroPadsFractionDigits = false
        if AppLanguage.isChinese {
            formatter.isAdaptive = true
        }
        let result = formatter.string(fromByteCount: bytes)
        if result.hasPrefix("Zero") {
            return result.replacingOccurrences(of: "Zero", with: "0")
        }
        return result
    }
}

public extension TimeInterval {
    var localizedShortDuration: String {
        LocalizedFormat.shortDuration(self)
    }
}
