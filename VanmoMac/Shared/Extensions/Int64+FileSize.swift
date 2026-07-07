import Foundation

extension Int64 {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false
        let result = formatter.string(fromByteCount: self)
        if result.hasPrefix("Zero") {
            return result.replacingOccurrences(of: "Zero", with: "0")
        }
        return result
    }
}
