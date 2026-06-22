import Foundation
import AVFoundation
import CoreMedia

/// 视频动态范围。`rawValue` 用于持久化到 `MediaItem`。
enum DynamicRange: String {
    case sdr
    /// 通用 HDR（探测到 PQ 但未细分具体标准）
    case hdr
    case hdr10
    case hlg
    case dolbyVision

    var isHDR: Bool { self != .sdr }

    /// 详情页等场景的完整标签。
    var displayName: String? {
        switch self {
        case .sdr: return nil
        case .hdr: return "HDR"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "Dolby Vision"
        }
    }

    /// 列表角标用的紧凑标签。
    var compactBadge: String? {
        switch self {
        case .sdr: return nil
        case .hdr: return "HDR"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        case .dolbyVision: return "DV"
        }
    }
}

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

    /// 读取视频轨真实元数据判断动态范围。
    /// 仅适用于 AVFoundation 可解析的容器（mp4/mov 等）；
    /// 无法读取（如 mkv 需走 FFmpeg）时返回 `nil`，由调用方回退到文件名启发式。
    static func detectDynamicRange(for url: URL) async -> DynamicRange? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let formatDescriptions = try? await track.load(.formatDescriptions),
              let description = formatDescriptions.first else {
            return nil
        }

        if isDolbyVision(description) {
            return .dolbyVision
        }

        guard let transferFunction = CMFormatDescriptionGetExtension(
            description,
            extensionKey: kCMFormatDescriptionExtension_TransferFunction
        ) as? String else {
            return .sdr
        }

        if transferFunction == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) {
            return .hdr10
        }
        if transferFunction == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) {
            return .hlg
        }
        return .sdr
    }

    /// 通过编码子类型或 Dolby Vision 配置原子（dvcC / dvvC）判断杜比视界。
    private static func isDolbyVision(_ description: CMFormatDescription) -> Bool {
        let subtype = CMFormatDescriptionGetMediaSubType(description)
        let dolbyVisionSubtypes: Set<FourCharCode> = [
            fourCC("dvh1"), fourCC("dvhe"), fourCC("dvav"), fourCC("dav1"),
        ]
        if dolbyVisionSubtypes.contains(subtype) {
            return true
        }

        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any],
              let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any] else {
            return false
        }
        return atoms["dvcC"] != nil || atoms["dvvC"] != nil
    }

    private static func fourCC(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + FourCharCode(scalar.value & 0xFF)
        }
        return result
    }
}
