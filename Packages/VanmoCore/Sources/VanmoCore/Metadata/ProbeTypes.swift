import Foundation

public enum ProbeStatus: String, Codable, Sendable {
    case pending
    case success
    case partial
    case failed
    case unsupported
}

public struct MediaProbeResult: Sendable, Equatable {
    public let status: ProbeStatus
    public let duration: TimeInterval
    public let container: String?
    public let videoWidth: Int?
    public let videoHeight: Int?
    public let videoCodec: String?
    public let dynamicRange: DynamicRange?
    public let audioTracks: [AudioTrackInfo]
    public let subtitleTracks: [SubtitleTrackInfo]
    public let message: String?

    public init(
        status: ProbeStatus,
        duration: TimeInterval = 0,
        container: String? = nil,
        videoWidth: Int? = nil,
        videoHeight: Int? = nil,
        videoCodec: String? = nil,
        dynamicRange: DynamicRange? = nil,
        audioTracks: [AudioTrackInfo] = [],
        subtitleTracks: [SubtitleTrackInfo] = [],
        message: String? = nil
    ) {
        self.status = status
        self.duration = duration
        self.container = container
        self.videoWidth = videoWidth
        self.videoHeight = videoHeight
        self.videoCodec = videoCodec
        self.dynamicRange = dynamicRange
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.message = message
    }
}

public struct ProbeFingerprint: Sendable, Equatable {
    public let remoteModifiedAt: Date?
    public let fileSize: Int64
    public let contentVersion: String?

    public init(remoteModifiedAt: Date?, fileSize: Int64, contentVersion: String? = nil) {
        self.remoteModifiedAt = remoteModifiedAt
        self.fileSize = fileSize
        self.contentVersion = contentVersion
    }

    public var storageValue: String {
        let mtime = remoteModifiedAt.map { String($0.timeIntervalSince1970) } ?? "nil"
        let version = contentVersion ?? ""
        return "\(mtime)::\(fileSize)::\(version)"
    }

    public static func from(item: MediaItem) -> ProbeFingerprint {
        ProbeFingerprint(
            remoteModifiedAt: item.remoteModifiedAt,
            fileSize: item.fileSize,
            contentVersion: item.remoteContentVersion
        )
    }

    public static func from(file: RemoteFile) -> ProbeFingerprint {
        ProbeFingerprint(
            remoteModifiedAt: file.modifiedDate,
            fileSize: file.size,
            contentVersion: file.contentVersion
        )
    }
}

public protocol MediaProbeProviding: AnyObject, Sendable {
    func probe(url: URL, timeout: TimeInterval) async throws -> MediaProbeResult
}

public enum MediaProbeApplicator {
    public static func shouldProbe(item: MediaItem) -> Bool {
        guard !item.isLiveStream else { return false }
        guard item.mediaType != .tvShow, item.mediaType != .boxSet else { return false }

        let fingerprint = ProbeFingerprint.from(item: item).storageValue
        if item.probeStatus == ProbeStatus.pending.rawValue {
            return false
        }
        if item.probeStatus == ProbeStatus.success.rawValue,
           item.probeFingerprint == fingerprint,
           item.duration > 0,
           (item.videoWidth ?? 0) > 0 || (item.videoHeight ?? 0) > 0 {
            return false
        }

        return item.probeStatus == nil
            || item.probeStatus == ProbeStatus.failed.rawValue
            || item.probeFingerprint != fingerprint
            || item.duration <= 0
            || ((item.videoWidth ?? 0) <= 0 && (item.videoHeight ?? 0) <= 0)
    }

    public static func markPending(_ item: MediaItem) {
        item.probeStatus = ProbeStatus.pending.rawValue
    }

    public static func invalidateIfNeeded(existing: MediaItem, file: RemoteFile) {
        let newFingerprint = ProbeFingerprint.from(file: file).storageValue
        if existing.probeFingerprint != newFingerprint {
            existing.probeStatus = ProbeStatus.pending.rawValue
            existing.probeFingerprint = nil
            existing.probedAt = nil
        }
    }

    public static func apply(_ result: MediaProbeResult, to item: MediaItem, fingerprint: ProbeFingerprint) {
        item.probeStatus = result.status.rawValue
        item.probeFingerprint = fingerprint.storageValue
        item.probedAt = Date()

        if result.duration > 0 {
            item.duration = result.duration
        }
        if let container = result.container, !container.isEmpty {
            item.container = container
        }
        if let width = result.videoWidth, width > 0 {
            item.videoWidth = width
        }
        if let height = result.videoHeight, height > 0 {
            item.videoHeight = height
        }
        if let codec = result.videoCodec, !codec.isEmpty {
            item.videoCodec = codec
        }
        if let dynamicRange = result.dynamicRange {
            item.dynamicRange = dynamicRange.rawValue
        }
        if !result.audioTracks.isEmpty {
            item.audioTracks = result.audioTracks
        }
        if !result.subtitleTracks.isEmpty {
            item.subtitleTracks = result.subtitleTracks
        }
    }
}
