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
            .activityBackgroundTint(DownloadLiveActivityPalette.background)
            .widgetURL(URL(string: "vanmo://downloads"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DownloadLiveActivityPoster(
                        urlString: context.attributes.posterURLString,
                        width: 44,
                        height: 60,
                        cornerRadius: 11
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DownloadLiveActivityPalette.ivory)
                            .lineLimit(1)
                        Text(context.state.isCompleted ? "100% · Ready Offline" : "\(context.state.statusText) · \(context.state.percent)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(context.state.isCompleted ? DownloadLiveActivityPalette.ring : DownloadLiveActivityPalette.muted)
                            .lineLimit(1)
                        Text(context.state.byteLine)
                            .font(.system(size: 10))
                            .foregroundStyle(DownloadLiveActivityPalette.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.state.taskID.isEmpty, !context.state.isCompleted {
                        if context.state.isPaused {
                            Button(intent: ResumeDownloadIntent(taskID: context.state.taskID)) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(DownloadLiveActivityPalette.ring)
                                    .frame(width: 36, height: 36)
                                    .background(DownloadLiveActivityPalette.ring.opacity(0.12), in: Circle())
                                    .overlay(Circle().strokeBorder(DownloadLiveActivityPalette.amberStroke, lineWidth: 0.9))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(intent: PauseDownloadIntent(taskID: context.state.taskID)) {
                                Image(systemName: "pause.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(DownloadLiveActivityPalette.ring)
                                    .frame(width: 36, height: 36)
                                    .background(DownloadLiveActivityPalette.ring.opacity(0.12), in: Circle())
                                    .overlay(Circle().strokeBorder(DownloadLiveActivityPalette.amberStroke, lineWidth: 0.9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DownloadLiveActivityProgressBar(progress: context.state.isCompleted ? 1 : context.state.progress)
                        .padding(.top, 4)
                }
            } compactLeading: {
                DownloadLiveActivityPoster(
                    urlString: context.attributes.posterURLString,
                    width: 22,
                    height: 22,
                    cornerRadius: 11
                )
            } compactTrailing: {
                if context.state.isPaused, !context.state.isCompleted {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DownloadLiveActivityPalette.ring)
                        .frame(width: 20, height: 20)
                } else {
                    DownloadLiveActivityProgressRing(
                        progress: context.state.isCompleted ? 1 : context.state.progress,
                        percent: context.state.percent
                    )
                }
            } minimal: {
                if context.state.isPaused, !context.state.isCompleted {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DownloadLiveActivityPalette.ring)
                } else {
                    ProgressView(value: context.state.progress)
                        .tint(DownloadLiveActivityPalette.ring)
                }
            }
            .keylineTint(DownloadLiveActivityPalette.ring)
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
                    width: 44,
                    height: 60,
                    cornerRadius: 11
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DownloadLiveActivityPalette.ivory)
                        .lineLimit(1)
                    Text(state.isCompleted ? "\(state.percent)% · \(state.statusText)" : "\(state.statusText) · \(state.percent)%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(state.isCompleted ? DownloadLiveActivityPalette.ring : DownloadLiveActivityPalette.muted)
                        .lineLimit(1)
                    Text(state.byteLine)
                        .font(.system(size: 10))
                        .foregroundStyle(DownloadLiveActivityPalette.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if showsActions, !state.taskID.isEmpty, !state.isCompleted {
                    if state.isPaused {
                        Button(intent: ResumeDownloadIntent(taskID: state.taskID)) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DownloadLiveActivityPalette.ring)
                                .frame(width: 36, height: 36)
                                .background(DownloadLiveActivityPalette.ring.opacity(0.12), in: Circle())
                                .overlay(Circle().strokeBorder(DownloadLiveActivityPalette.amberStroke, lineWidth: 0.9))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(intent: PauseDownloadIntent(taskID: state.taskID)) {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(DownloadLiveActivityPalette.ring)
                                .frame(width: 36, height: 36)
                                .background(DownloadLiveActivityPalette.ring.opacity(0.12), in: Circle())
                                .overlay(Circle().strokeBorder(DownloadLiveActivityPalette.amberStroke, lineWidth: 0.9))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            DownloadLiveActivityProgressBar(progress: state.isCompleted ? 1 : state.progress)
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
                .strokeBorder(DownloadLiveActivityPalette.glassStroke, lineWidth: 0.75)
        )
    }

    private var placeholder: some View {
        Color.white.opacity(0.12)
            .overlay {
                Image(systemName: "arrow.down")
                    .font(.system(size: min(width, height) * 0.40, weight: .bold))
                    .foregroundStyle(DownloadLiveActivityPalette.ring)
            }
    }

    private func isRemoteHTTP(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

private struct CatEarMiniShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: w * 0.08, y: 0))
        path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.65))
        path.move(to: CGPoint(x: w * 0.65, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.92, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        return path
    }
}

private struct DownloadLiveActivityProgressRing: View {
    let progress: Double
    let percent: Int

    var body: some View {
        VStack(spacing: -1.5) {
            CatEarMiniShape()
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round))
                .frame(width: 11, height: 4)

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0.04), 1))
                    .stroke(DownloadLiveActivityPalette.ring, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percent)")
                    .font(.system(size: 5.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(DownloadLiveActivityPalette.ring)
            }
            .frame(width: 16, height: 16)
        }
    }
}

private struct DownloadLiveActivityProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.14))
                Capsule()
                    .fill(DownloadLiveActivityPalette.ring)
                    .frame(width: max(geo.size.width * min(max(progress, 0), 1), 4))
            }
        }
        .frame(height: 4)
    }
}

private enum DownloadLiveActivityPalette {
    static let background = Color(red: 5 / 255, green: 5 / 255, blue: 7 / 255)
    static let ring = Color(red: 255 / 255, green: 181 / 255, blue: 71 / 255)
    static let ivory = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255)
    static let muted = Color(red: 168 / 255, green: 165 / 255, blue: 158 / 255)
    static let dim = Color(red: 114 / 255, green: 112 / 255, blue: 107 / 255)
    static let glassStroke = Color(red: 244 / 255, green: 239 / 255, blue: 230 / 255).opacity(0.14)
    static let amberStroke = Color(red: 255 / 255, green: 181 / 255, blue: 71 / 255).opacity(0.45)
}
