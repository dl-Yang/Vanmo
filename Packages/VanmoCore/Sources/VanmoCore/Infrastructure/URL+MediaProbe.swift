import Foundation

extension URL {
    var isVideoFile: Bool { MediaFormatProbe.isVideo(self) }

    var isSubtitleFile: Bool { MediaFormatProbe.isSubtitle(self) }
}
