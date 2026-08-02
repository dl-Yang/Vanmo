import AppKit
import SwiftData
import SwiftUI
import VanmoCore

/// 承载播放器的独立 macOS 窗口。
/// 播放内容从主窗口分离，使用标准可缩放窗口 + 黑色内容区，
/// 关闭窗口时由 `onWindowClosed` 通知 AppState 停止播放并清理状态。
@MainActor
final class MacPlayerWindowController: NSWindowController, NSWindowDelegate {
    private let onWindowClosed: () -> Void

    init(
        item: MediaItem,
        startPosition: TimeInterval,
        appState: MacAppState,
        libraryViewModel: MacLibraryViewModel,
        connectionsViewModel: MacConnectionsViewModel,
        modelContainer: ModelContainer,
        onWindowClosed: @escaping () -> Void
    ) {
        self.onWindowClosed = onWindowClosed

        let playerView = MacPlayerView(item: item, startPosition: startPosition)
            .environmentObject(appState)
            .environmentObject(libraryViewModel)
            .environmentObject(connectionsViewModel)
            .modelContainer(modelContainer)

        let window = NSWindow(
            contentRect: Self.initialContentRect(for: item),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = item.displayTitle
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 960, height: 540)
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: playerView)
        window.setFrameAutosaveName("Vanmo.PlayerWindow")
        window.collectionBehavior.insert(.fullScreenPrimary)

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPlayer() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onWindowClosed()
    }

    // MARK: - 初始窗口尺寸

    private static func initialContentRect(for item: MediaItem) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var size = preferredContentSize(for: item)

        let maxSize = NSSize(
            width: screen.width * 0.9,
            height: screen.height * 0.9
        )
        if size.width > maxSize.width || size.height > maxSize.height {
            let scale = min(maxSize.width / size.width, maxSize.height / size.height)
            size = NSSize(width: size.width * scale, height: size.height * scale)
        }

        return NSRect(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 以 1280×720 为基准，按视频实际宽高比等比缩放初始窗口。
    private static func preferredContentSize(for item: MediaItem) -> NSSize {
        let baseWidth: CGFloat = 1280
        let baseHeight: CGFloat = 720
        guard let videoWidth = item.videoWidth,
              let videoHeight = item.videoHeight,
              videoWidth > 0, videoHeight > 0 else {
            return NSSize(width: baseWidth, height: baseHeight)
        }

        let aspect = CGFloat(videoWidth) / CGFloat(videoHeight)
        let baseAspect = baseWidth / baseHeight
        if aspect >= baseAspect {
            return NSSize(width: baseWidth, height: baseWidth / aspect)
        }
        return NSSize(width: baseHeight * aspect, height: baseHeight)
    }
}
