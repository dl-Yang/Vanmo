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
        let progress = (style.fontSize - 12) / 24
        return min(1, max(0.5, 0.5 + progress * 0.5))
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
                if let attributedText = content.richAttributedText {
                    attributedSubtitleLabel(attributedText)
                } else if let uiImage = content.image {
                    ImageSubtitleView(uiImage: uiImage, targetScale: imageSubtitleScale)
                } else if let attributedText = content.attributedText {
                    attributedSubtitleLabel(attributedText)
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
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: content.text)
        }
    }

    private func attributedSubtitleLabel(_ attributedText: NSAttributedString) -> some View {
        AttributedSubtitleLabel(
            attributedText: attributedText,
            style: style
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(style.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private extension SubtitleContent {
    var richAttributedText: NSAttributedString? {
        guard let attributedText else { return nil }
        let visibleText = attributedText.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return visibleText.isEmpty ? nil : attributedText
    }
}

private struct ImageSubtitleView: View {
    let uiImage: UIImage
    let targetScale: CGFloat

    var body: some View {
        ImageSubtitleLayout(imageSize: uiImage.size, relativeScale: targetScale) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        }
        .onChange(of: targetScale, initial: true) { _, scale in
#if DEBUG
            print(
                "[Debug][Subtitle] imageScale=\(scale) "
                    + "width=\(Int(uiImage.size.width)) height=\(Int(uiImage.size.height))"
            )
#endif
        }
    }
}

private struct ImageSubtitleLayout: Layout {
    let imageSize: CGSize
    let relativeScale: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: 1, height: 1)
        }

        let availableWidth = proposal.width ?? imageSize.width
        let aspectRatio = imageSize.width / imageSize.height
        let fittedWidth = min(imageSize.width, availableWidth)
        let width = max(1, fittedWidth * relativeScale)
        return CGSize(width: width, height: max(1, width / aspectRatio))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        subview.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(bounds.size)
        )
    }
}

private struct AttributedSubtitleLabel: UIViewRepresentable {
    let attributedText: NSAttributedString
    let style: SubtitleStyle

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.numberOfLines = 0
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = false
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let styledText = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: styledText.length)
        guard fullRange.length > 0 else {
            label.attributedText = styledText
            return
        }

        styledText.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let font = (value as? UIFont)?.withSize(style.fontSize)
                ?? UIFont.systemFont(ofSize: style.fontSize, weight: .medium)
            styledText.addAttribute(.font, value: font, range: range)
        }
        styledText.addAttribute(.foregroundColor, value: UIColor(style.textColor), range: fullRange)
        label.attributedText = styledText
    }
}

struct SubtitleStyle {
    var fontSize: CGFloat = 18
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

struct SubtitleStylePreview: View {
    let style: SubtitleStyle

    private var previewStyle: SubtitleStyle {
        var preview = style
        preview.bottomPadding = 14
        preview.position = .bottom
        return preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.10, blue: 0.15),
                        Color(red: 0.02, green: 0.03, blue: 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "film.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.12))

                SubtitleOverlayView(
                    content: SubtitleContent(text: L10n.tr("这是一段字幕文本")),
                    style: previewStyle
                )
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(L10n.tr("位图字幕仅支持大小调整"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("字幕实时预览"))
    }
}

struct SubtitleSettingsView: View {
    @Binding var style: SubtitleStyle
    @Binding var delay: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("实时预览")) {
                    SubtitleStylePreview(style: style)
                }

                Section(L10n.tr("字体")) {
                    HStack {
                        Text(L10n.tr("大小"))
                        Spacer()
                        Stepper("\(Int(style.fontSize))pt", value: $style.fontSize, in: 12...36, step: 2)
                    }

                    ColorPicker(L10n.tr("文字颜色"), selection: $style.textColor)
                }

                Section(L10n.tr("背景")) {
                    ColorPicker(L10n.tr("背景颜色"), selection: $style.backgroundColor)
                }

                Section(L10n.tr("时间偏移")) {
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
                        Button(L10n.tr("重置")) { delay = 0 }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("+0.5s") { delay += 0.5 }
                            .buttonStyle(.bordered)
                    }
                }

                Section(L10n.tr("位置")) {
                    Picker(L10n.tr("位置"), selection: $style.position) {
                        Text(L10n.tr("顶部")).tag(SubtitleStyle.SubtitlePosition.top)
                        Text(L10n.tr("底部")).tag(SubtitleStyle.SubtitlePosition.bottom)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(L10n.tr("字幕设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("完成")) { dismiss() }
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
