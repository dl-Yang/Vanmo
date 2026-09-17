import Kingfisher
import SwiftUI
import VanmoCore

enum DownloadIslandMode: Equatable {
    case hidden
    case flying
    case compact
    case expanded
}

enum DownloadIslandMotion {
    /// Compact → Expanded: system-island grow with a little overshoot above the blob.
    static let morph: Animation = .spring(response: 0.36, dampingFraction: 0.68)
    /// Expanded → Compact: critically damped so height cannot dip below the hardware island.
    static let collapse: Animation = .spring(response: 0.36, dampingFraction: 1)
    /// Critically damped so delete / complete collapse cannot overshoot and bounce.
    static let dismiss: Animation = .spring(response: 0.32, dampingFraction: 1)
    /// Island → Compact appear without a settle bounce.
    static let appear: Animation = .spring(response: 0.42, dampingFraction: 1)
    static let contentIn: Animation = .easeOut(duration: 0.16).delay(0.08)
    static let contentOut: Animation = .easeIn(duration: 0.10)
}

struct DownloadIslandChrome: Equatable {
    var taskID: UUID?
    var title: String
    var statusText: String
    var progress: Double
    var isPaused: Bool
    var isCompleted: Bool
    var receivedBytes: Int64
    var totalBytes: Int64
    var posterURL: URL?

    static func make(from selected: DownloadActivityPresentation, task: DownloadTaskSnapshot?) -> DownloadIslandChrome {
        let resolved = task ?? selected.task
        let isPaused = resolved?.status == .paused
        let isCompleted = resolved?.status == .completed || selected.didCompleteCurrent
        let statusText: String
        if isCompleted {
            statusText = L10n.tr("已完成")
        } else if isPaused {
            statusText = L10n.tr("已暂停")
        } else {
            statusText = L10n.tr("下载中")
        }
        return DownloadIslandChrome(
            taskID: resolved?.id,
            title: selected.title.isEmpty ? (resolved.map { DownloadActivityPresentation.title(for: $0.request) } ?? "") : selected.title,
            statusText: statusText,
            progress: selected.progress,
            isPaused: isPaused,
            isCompleted: isCompleted,
            receivedBytes: resolved?.receivedBytes ?? 0,
            totalBytes: resolved?.totalBytes ?? 0,
            posterURL: selected.posterURL ?? resolved?.request.postUrl
        )
    }

    var percent: Int {
        Int(((isCompleted ? 1 : min(max(progress, 0), 1)) * 100).rounded())
    }

    var byteLine: String {
        let received = ByteCountFormatter.string(fromByteCount: receivedBytes, countStyle: .file)
        guard totalBytes > 0 else { return received }
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(received) / \(total)"
    }
}

struct DownloadIslandCompactView: View {
    let chrome: DownloadIslandChrome
    var onExpand: (() -> Void)?
    var onResume: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { onExpand?() }) {
                DownloadIslandPoster(url: chrome.posterURL, size: 23, cornerRadius: 11.5)
            }
            .buttonStyle(.plain)

            Button(action: { onExpand?() }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(chrome.title)
                        .font(.system(size: 8.3, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(chrome.statusText)
                        .font(.system(size: 6.4, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.47))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            compactTrailing
        }
        .padding(.horizontal, 8)
        .frame(
            width: DownloadIslandCapability.compactWidth,
            height: DownloadIslandCapability.compactHeight
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("download.island.compact")
        .animation(nil, value: chrome.isPaused)
        .animation(nil, value: chrome.progress)
    }

    @ViewBuilder
    private var compactTrailing: some View {
        if chrome.isPaused, !chrome.isCompleted {
            Button(action: { onResume?() }) {
                DownloadIslandPauseGlyph(color: DownloadIslandPalette.ringText, height: 11)
                    .frame(width: 23, height: 23)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("继续"))
            .accessibilityIdentifier("download.island.compact.resume")
        } else {
            DownloadIslandProgressRing(progress: chrome.progress, percent: chrome.percent)
                .allowsHitTesting(false)
        }
    }
}

struct DownloadIslandExpandedView: View {
    let chrome: DownloadIslandChrome
    var onToggle: () -> Void
    var onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 13) {
                Button(action: onCollapse) {
                    DownloadIslandPoster(url: chrome.posterURL, size: nil, cornerRadius: 12)
                        .frame(width: 94, height: 56)
                }
                .buttonStyle(.plain)

                Button(action: onCollapse) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chrome.title)
                            .font(.system(size: 15, weight: .semibold))
                            .tracking(-0.3)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("\(chrome.statusText)  •  \(chrome.percent)%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.49))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, DownloadIslandCapability.expandedContentTopInset)
            .padding(.horizontal, 16)

            DownloadIslandProgressBar(progress: chrome.progress)
                .padding(.top, 20)
                .padding(.horizontal, 16)

            HStack {
                Text(chrome.byteLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.38))
                Spacer()
                Button(action: onToggle) {
                    DownloadIslandPauseGlyph(
                        color: DownloadIslandPalette.ink,
                        height: 14,
                        isPlay: chrome.isPaused
                    )
                    .frame(width: 108, height: 36)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(DownloadIslandPauseButtonStyle())
                .accessibilityLabel(chrome.isPaused ? L10n.tr("继续") : L10n.tr("暂停"))
                .accessibilityIdentifier("download.island.expanded.toggle")
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(
            width: DownloadIslandCapability.expandedWidth,
            height: DownloadIslandCapability.expandedHeight,
            alignment: .topLeading
        )
        .accessibilityIdentifier("download.island.expanded")
        .animation(nil, value: chrome.isPaused)
        .animation(nil, value: chrome.progress)
    }
}

struct DownloadIslandPoster: View {
    let url: URL?
    var size: CGFloat?
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let url {
                KFImage(url)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.white.opacity(0.12)
                    .overlay {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.64)
        )
    }
}

struct DownloadIslandProgressRing: View {
    let progress: Double
    let percent: Int
    var size: CGFloat = 23
    var lineWidth: CGFloat = 2
    var percentSize: CGFloat = 5.8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.02), 1))
                .stroke(DownloadIslandPalette.ring, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.system(size: percentSize, weight: .semibold))
                .foregroundStyle(DownloadIslandPalette.ringText)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct DownloadIslandProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.11))
                Capsule()
                    .fill(DownloadIslandPalette.barFill)
                    .frame(width: max(geo.size.width * min(max(progress, 0), 1), 4))
                    .shadow(color: Color(red: 126 / 255, green: 197 / 255, blue: 1).opacity(0.85), radius: 6)
            }
        }
        .frame(height: 6)
    }
}

struct DownloadIslandPauseGlyph: View {
    let color: Color
    var height: CGFloat = 14
    var isPlay: Bool = false

    var body: some View {
        if isPlay {
            Image(systemName: "play.fill")
                .font(.system(size: height * 0.7, weight: .bold))
                .foregroundStyle(color)
        } else {
            HStack(spacing: 4) {
                Capsule().fill(color).frame(width: 4, height: height)
                Capsule().fill(color).frame(width: 4, height: height)
            }
        }
    }
}

#Preview("compact") {
    DownloadIslandCompactView(
        chrome: DownloadIslandChrome(
            taskID: nil,
            title: "Dune: Part Two",
            statusText: L10n.tr("下载中"),
            progress: 0.45,
            isPaused: false,
            isCompleted: false,
            receivedBytes: 1_800_000_000,
            totalBytes: 4_000_000_000,
            posterURL: nil
        )
    )
    .padding()
    .background(Color.black, in: Capsule())
    .padding()
    .background(Color.gray)
}

#Preview("compact paused") {
    DownloadIslandCompactView(
        chrome: DownloadIslandChrome(
            taskID: nil,
            title: "Dune: Part Two",
            statusText: L10n.tr("已暂停"),
            progress: 0.45,
            isPaused: true,
            isCompleted: false,
            receivedBytes: 1_800_000_000,
            totalBytes: 4_000_000_000,
            posterURL: nil
        )
    )
    .padding()
    .background(Color.black, in: Capsule())
    .padding()
    .background(Color.gray)
}

#Preview("expanded") {
    DownloadIslandExpandedView(
        chrome: DownloadIslandChrome(
            taskID: nil,
            title: "Dune: Part Two",
            statusText: L10n.tr("下载中"),
            progress: 0.45,
            isPaused: false,
            isCompleted: false,
            receivedBytes: 1_800_000_000,
            totalBytes: 4_000_000_000,
            posterURL: nil
        ),
        onToggle: {},
        onCollapse: {}
    )
    .padding()
    .background(Color.black, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    .padding()
    .background(Color.gray)
}

struct DownloadIslandMorphChrome: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chrome: DownloadIslandChrome
    let isExpanded: Bool
    var onExpand: (() -> Void)?
    var onResume: (() -> Void)?
    var onToggle: () -> Void
    var onCollapse: () -> Void

    var body: some View {
        let width = isExpanded ? DownloadIslandCapability.expandedWidth : DownloadIslandCapability.compactWidth
        let height = isExpanded ? DownloadIslandCapability.expandedHeight : DownloadIslandCapability.compactHeight
        let corner = isExpanded ? DownloadIslandCapability.expandedCornerRadius : DownloadIslandCapability.compactHeight / 2
        ZStack(alignment: .top) {
            DownloadIslandCompactView(chrome: chrome, onExpand: onExpand, onResume: onResume)
                .opacity(isExpanded ? 0 : 1)
                .allowsHitTesting(!isExpanded)
                .animation(reduceMotion ? nil : (isExpanded ? DownloadIslandMotion.contentOut : DownloadIslandMotion.contentIn), value: isExpanded)
            DownloadIslandExpandedView(chrome: chrome, onToggle: onToggle, onCollapse: onCollapse)
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .animation(reduceMotion ? nil : (isExpanded ? DownloadIslandMotion.contentIn : DownloadIslandMotion.contentOut), value: isExpanded)
        }
        .frame(width: width, height: height, alignment: .top)
        .background(DownloadIslandPalette.background, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

private struct DownloadIslandPauseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum DownloadIslandPalette {
    static let background = Color.black
    static let ink = Color(red: 9 / 255, green: 10 / 255, blue: 12 / 255)
    static let ring = Color(red: 116 / 255, green: 212 / 255, blue: 1)
    static let ringText = Color(red: 223 / 255, green: 242 / 255, blue: 254 / 255)
    static let barFill = LinearGradient(
        colors: [
            Color(red: 116 / 255, green: 212 / 255, blue: 1),
            Color(red: 185 / 255, green: 220 / 255, blue: 1)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}
