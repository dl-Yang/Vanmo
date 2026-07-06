import SwiftUI
import VanmoCore

struct SubtitleOverlayView: View {
    let content: SubtitleContent?
    let style: SubtitleStyle

    var body: some View {
        VStack {
            switch verticalPlacement {
            case .top:
                positionedSubtitleBody
                    .padding(.top, verticalMargin)
                Spacer()
            case .center:
                Spacer()
                positionedSubtitleBody
                Spacer()
            case .bottom:
                Spacer()
                positionedSubtitleBody
                    .padding(.bottom, verticalMargin)
            }
        }
    }

    private var verticalPlacement: SubtitlePlacement.Vertical {
        if let placement = content?.placement {
            return placement.vertical
        }
        return style.position == .top ? .top : .bottom
    }

    private var verticalMargin: CGFloat {
        content?.placement?.verticalMargin ?? style.bottomPadding
    }

    private var horizontalAlignment: Alignment {
        switch content?.placement?.horizontal {
        case .leading:
            return .leading
        case .trailing:
            return .trailing
        case .center, .none:
            return .center
        }
    }

    private var horizontalPadding: EdgeInsets {
        guard let placement = content?.placement else {
            return EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)
        }
        return EdgeInsets(
            top: 0,
            leading: max(24, placement.leadingMargin),
            bottom: 0,
            trailing: max(24, placement.trailingMargin)
        )
    }

    private var imageSubtitleScale: CGFloat {
        min(0.75, max(0.45, style.fontSize / 32))
    }

    private var positionedSubtitleBody: some View {
        subtitleBody
            .frame(maxWidth: .infinity, alignment: horizontalAlignment)
            .padding(horizontalPadding)
    }

    @ViewBuilder
    private var subtitleBody: some View {
        if let content, !content.isEmpty {
            Group {
                if let attributedText = content.attributedText {
                    AttributedSubtitleLabel(attributedText: attributedText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let text = content.text, !text.isEmpty {
                    Text(text)
                        .font(.system(size: style.fontSize))
                        .fontWeight(.medium)
                        .foregroundStyle(style.textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(style.backgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let uiImage = content.image {
                    ImageSubtitleView(uiImage: uiImage, targetScale: imageSubtitleScale)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: content.text)
        }
    }
}

private struct ImageSubtitleView: View {
    let uiImage: UIImage
    let targetScale: CGFloat

    var body: some View {
        let preferredHeight = max(1, uiImage.size.height * targetScale)

        GeometryReader { proxy in
            let size = displaySize(maxWidth: proxy.size.width)

            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: preferredHeight)
    }

    private func displaySize(maxWidth: CGFloat) -> CGSize {
        let imageSize = uiImage.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let targetWidth = imageSize.width * targetScale
        let targetHeight = imageSize.height * targetScale
        guard targetWidth > maxWidth else {
            return CGSize(width: targetWidth, height: targetHeight)
        }

        let aspectRatio = imageSize.width / imageSize.height
        return CGSize(width: maxWidth, height: maxWidth / aspectRatio)
    }
}

private struct AttributedSubtitleLabel: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = attributedText
    }
}

struct SubtitleStyle {
    var fontSize: CGFloat = 14
    var textColor: Color = .white
    var backgroundColor: Color = Color.black.opacity(0.6)
    var bottomPadding: CGFloat = 40
    var position: SubtitlePosition = .bottom

    enum SubtitlePosition: String {
        case top, bottom
    }
}

/// 字幕样式的全局持久化（UserDefaults）。播放器与设置页共用同一组键。
enum SubtitleStylePreferences {
    static let fontSizeKey = "subtitle.fontSize"
    static let textColorKey = "subtitle.textColorHex"
    static let backgroundColorKey = "subtitle.backgroundColorHex"
    static let positionKey = "subtitle.position"

    static func load() -> SubtitleStyle {
        let defaults = UserDefaults.standard
        var style = SubtitleStyle()
        if let fontSize = defaults.object(forKey: fontSizeKey) as? Double {
            style.fontSize = fontSize
        }
        if let hex = defaults.string(forKey: textColorKey), let color = Color(rgbaHex: hex) {
            style.textColor = color
        }
        if let hex = defaults.string(forKey: backgroundColorKey), let color = Color(rgbaHex: hex) {
            style.backgroundColor = color
        }
        if let raw = defaults.string(forKey: positionKey),
           let position = SubtitleStyle.SubtitlePosition(rawValue: raw) {
            style.position = position
        }
        return style
    }

    static func save(_ style: SubtitleStyle) {
        let defaults = UserDefaults.standard
        defaults.set(Double(style.fontSize), forKey: fontSizeKey)
        defaults.set(style.textColor.rgbaHex, forKey: textColorKey)
        defaults.set(style.backgroundColor.rgbaHex, forKey: backgroundColorKey)
        defaults.set(style.position.rawValue, forKey: positionKey)
    }
}

struct SubtitleSettingsView: View {
    @Binding var style: SubtitleStyle
    @Binding var delay: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("字体") {
                    HStack {
                        Text("大小")
                        Spacer()
                        Stepper("\(Int(style.fontSize))pt", value: $style.fontSize, in: 12...36, step: 2)
                    }

                    ColorPicker("文字颜色", selection: $style.textColor)
                }

                Section("背景") {
                    ColorPicker("背景颜色", selection: $style.backgroundColor)
                }

                Section("时间偏移") {
                    HStack {
                        Text(String(format: "%+.1fs", delay))
                            .monospacedDigit()
                            .frame(width: 60)

                        Slider(value: $delay, in: -10...10, step: 0.1)
                    }

                    HStack {
                        Button("-0.5s") { delay -= 0.5 }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("重置") { delay = 0 }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("+0.5s") { delay += 0.5 }
                            .buttonStyle(.bordered)
                    }
                }

                Section("位置") {
                    Picker("位置", selection: $style.position) {
                        Text("顶部").tag(SubtitleStyle.SubtitlePosition.top)
                        Text("底部").tag(SubtitleStyle.SubtitlePosition.bottom)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("字幕设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SubtitleOverlayView(
            content: SubtitleContent(text: "这是一段字幕文本\nThis is subtitle text"),
            style: SubtitleStyle()
        )
    }
}
