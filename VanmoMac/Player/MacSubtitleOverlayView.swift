import SwiftUI
import VanmoCore

struct MacSubtitleOverlayView: View {
    let text: String?
    let style: MacSubtitleStyle

    var body: some View {
        VStack {
            if style.position == .top {
                subtitleBody
                    .padding(.top, style.verticalPadding)
                Spacer()
            } else {
                Spacer()
                subtitleBody
                    .padding(.bottom, style.verticalPadding)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var subtitleBody: some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.system(size: style.fontSize, weight: .medium))
                .foregroundStyle(style.textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(style.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 24)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: text)
        }
    }
}

struct MacSubtitleStyle: Equatable {
    var fontSize: CGFloat = 18
    var textColor: Color = .white
    var backgroundColor: Color = Color.black.opacity(0.6)
    var verticalPadding: CGFloat = 120
    var position: MacSubtitlePosition = .bottom

    enum MacSubtitlePosition: String {
        case top
        case bottom
    }
}

enum MacSubtitleStylePreferences {
    static let fontSizeKey = "subtitle.fontSize"
    static let textColorKey = "subtitle.textColorHex"
    static let backgroundColorKey = "subtitle.backgroundColorHex"
    static let positionKey = "subtitle.position"

    static func load() -> MacSubtitleStyle {
        let defaults = UserDefaults.standard
        var style = MacSubtitleStyle()
        if let fontSize = defaults.object(forKey: fontSizeKey) as? Double {
            style.fontSize = fontSize
        }
        if let hex = defaults.string(forKey: textColorKey), let color = color(fromHex: hex) {
            style.textColor = color
        }
        if let hex = defaults.string(forKey: backgroundColorKey), let color = color(fromHex: hex) {
            style.backgroundColor = color
        }
        if let raw = defaults.string(forKey: positionKey) {
            style.position = raw == "top" ? .top : .bottom
        }
        return style
    }

    private static func color(fromHex hex: String) -> Color? {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.hasPrefix("#") { sanitized.removeFirst() }
        guard sanitized.count == 8, let value = UInt64(sanitized, radix: 16) else { return nil }
        let r = Double((value >> 24) & 0xFF) / 255
        let g = Double((value >> 16) & 0xFF) / 255
        let b = Double((value >> 8) & 0xFF) / 255
        let a = Double(value & 0xFF) / 255
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}
