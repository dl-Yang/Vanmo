import Foundation
import VanmoCore

enum MacFormatters {
    static func remainingDuration(position: TimeInterval, total: TimeInterval) -> String {
        LocalizedFormat.remainingDuration(position: position, total: total)
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else {
            return LocalizedFormat.shortDuration(0)
        }
        return LocalizedFormat.shortDuration(interval)
    }

    static func playerTimestamp(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0:00" }
        let totalSeconds = max(Int(interval.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func playerRemainingTimestamp(_ interval: TimeInterval) -> String {
        let value = playerTimestamp(abs(interval))
        return interval < 0 ? "-\(value)" : value
    }
}
