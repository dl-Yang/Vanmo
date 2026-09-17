import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct VanmoDownloadWidgetBundle: WidgetBundle {
    var body: some Widget {
        DownloadLiveActivityWidget()
    }
}

struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadLiveActivityAttributes.self) { context in
            DownloadLiveActivityExpandedCard(
                state: context.state,
                posterURLString: context.attributes.posterURLString,
                showsActions: true
            )
            .padding(16)
            .widgetURL(URL(string: "vanmo://downloads"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DownloadLiveActivityPoster(
                        urlString: context.attributes.posterURLString,
                        width: 64,
                        height: 38,
                        cornerRadius: 8
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text("\(context.state.statusText)  •  \(context.state.percent)%")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.49))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        DownloadLiveActivityProgressBar(progress: context.state.progress)
                        HStack {
                            Text(context.state.byteLine)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.white.opacity(0.38))
                            Spacer()
                            if !context.state.taskID.isEmpty, !context.state.isCompleted {
                                if context.state.isPaused {
                                    Button(intent: ResumeDownloadIntent(taskID: context.state.taskID)) {
                                        DownloadLiveActivityPauseGlyph(isPlay: true)
                                            .frame(width: 72, height: 28)
                                            .background(Color.white, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .tint(.white)
                                } else {
                                    Button(intent: PauseDownloadIntent(taskID: context.state.taskID)) {
                                        DownloadLiveActivityPauseGlyph(isPlay: false)
                                            .frame(width: 72, height: 28)
                                            .background(Color.white, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                    .tint(.white)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                DownloadLiveActivityPoster(
                    urlString: context.attributes.posterURLString,
                    width: 20,
                    height: 20,
                    cornerRadius: 10
                )
            } compactTrailing: {
                if context.state.isPaused, !context.state.isCompleted {
                    DownloadLiveActivityPauseGlyph(isPlay: false, color: DownloadLiveActivityPalette.ringText, height: 9)
                        .frame(width: 20, height: 20)
                } else {
                    DownloadLiveActivityProgressRing(
                        progress: context.state.progress,
                        percent: context.state.percent
                    )
                }
            } minimal: {
                if context.state.isPaused, !context.state.isCompleted {
                    DownloadLiveActivityPauseGlyph(isPlay: false, color: DownloadLiveActivityPalette.ringText, height: 8)
                } else {
                    ProgressView(value: context.state.progress)
                        .tint(DownloadLiveActivityPalette.ring)
                }
            }
            .widgetURL(URL(string: "vanmo://downloads"))
        }
    }
}

private struct DownloadLiveActivityExpandedCard: View {
    let state: DownloadLiveActivityAttributes.ContentState
    let posterURLString: String?
    var showsActions: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                DownloadLiveActivityPoster(
                    urlString: posterURLString,
                    width: 94,
                    height: 56,
                    cornerRadius: 12
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("\(state.statusText)  •  \(state.percent)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.49))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            DownloadLiveActivityProgressBar(progress: state.progress)
            HStack {
                Text(state.byteLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.38))
                Spacer()
                if showsActions, !state.taskID.isEmpty, !state.isCompleted {
                    if state.isPaused {
                        Button(intent: ResumeDownloadIntent(taskID: state.taskID)) {
                            DownloadLiveActivityPauseGlyph(isPlay: true)
                                .frame(width: 108, height: 36)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(intent: PauseDownloadIntent(taskID: state.taskID)) {
                            DownloadLiveActivityPauseGlyph(isPlay: false)
                                .frame(width: 108, height: 36)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct DownloadLiveActivityPoster: View {
    let urlString: String?
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), isRemoteHTTP(url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.64)
        )
    }

    private var placeholder: some View {
        Color.white.opacity(0.12)
            .overlay {
                Image(systemName: "arrow.down")
                    .font(.system(size: min(width, height) * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
    }

    private func isRemoteHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

private struct DownloadLiveActivityProgressRing: View {
    let progress: Double
    let percent: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 2)
            Circle()
                .trim(from: 0, to: min(max(progress, 0.02), 1))
                .stroke(DownloadLiveActivityPalette.ring, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(percent)")
                .font(.system(size: 5.8, weight: .semibold))
                .foregroundStyle(DownloadLiveActivityPalette.ringText)
        }
        .frame(width: 20, height: 20)
    }
}

private struct DownloadLiveActivityProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.11))
                Capsule()
                    .fill(DownloadLiveActivityPalette.barFill)
                    .frame(width: max(geo.size.width * min(max(progress, 0), 1), 4))
            }
        }
        .frame(height: 6)
    }
}

private struct DownloadLiveActivityPauseGlyph: View {
    var isPlay: Bool = false
    var color: Color = DownloadLiveActivityPalette.ink
    var height: CGFloat = 12

    var body: some View {
        if isPlay {
            Image(systemName: "play.fill")
                .font(.system(size: height * 0.7, weight: .bold))
                .foregroundStyle(color)
        } else {
            HStack(spacing: 3) {
                Capsule().fill(color).frame(width: 3.5, height: height)
                Capsule().fill(color).frame(width: 3.5, height: height)
            }
        }
    }
}

private enum DownloadLiveActivityPalette {
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
