import AVKit
import SwiftUI

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(red: 0xF4 / 255, green: 0xEF / 255, blue: 0xE6 / 255, alpha: 1)
        view.activeTintColor = UIColor(red: 0xFF / 255, green: 0xB5 / 255, blue: 0x47 / 255, alpha: 1)
        view.prioritizesVideoDevices = true
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AVRoutePickerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 24, height: proposal.height ?? 24)
    }
}

#Preview {
    AirPlayRouteButton()
        .frame(width: 40, height: 40)
        .background(.black)
}
