import SwiftUI

struct SubtitleOverlayView: View {
    let content: SubtitleContent?
    let style: SubtitleStyle

    var body: some View {
        VStack {
            Spacer()

            if let content, !content.isEmpty {
                Group {
                    if let text = content.text, !text.isEmpty {
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
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: style.fontSize * 2)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, style.bottomPadding)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: content.text)
            }
        }
    }
}

struct SubtitleStyle {
    var fontSize: CGFloat = 14
    var textColor: Color = .white
    var backgroundColor: Color = Color.black.opacity(0.6)
    var bottomPadding: CGFloat = 40
    var position: SubtitlePosition = .bottom

    enum SubtitlePosition {
        case top, bottom
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
