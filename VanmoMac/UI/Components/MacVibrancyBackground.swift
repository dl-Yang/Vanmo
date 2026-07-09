import SwiftUI
import AppKit

class TransparentWindowVisualEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
    }
}

struct MacVibrancyBackground: NSViewRepresentable {
    var isDark: Bool
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    private var material: NSVisualEffectView.Material {
        isDark ? .hudWindow : .underWindowBackground
    }

    private var preferredAppearance: NSAppearance? {
        NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = TransparentWindowVisualEffectView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
        if let transparent = nsView as? TransparentWindowVisualEffectView {
            transparent.configureWindow()
        }
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = preferredAppearance
    }
}
