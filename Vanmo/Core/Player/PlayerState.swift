import Foundation
import CoreMedia

enum PlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case error(String)
    case ended

    var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering: return true
        default: return false
        }
    }
}

enum VideoScaleMode: String, CaseIterable {
    case fit
    case fill
    case stretch

    var displayName: String {
        switch self {
        case .fit: return "适应"
        case .fill: return "填充"
        case .stretch: return "拉伸"
        }
    }

    var icon: String {
        switch self {
        case .fit: return "arrow.down.right.and.arrow.up.left"
        case .fill: return "arrow.up.left.and.arrow.down.right"
        case .stretch: return "rectangle.expand.vertical"
        }
    }
}

struct PlayerConfig {
    var playbackRate: Float = 1.0
    var scaleMode: VideoScaleMode = .fit
    var selectedAudioTrack: Int = 0
    var selectedSubtitleTrack: Int? = nil
    var subtitleDelay: TimeInterval = 0
    var brightness: Float? = nil
    var volume: Float = 1.0
    var isMuted: Bool = false

    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0]
}
