import Foundation

enum MacFormatters {
    static func remainingDuration(position: TimeInterval, total: TimeInterval) -> String {
        let remaining = max(total - position, 0)
        return formatDuration(remaining) + " remaining"
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0m" }
        let totalMinutes = Int(interval.rounded()) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(max(minutes, 1))m"
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
