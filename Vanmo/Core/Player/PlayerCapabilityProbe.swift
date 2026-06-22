import Foundation

enum PlayerCapabilityProbe {
    static func isHDRCandidate(url: URL) -> Bool {
        let source = url.lastPathComponent.uppercased()
        return source.contains("HDR")
            || source.contains("DOLBY VISION")
            || source.contains("DOVI")
            || source.contains(".DV.")
            || source.contains("HLG")
            || source.contains("HDR10")
    }

    static func isDiscImage(url: URL) -> Bool {
        MediaFormatProbe.isDiscImage(url)
    }
}
