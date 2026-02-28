import Foundation
import UniformTypeIdentifiers

extension URL {
    var isVideoFile: Bool {
        let videoExtensions: Set<String> = [
            "mkv", "mp4", "avi", "wmv", "mov", "flv", "rmvb",
            "ts", "m2ts", "webm", "m4v", "mpg", "mpeg", "3gp", "ogv"
        ]
        return videoExtensions.contains(pathExtension.lowercased())
    }

    var isSubtitleFile: Bool {
        let subtitleExtensions: Set<String> = [
            "srt", "ass", "ssa", "vtt", "sub", "idx", "sup"
        ]
        return subtitleExtensions.contains(pathExtension.lowercased())
    }

    var fileSizeString: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
