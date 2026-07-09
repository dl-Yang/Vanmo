import AppKit
import SwiftUI
import VanmoCore

struct MacKSPlayerView: NSViewRepresentable {
    let videoView: NSView?
    let scaleMode: VideoScaleMode

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        attachVideoView(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attachVideoView(to: nsView)
    }

    private func attachVideoView(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        guard let videoView else { return }

        videoView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: container.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
