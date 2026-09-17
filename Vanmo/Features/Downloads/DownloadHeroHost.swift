import Kingfisher
import SwiftUI
import UIKit
import VanmoCore

/// Owns the in-app island → system Dynamic Island handoff.
/// `ContentView` observes only `hidesStatusBar` so progress ticks cannot remount the player.
@MainActor
final class DownloadIslandHandoff: ObservableObject {
    static let shared = DownloadIslandHandoff()

    @Published var hidesStatusBar = true
    private(set) var isParked = false

    func resignToSystemIsland() {
        isParked = true
        hidesStatusBar = false
    }

    func becomeActive() {
        isParked = false
        applyStatusBarPolicy()
    }

    /// Island and notch phones hide the system status bar so in-app download chrome is not covered.
    func applyStatusBarPolicy() {
        if isParked {
            hidesStatusBar = false
            return
        }
        hidesStatusBar = DownloadIslandCapability.hasDynamicIsland
            || DownloadIslandCapability.hasNotchStatusBar
    }
}

struct DownloadHeroHost: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var hero: DownloadHeroController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let screen = geo.frame(in: .global)
            ZStack {
                Color.clear
                    .onAppear {
                        updateIslandDestination(screen: screen, safeTop: geo.safeAreaInsets.top)
                    }
                    .onChange(of: geo.size) { _, _ in
                        updateIslandDestination(
                            screen: geo.frame(in: .global),
                            safeTop: geo.safeAreaInsets.top
                        )
                    }
                if hero.isFlying {
                    flightCapsule
                        .opacity(hero.capsuleOpacity)
                        .position(DownloadHeroLayout.localPoint(hero.capsuleCenter, in: screen))
                        .accessibilityHidden(true)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: downloadManager.tasks) { _, tasks in
            DownloadLiveActivityBridge.shared.sync(tasks: tasks)
        }
        .onChange(of: scenePhase) { _, _ in
            DownloadLiveActivityBridge.shared.sync(tasks: downloadManager.tasks)
        }
        .onAppear {
            DownloadLiveActivityBridge.shared.sync(tasks: downloadManager.tasks)
        }
        .onReceive(NotificationCenter.default.publisher(for: .downloadHeroRequested)) { notification in
            guard let request = notification.object as? DownloadHeroRequest else { return }
            updateHeroDestinationFromWindow()
            hero.requestFlight(
                title: request.title,
                posterURL: request.posterURL,
                reduceMotion: reduceMotion
            )
        }
    }

    @ViewBuilder
    private var flightCapsule: some View {
        if DownloadIslandCapability.hasDynamicIsland {
            let selected = DownloadActivityPresentation.select(from: downloadManager.tasks)
            DownloadHeroFlightCapsule(
                title: hero.title,
                posterURL: hero.posterURL,
                progress: selected.shouldEnd ? 1 : selected.progress,
                isCompleted: selected.shouldEnd,
                isPaused: selected.task?.status == .paused,
                morphProgress: hero.morphProgress,
                size: hero.capsuleSize
            )
        } else {
            DownloadHeroCapsule(title: hero.title, posterURL: hero.posterURL)
                .frame(width: hero.capsuleSize.width, height: hero.capsuleSize.height)
                .clipShape(Capsule())
                .scaleEffect(hero.capsuleScale)
        }
    }

    private func updateIslandDestination(screen: CGRect, safeTop: CGFloat) {
        let frame = Self.destinationFrame(in: screen, safeTop: safeTop)
        guard hero.destinationFrame != frame else { return }
        DispatchQueue.main.async {
            hero.destinationFrame = frame
        }
    }

    private func updateHeroDestinationFromWindow() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
        else { return }
        let frame = Self.destinationFrame(
            in: window.bounds,
            safeTop: window.safeAreaInsets.top
        )
        guard hero.destinationFrame != frame else { return }
        hero.destinationFrame = frame
    }

    private static func destinationFrame(in screen: CGRect, safeTop: CGFloat) -> CGRect {
        if DownloadIslandCapability.hasDynamicIsland {
            return DownloadIslandCapability.islandFrame(in: screen, safeAreaTop: safeTop)
        }
        if DownloadIslandCapability.hasNotchStatusBar {
            return DownloadIslandCapability.notchLandingFrame(in: screen)
        }
        return DownloadIslandCapability.fallbackBarFrame(in: screen, safeAreaTop: safeTop)
    }
}

struct DownloadIslandRingHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var hero: DownloadHeroController
    @State private var mode: DownloadIslandMode = .hidden
    @State private var displayedActivityID: UUID?
    @State private var chrome: DownloadIslandChrome?
    @State private var pendingAfterCompletion: DownloadIslandChrome?
    @State private var dismissProgress: CGFloat = 0
    @State private var isShowingCompletion = false
    @State private var isDismissing = false
    @State private var appearGeneration = 0
    @State private var pulseTask: Task<Void, Never>?
    @State private var blobGlobalFrame: CGRect = .zero

    var body: some View {
        islandContent
            .ignoresSafeArea()
            .onAppear {
                apply(selectedPresentation)
#if DEBUG
                installDebugWalkObservers()
#endif
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
            .onChange(of: scenePhase) { oldPhase, phase in
                handleScenePhase(phase, from: oldPhase)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                hideForSystemHandoff()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                restoreFromSystemHandoff()
            }
            .onDisappear {
                pulseTask?.cancel()
            }
    }

    @ViewBuilder
    private var islandContent: some View {
        if shouldShow, let chrome {
            ZStack(alignment: .top) {
                if mode == .expanded {
                    IslandOutsidePressCatcher(
                        onPress: collapseToCompact,
                        passthroughGlobalFrame: blobGlobalFrame
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                }

                Capsule()
                    .fill(DownloadIslandPalette.background)
                    .frame(
                        width: DownloadIslandCapability.islandWidth,
                        height: DownloadIslandCapability.islandHeight
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, DownloadIslandCapability.islandTopInset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    chromeView(chrome)
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: DownloadIslandBlobFrameKey.self,
                                    value: geo.frame(in: .global)
                                )
                            }
                        }
                    if mode == .compact {
                        Color.clear
                            .frame(
                                width: DownloadIslandCapability.compactWidth,
                                height: DownloadIslandCapability.compactHitExtension
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { expand() }
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, DownloadIslandCapability.islandTopInset)
            }
            .frame(maxWidth: .infinity, maxHeight: mode == .expanded ? .infinity : nil, alignment: .top)
            .onPreferenceChange(DownloadIslandBlobFrameKey.self) { blobGlobalFrame = $0 }
            .opacity(isInteractive || isDismissing || dismissProgress > 0 ? 1 : 0)
            .allowsHitTesting(isInteractive)
        }
    }

    @ViewBuilder
    private func chromeView(_ chrome: DownloadIslandChrome) -> some View {
        let width = DownloadIslandCapability.compactDisplayWidth(dismissProgress: dismissProgress)
        let height = DownloadIslandCapability.compactDisplayHeight(dismissProgress: dismissProgress)
        DownloadIslandMorphChrome(
            chrome: chrome,
            isExpanded: mode == .expanded,
            onExpand: expand,
            onResume: { resumeDownload(chrome) },
            onToggle: { toggleDownload(chrome) },
            onCollapse: collapseToCompact
        )
        .scaleEffect(
            x: mode == .expanded ? 1 : width / DownloadIslandCapability.compactWidth,
            y: mode == .expanded ? 1 : height / DownloadIslandCapability.compactHeight,
            anchor: .top
        )
        .opacity(1 - Double(min(max(dismissProgress, 0), 1)))
    }

    private var shouldShow: Bool {
        DownloadIslandCapability.hasDynamicIsland
            && chrome != nil
            && !hero.isFlying
            && (mode == .compact || mode == .expanded || mode == .flying)
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

    private func handleScenePhase(_ phase: ScenePhase, from previous: ScenePhase) {
        if phase == .inactive, previous == .active {
            hideForSystemHandoff()
            return
        }
        if phase == .background {
            hideForSystemHandoff()
            return
        }
        if phase == .active {
            restoreFromSystemHandoff()
        }
    }

    /// Hide the fake island and request ActivityKit before the home snapshot.
    /// An animated dismiss here leaves Compact on the card and blocks absorb.
    private func hideForSystemHandoff() {
        guard DownloadIslandCapability.hasDynamicIsland else {
            DownloadLiveActivityBridge.shared.sync(tasks: downloadManager.tasks)
            return
        }
        if DownloadIslandHandoff.shared.isParked {
            DownloadLiveActivityBridge.shared.sync(tasks: downloadManager.tasks)
            return
        }
        DownloadIslandHandoff.shared.resignToSystemIsland()
        appearGeneration += 1
        pulseTask?.cancel()
        pulseTask = nil
        isShowingCompletion = false
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDismissing = false
            dismissProgress = 0
            chrome = nil
            mode = .hidden
        }
        DownloadLiveActivityBridge.shared.sync(tasks: downloadManager.tasks)
#if DEBUG
        print("[Debug][Downloads] island handoff hide")
#endif
    }

    /// Restore Compact with `playAppear`. Background hide stays instant so the home snapshot has no leftover fake island.
    private func restoreFromSystemHandoff() {
        guard DownloadIslandHandoff.shared.isParked else { return }
        isDismissing = false
        pulseTask?.cancel()
        DownloadIslandHandoff.shared.becomeActive()
        DownloadLiveActivityBridge.shared.sync(tasks: downloadManager.tasks)
        apply(selectedPresentation, preferAppear: true)
#if DEBUG
        print("[Debug][Downloads] island handoff restore")
#endif
    }

    private func apply(
        _ selected: DownloadActivityPresentation,
        preferAppear: Bool = false,
        landHandOff: Bool = false
    ) {
        if isDismissing {
            return
        }
        if DownloadIslandHandoff.shared.isParked {
            if let task = selected.task {
                displayedActivityID = task.id
                if chrome != nil {
                    chrome = DownloadIslandChrome.make(from: selected, task: task)
                }
            }
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
        if mode == .compact || mode == .expanded {
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
            adoptCompactWithoutAppear()
#if DEBUG
            print("[Debug][Downloads] island land compact")
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
        adoptCompactWithoutAppear()
    }

    private func adoptCompactWithoutAppear() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mode = .compact
            dismissProgress = 0
        }
    }

    private func playAppear() {
        guard mode == .hidden else { return }
        appearGeneration += 1
        let generation = appearGeneration
        mode = .compact
        if reduceMotion {
            dismissProgress = 0
            return
        }
        dismissProgress = 1
        DispatchQueue.main.async {
            guard generation == appearGeneration, mode == .compact, !DownloadIslandHandoff.shared.isParked, !isDismissing else { return }
            withAnimation(DownloadIslandMotion.appear) {
                dismissProgress = 0
            }
        }
    }

    private func expand() {
        guard mode == .compact, !isDismissing, !DownloadIslandHandoff.shared.isParked else { return }
#if DEBUG
        print("[Debug][Downloads] island expand")
#endif
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mode = .expanded
            }
            return
        }
        withAnimation(DownloadIslandMotion.morph) {
            mode = .expanded
        }
    }

    private func collapseToCompact() {
        guard mode == .expanded else { return }
#if DEBUG
        print("[Debug][Downloads] island collapse")
#endif
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mode = .compact
            }
            return
        }
        withAnimation(DownloadIslandMotion.collapse) {
            mode = .compact
        }
    }

    private func resumeDownload(_ chrome: DownloadIslandChrome) {
        guard let id = chrome.taskID, chrome.isPaused, !chrome.isCompleted else { return }
#if DEBUG
        print("[Debug][Downloads] island compact resume task=\(id.uuidString)")
#endif
        Task { await DownloadManager.shared.resume(id) }
    }

    private func toggleDownload(_ chrome: DownloadIslandChrome) {
        guard let id = chrome.taskID, !chrome.isCompleted else { return }
#if DEBUG
        print("[Debug][Downloads] island expanded toggle paused=\(chrome.isPaused) task=\(id.uuidString)")
#endif
        Task {
            if chrome.isPaused {
                await DownloadManager.shared.resume(id)
            } else {
                await DownloadManager.shared.pause(id)
            }
        }
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
            mode = .compact
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
                mode = .compact
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
            if mode == .expanded {
                mode = .compact
            }
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

#if DEBUG
    private func installDebugWalkObservers() {
        IslandDebugDarwin.shared.handler = { name in
            switch name {
            case IslandDebugDarwin.expand:
                expand()
            case IslandDebugDarwin.collapse:
                collapseToCompact()
            case IslandDebugDarwin.toggle:
                if let chrome {
                    toggleDownload(chrome)
                }
            case IslandDebugDarwin.resume:
                if let chrome {
                    resumeDownload(chrome)
                }
            case IslandDebugDarwin.pauseAll:
                Task { await DownloadManager.shared.pauseAll() }
            case IslandDebugDarwin.deleteAll:
                Task {
                    await DownloadManager.shared.delete(Set(downloadManager.tasks.map(\.id)))
                }
            case IslandDebugDarwin.openDownloads:
                IslandDebugDarwin.shared.openDownloadsHandler?()
            default:
                break
            }
        }
    }
#endif
}

struct DownloadFallbackBarHost: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var hero: DownloadHeroController
    @ObservedObject private var liveActivity = DownloadLiveActivityBridge.shared
    @State private var displayedActivityID: UUID?
    @State private var visiblePresentation: DownloadActivityPresentation?
    @State private var barOpacity: Double = 1
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if liveActivity.shouldShowFallbackBar, let presentation = visiblePresentation {
                DownloadFallbackProgressBar(
                    title: presentation.title,
                    progress: presentation.progress,
                    posterURL: presentation.posterURL,
                    scale: hero.destinationScale
                ) {
                    appState.openDownloads()
                }
                .padding(.top, 6)
                .padding(.horizontal, 16)
                .opacity((hero.showsDestinationChrome ? 1 : 0) * barOpacity)
                .animation(.easeOut(duration: 0.22), value: hero.showsDestinationChrome)
                .animation(.easeOut(duration: 0.28), value: barOpacity)
                .allowsHitTesting(hero.showsDestinationChrome && barOpacity > 0.5)
            }
        }
        .onAppear {
            applyFallback(fallbackPresentation)
        }
        .onChange(of: downloadManager.tasks) { _, _ in
            applyFallback(fallbackPresentation)
        }
        .onDisappear {
            hideTask?.cancel()
        }
    }

    private var fallbackPresentation: DownloadActivityPresentation? {
        let presentation = DownloadActivityPresentation.select(
            from: downloadManager.tasks,
            previouslyDisplayedID: displayedActivityID
        )
        return presentation.task == nil ? nil : presentation
    }

    private func applyFallback(_ presentation: DownloadActivityPresentation?) {
        if let presentation {
            hideTask?.cancel()
            hideTask = nil
            displayedActivityID = presentation.task?.id
            visiblePresentation = presentation
            barOpacity = 1
            return
        }
        guard visiblePresentation != nil else { return }
        if reduceMotion {
            visiblePresentation = nil
            barOpacity = 1
            displayedActivityID = nil
            return
        }
        hideTask?.cancel()
        barOpacity = 0
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            visiblePresentation = nil
            barOpacity = 1
            displayedActivityID = nil
        }
    }
}

struct DownloadHeroFlightCapsule: View {
    let title: String
    let posterURL: URL?
    let progress: Double
    let isCompleted: Bool
    let isPaused: Bool
    let morphProgress: CGFloat
    let size: CGSize

    var body: some View {
        ZStack {
            materialContent
                .opacity(1 - morphProgress)
            DownloadIslandCompactView(
                chrome: DownloadIslandChrome(
                    taskID: nil,
                    title: title,
                    statusText: isCompleted ? L10n.tr("已完成") : (isPaused ? L10n.tr("已暂停") : L10n.tr("下载中")),
                    progress: progress,
                    isPaused: isPaused,
                    isCompleted: isCompleted,
                    receivedBytes: 0,
                    totalBytes: 0,
                    posterURL: posterURL
                )
            )
            .scaleEffect(
                x: size.width / DownloadIslandCapability.compactWidth,
                y: size.height / DownloadIslandCapability.compactHeight
            )
            .opacity(morphProgress)
        }
        .frame(width: size.width, height: size.height)
        .background {
            ZStack {
                Capsule().fill(.ultraThinMaterial).opacity(1 - morphProgress)
                Capsule().fill(Color.black).opacity(morphProgress)
            }
        }
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08 * (1 - morphProgress)), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16 * Double(1 - morphProgress)), radius: 10, y: 4)
        .clipShape(Capsule())
    }

    private var materialContent: some View {
        HStack(spacing: 8) {
            Group {
                if let posterURL {
                    KFImage(posterURL)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .clipShape(Circle())
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
    }
}

struct DownloadHeroCapsule: View {
    let title: String
    let posterURL: URL?

    var body: some View {
        HStack(spacing: 8) {
            poster
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .frame(maxWidth: 220)
    }

    private var poster: some View {
        Group {
            if let posterURL {
                KFImage(posterURL)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }
}

struct DownloadFallbackProgressBar: View {
    let title: String
    let progress: Double
    let posterURL: URL?
    let scale: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Group {
                    if let posterURL {
                        KFImage(posterURL)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(Color.vanmoAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .downloadChromeCapsuleBackground()
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .accessibilityLabel(L10n.tr("下载进度"))
        .accessibilityValue("\(Int(min(max(progress, 0), 1) * 100))%")
        .accessibilityIdentifier("download.fallback.bar")
    }
}

private struct DownloadIslandBlobFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct IslandOutsidePressCatcher: UIViewRepresentable {
    var onPress: () -> Void
    var passthroughGlobalFrame: CGRect

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isMultipleTouchEnabled = false
        view.onPress = onPress
        view.passthroughGlobalFrame = passthroughGlobalFrame
        return view
    }

    func updateUIView(_ uiView: CatcherView, context: Context) {
        uiView.onPress = onPress
        uiView.passthroughGlobalFrame = passthroughGlobalFrame
    }

    final class CatcherView: UIView {
        var onPress: (() -> Void)?
        var passthroughGlobalFrame: CGRect = .zero
        private var didFire = false

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard bounds.contains(point) else { return false }
            guard !passthroughGlobalFrame.isEmpty else { return true }
            let hole = convert(passthroughGlobalFrame, from: nil)
            return !hole.contains(point)
        }

        override func hitTest(_ hitPoint: CGPoint, with event: UIEvent?) -> UIView? {
            guard point(inside: hitPoint, with: event) else { return nil }
            return self
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard !didFire else { return }
            didFire = true
            onPress?()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            didFire = false
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            didFire = false
        }
    }
}

struct DownloadHeroRequest {
    let title: String
    let posterURL: URL?
}

extension Notification.Name {
    static let downloadHeroRequested = Notification.Name("vanmo.downloadHeroRequested")
}

#if DEBUG
final class IslandDebugDarwin {
    static let shared = IslandDebugDarwin()
    static let expand = "com.vanmo.debug.island.expand"
    static let collapse = "com.vanmo.debug.island.collapse"
    static let toggle = "com.vanmo.debug.island.toggle"
    static let resume = "com.vanmo.debug.island.resume"
    static let pauseAll = "com.vanmo.debug.downloads.pauseAll"
    static let deleteAll = "com.vanmo.debug.downloads.deleteAll"
    static let openDownloads = "com.vanmo.debug.downloads.open"

    var handler: ((String) -> Void)?
    var openDownloadsHandler: (() -> Void)?

    private init() {
        for name in [Self.expand, Self.collapse, Self.toggle, Self.resume, Self.pauseAll, Self.deleteAll, Self.openDownloads] {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let hook = Unmanaged<IslandDebugDarwin>.fromOpaque(observer).takeUnretainedValue()
                    let raw = name.rawValue as String
                    DispatchQueue.main.async {
                        print("[Debug][Downloads] island walk action=\(raw)")
                        hook.handler?(raw)
                    }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
    }
}
#endif

extension View {
    func downloadChromeCapsuleBackground() -> some View {
        modifier(DownloadChromeCapsuleBackground())
    }
}

private struct DownloadChromeCapsuleBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

extension DownloadHeroController {
    static func request(title: String, posterURL: URL?) {
        NotificationCenter.default.post(
            name: .downloadHeroRequested,
            object: DownloadHeroRequest(title: title, posterURL: posterURL)
        )
    }
}

#Preview("capsule") {
    DownloadHeroCapsule(title: "download.png", posterURL: nil)
}

#Preview("island compact") {
    DownloadIslandCompactView(
        chrome: DownloadIslandChrome(
            taskID: nil,
            title: "Dune: Part Two",
            statusText: L10n.tr("下载中"),
            progress: 0.45,
            isPaused: false,
            isCompleted: false,
            receivedBytes: 1_800_000_000,
            totalBytes: 4_000_000_000,
            posterURL: nil
        )
    )
}
