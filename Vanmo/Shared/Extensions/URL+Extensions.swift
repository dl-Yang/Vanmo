import Foundation
import VanmoCore

extension URL {
    var isVideoFile: Bool { MediaFormatProbe.isVideo(self) }
    var isSubtitleFile: Bool { MediaFormatProbe.isSubtitle(self) }

    var fileSizeString: String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
