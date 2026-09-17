import SwiftUI
import VanmoCore

private enum DownloadNotchBarMode: Equatable {
    case hidden
    case flying
    case visible
}

/// Leading solid-blue status-bar capsule for notch iPhones without a Dynamic Island.
/// The app status bar is hidden so this overlay is not covered by the system time.
/// Visual reference: system location pill (`tem/1.PNG`). No video title or poster.
struct DownloadNotchStatusBarHost: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var hero: DownloadHeroController
    @State private var mode: DownloadNotchBarMode = .hidden
    @State private var displayedActivityID: UUID?
    @State private var chrome: DownloadIslandChrome?
    @State private var pendingAfterCompletion: DownloadIslandChrome?
    @State private var dismissProgress: CGFloat = 0
    @State private var isShowingCompletion = false
    @State private var isDismissing = false
    @State private var appearGeneration = 0
    @State private var pulseTask: Task<Void, Never>?

    var body: some View {
        Group {
            if shouldShow, let chrome {
                notchContent(chrome)
                    .frame(
                        width: DownloadIslandCapability.notchCapsuleLeading
                            + DownloadIslandCapability.notchCapsuleWidth,
                        height: DownloadIslandCapability.notchStatusBarHeight,
                        alignment: .leading
                    )
                    .fixedSize(horizontal: true, vertical: true)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(isInteractive)
                    .accessibilityIdentifier("download.notch.status.bar")
            }
        }
        .onAppear {
            DownloadIslandHandoff.shared.applyStatusBarPolicy()
            apply(selectedPresentation)
        }
        .onChange(of: downloadManager.tasks) { _, tasks in
            apply(
                DownloadActivityPresentation.select(
                    from: tasks,
                    previouslyDisplayedID: displayedActivityID
                )
            )
        }
        .onChange(of: hero.landedAt) { _, landedAt in
            guard landedAt != nil else { return }
            apply(selectedPresentation, landHandOff: true)
        }
        .onChange(of: hero.isFlying) { _, flying in
            if flying {
                mode = .flying
                return
            }
            if mode == .flying {
                apply(selectedPresentation, landHandOff: true)
            }
        }
        .onDisappear {
            pulseTask?.cancel()
        }
    }

    @ViewBuilder
    private func notchContent(_ chrome: DownloadIslandChrome) -> some View {
        Button(action: { handleCapsuleTap(chrome) }) {
            DownloadNotchStatusCapsule(
                progress: chrome.isCompleted ? 1 : chrome.progress,
                isPaused: chrome.isPaused && !chrome.isCompleted,
                isCompleted: chrome.isCompleted
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(1 - 0.28 * dismissProgress, anchor: .center)
        .opacity(1 - Double(min(max(dismissProgress, 0), 1)))
        .padding(.leading, DownloadIslandCapability.notchCapsuleLeading)
        .accessibilityLabel(chrome.isPaused && !chrome.isCompleted ? L10n.tr("继续") : L10n.tr("下载进度"))
        .accessibilityValue("\(chrome.percent)%")
        .accessibilityIdentifier("download.notch.status.capsule")
        .animation(nil, value: chrome.isPaused)
        .animation(nil, value: chrome.progress)
    }

    private func handleCapsuleTap(_ chrome: DownloadIslandChrome) {
        if chrome.isPaused, !chrome.isCompleted {
            resumeDownload(chrome)
            return
        }
        appState.openDownloads()
    }

    private var shouldShow: Bool {
        DownloadIslandCapability.hasNotchStatusBar
            && chrome != nil
            && !hero.isFlying
            && (mode == .visible || isDismissing)
    }

    private var isInteractive: Bool {
        hero.showsDestinationChrome && dismissProgress < 0.5 && !isDismissing
    }

    private var selectedPresentation: DownloadActivityPresentation {
        DownloadActivityPresentation.select(
            from: downloadManager.tasks,
            previouslyDisplayedID: displayedActivityID
        )
    }

    private func apply(
        _ selected: DownloadActivityPresentation,
        preferAppear: Bool = false,
        landHandOff: Bool = false
    ) {
        guard DownloadIslandCapability.hasNotchStatusBar else { return }
        if isDismissing {
            return
        }

        if let task = selected.task {
            displayedActivityID = task.id
            let next = DownloadIslandChrome.make(from: selected, task: task)
            if selected.didCompleteCurrent {
                pendingAfterCompletion = next
                showCompletedThenDismiss(completedChrome(from: selected, fallback: next))
                return
            }
            if isShowingCompletion {
                pendingAfterCompletion = next
                return
            }
            reveal(next, preferAppear: preferAppear, landHandOff: landHandOff)
            return
        }

        if selected.didCompleteCurrent {
            pendingAfterCompletion = nil
            showCompletedThenDismiss(completedChrome(from: selected, fallback: chrome))
            return
        }

        if chrome != nil {
            beginCollapseDismiss()
        }
    }

    private func completedChrome(
        from selected: DownloadActivityPresentation,
        fallback: DownloadIslandChrome?
    ) -> DownloadIslandChrome {
        let completed = latestCompletedTask
        return DownloadIslandChrome(
            taskID: completed?.id ?? fallback?.taskID,
            title: completed.map { DownloadActivityPresentation.title(for: $0.request) } ?? fallback?.title ?? selected.title,
            statusText: L10n.tr("已完成"),
            progress: 1,
            isPaused: false,
            isCompleted: true,
            receivedBytes: completed?.receivedBytes ?? fallback?.receivedBytes ?? 0,
            totalBytes: completed?.totalBytes ?? fallback?.totalBytes ?? 0,
            posterURL: completed?.request.postUrl ?? fallback?.posterURL ?? selected.posterURL
        )
    }

    private func reveal(
        _ next: DownloadIslandChrome,
        preferAppear: Bool,
        landHandOff: Bool
    ) {
        if mode == .visible {
            chrome = next
            return
        }

        if landHandOff || mode == .flying || hero.isFlying {
            cancelPendingHide()
            chrome = next
            if hero.isFlying, !landHandOff {
                mode = .flying
                return
            }
            playAppear()
#if DEBUG
            print("[Debug][Downloads] notch land status bar")
#endif
            return
        }

        cancelPendingHide()
        pendingAfterCompletion = nil
        chrome = next
        if preferAppear || mode == .hidden {
            playAppear()
            return
        }
        adoptVisibleWithoutAppear()
    }

    private func adoptVisibleWithoutAppear() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mode = .visible
            dismissProgress = 0
        }
    }

    private func playAppear() {
        appearGeneration += 1
        let generation = appearGeneration
        mode = .visible
        if reduceMotion {
            dismissProgress = 0
            return
        }
        dismissProgress = 1
        DispatchQueue.main.async {
            guard generation == appearGeneration, mode == .visible, !isDismissing else { return }
            withAnimation(DownloadIslandMotion.appear) {
                dismissProgress = 0
            }
        }
    }

    private func resumeDownload(_ chrome: DownloadIslandChrome) {
        guard let id = chrome.taskID, chrome.isPaused, !chrome.isCompleted else { return }
#if DEBUG
        print("[Debug][Downloads] notch status resume task=\(id.uuidString)")
#endif
        Task { await DownloadManager.shared.resume(id) }
    }

    private func showCompletedThenDismiss(_ next: DownloadIslandChrome) {
        if isShowingCompletion || isDismissing {
            return
        }
        pulseTask?.cancel()
        isDismissing = false
        dismissProgress = 0
        isShowingCompletion = true
        chrome = next
        if mode == .hidden || mode == .flying {
            mode = .visible
        }
        pulseTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            finishCompletionPulse()
        }
    }

    private func finishCompletionPulse() {
        if let pending = pendingAfterCompletion {
            pendingAfterCompletion = nil
            isShowingCompletion = false
            isDismissing = false
            chrome = pending
            if mode == .hidden || mode == .flying {
                mode = .visible
            }
            return
        }
        beginCollapseDismiss()
    }

    private func beginCollapseDismiss() {
        guard chrome != nil, !isDismissing else { return }
        appearGeneration += 1
        isShowingCompletion = false
        pulseTask?.cancel()
        if reduceMotion {
            isDismissing = true
            finishHidden()
            return
        }
        withAnimation(DownloadIslandMotion.dismiss) {
            isDismissing = true
            dismissProgress = 1
        }
        pulseTask = Task {
            try? await Task.sleep(nanoseconds: 360_000_000)
            guard !Task.isCancelled else { return }
            finishHidden()
        }
    }

    private func finishHidden() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            chrome = nil
            dismissProgress = 0
            isDismissing = false
            displayedActivityID = nil
            pendingAfterCompletion = nil
            mode = .hidden
        }
        apply(selectedPresentation)
    }

    private func cancelPendingHide() {
        appearGeneration += 1
        pulseTask?.cancel()
        pulseTask = nil
        isShowingCompletion = false
        isDismissing = false
        dismissProgress = 0
        pendingAfterCompletion = nil
    }

    private var latestCompletedTask: DownloadTaskSnapshot? {
        downloadManager.tasks
            .filter { $0.status == .completed }
            .max { $0.updatedAt < $1.updatedAt }
    }
}

#Preview("notch downloading") {
    DownloadNotchStatusBarPreview(isPaused: false)
}

#Preview("notch paused") {
    DownloadNotchStatusBarPreview(isPaused: true)
}

private enum DownloadNotchPalette {
    /// Dark-mode system blue from the location pill in `tem/1.PNG`.
    static let fill = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    static let progressTrack = Color.white.opacity(0.28)
}

private struct DownloadNotchStatusCapsule: View {
    let progress: Double
    let isPaused: Bool
    let isCompleted: Bool

    var body: some View {
        let width = DownloadIslandCapability.notchCapsuleWidth
        let height = DownloadIslandCapability.notchCapsuleHeight
        let lineWidth = DownloadIslandCapability.notchCapsuleLineWidth
        let inset = lineWidth / 2
        ZStack {
            Capsule()
                .fill(DownloadNotchPalette.fill)
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Capsule()
                .inset(by: inset)
                .stroke(DownloadNotchPalette.progressTrack, lineWidth: lineWidth)
            Capsule()
                .inset(by: inset)
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private var symbolName: String {
        if isCompleted { return "checkmark" }
        if isPaused { return "pause.fill" }
        return "arrow.down"
    }
}

private struct DownloadNotchStatusBarPreview: View {
    let isPaused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            DownloadNotchStatusCapsule(
                progress: 0.45,
                isPaused: isPaused,
                isCompleted: false
            )
            .padding(.leading, DownloadIslandCapability.notchCapsuleLeading)
            .padding(.top, 11)
        }
        .ignoresSafeArea(edges: .top)
    }
}
