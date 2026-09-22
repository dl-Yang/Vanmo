import SwiftData
import SwiftUI
import UIKit
import VanmoCore

struct LandscapePlayerPresenter: UIViewControllerRepresentable {
    let item: MediaItem?
    let isPresented: Bool
    let modelContext: ModelContext
    let onDismiss: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = PlayerPresentationAnchorViewController()
        viewController.view.backgroundColor = .clear
        viewController.onDidAppear = { [weak coordinator = context.coordinator] in
            coordinator?.attemptUpdate()
        }
        return viewController
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        context.coordinator.onDismiss = onDismiss
        context.coordinator.update(
            item: item,
            isPresented: isPresented,
            modelContext: modelContext,
            from: viewController
        )
    }

    static func dismantleUIViewController(
        _ viewController: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var onDismiss: @MainActor () -> Void

        private weak var presentingViewController: UIViewController?
        private weak var anchorViewController: UIViewController?
        private var playerViewController: LandscapePlayerHostingController?
        private var presentedItemID: UUID?
        private var isDismissing = false
        private var transitionCover: UIView?
        private var pendingItem: MediaItem?
        private var pendingIsPresented = false
        private var pendingModelContext: ModelContext?
        private var previousAnimationsEnabled: Bool?
        private var orientationRequestGeneration = 0
        private var orientationWaitTask: Task<Void, Never>?

        init(onDismiss: @escaping @MainActor () -> Void) {
            self.onDismiss = onDismiss
        }

        func update(
            item: MediaItem?,
            isPresented: Bool,
            modelContext: ModelContext,
            from presentingViewController: UIViewController
        ) {
            anchorViewController = presentingViewController
            pendingItem = item
            pendingIsPresented = isPresented
            pendingModelContext = modelContext
            attemptUpdate()
        }

        func attemptUpdate() {
            if let playerViewController {
                if pendingIsPresented,
                   let item = pendingItem,
                   let modelContext = pendingModelContext {
                    guard presentedItemID != item.id, !isDismissing else { return }
                    playerViewController.rootView = makePlayerView(
                        item: item,
                        modelContext: modelContext
                    )
                    presentedItemID = item.id
                } else if !pendingIsPresented, !isDismissing {
                    dismissPlayer()
                }
                return
            }

            guard let anchorViewController,
                  anchorViewController.viewIfLoaded?.window != nil else {
                return
            }

            let presentingViewController = topViewController(
                from: anchorViewController.view.window?.rootViewController
            ) ?? anchorViewController
            self.presentingViewController = presentingViewController

            if pendingIsPresented,
               let item = pendingItem,
               let modelContext = pendingModelContext {
                guard !isDismissing else { return }
                present(item: item, modelContext: modelContext, from: presentingViewController)
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finishDismissal()
        }

        func tearDown() {
            VanmoAppDelegate.orientationLock = .portrait
            orientationRequestGeneration += 1
            orientationWaitTask?.cancel()
            orientationWaitTask = nil
            restoreAnimationsAfterOrientationChange()
            transitionCover?.removeFromSuperview()
            transitionCover = nil
            playerViewController?.dismiss(animated: false)
            playerViewController = nil
            presentedItemID = nil
            isDismissing = false
        }

        private func topViewController(from rootViewController: UIViewController?) -> UIViewController? {
            if let presented = rootViewController?.presentedViewController {
                return topViewController(from: presented)
            }
            if let navigationController = rootViewController as? UINavigationController {
                return topViewController(from: navigationController.visibleViewController)
            }
            if let tabBarController = rootViewController as? UITabBarController {
                return topViewController(from: tabBarController.selectedViewController)
            }
            return rootViewController
        }

        private func present(
            item: MediaItem,
            modelContext: ModelContext,
            from presentingViewController: UIViewController
        ) {
            if UIDevice.current.userInterfaceIdiom == .phone {
                VanmoAppDelegate.orientationLock = .landscape
            }

            let rootView = makePlayerView(item: item, modelContext: modelContext)
            let preferredOrientation = presentingViewController.view.window?
                .windowScene?
                .interfaceOrientation ?? .portrait
            let playerViewController = LandscapePlayerHostingController(
                rootView: rootView,
                preferredOrientation: preferredOrientation
            )
            playerViewController.modalPresentationStyle = .fullScreen
            playerViewController.presentationController?.delegate = self
            playerViewController.onDidAppear = { [weak self, weak playerViewController] in
                guard let self, let playerViewController else { return }
                self.requestLandscape(for: playerViewController)
            }

            self.playerViewController = playerViewController
            presentedItemID = item.id
            presentingViewController.present(playerViewController, animated: false)
        }

        private func makePlayerView(
            item: MediaItem,
            modelContext: ModelContext
        ) -> AnyView {
            AnyView(
                PlayerView(item: item) { [weak self] in
                    self?.dismissPlayer()
                }
                .id(item.id)
                .environment(\.modelContext, modelContext)
            )
        }

        private func requestLandscape(for playerViewController: UIViewController) {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return }
            guard let windowScene = playerViewController.view.window?.windowScene else { return }

            let generation = beginOrientationChange()
            UIView.performWithoutAnimation {
                playerViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                windowScene.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .landscape)
                ) { [weak self] error in
#if DEBUG
                    print("[Debug][Player] landscape request failed: \(error.localizedDescription)")
#endif
                    Task { @MainActor in
                        self?.finishOrientationChange(generation: generation)
                    }
                }
            }

            orientationWaitTask = Task { @MainActor [weak self, weak windowScene] in
                guard let self else { return }
                if let windowScene {
                    for _ in 0..<60 where !windowScene.interfaceOrientation.isLandscape {
                        try? await Task.sleep(nanoseconds: 16_000_000)
                    }
                }
                guard !Task.isCancelled else { return }
                self.finishOrientationChange(generation: generation)
            }
        }

        private func dismissPlayer() {
            guard let playerViewController, !isDismissing else { return }
            isDismissing = true

            let window = playerViewController.view.window
            let transitionCover = window.flatMap { makeTransitionCover(in: $0) }
            self.transitionCover = transitionCover

            if UIDevice.current.userInterfaceIdiom == .pad {
                completeDismissal(transitionCover: transitionCover)
                return
            }

            VanmoAppDelegate.orientationLock = .portrait
            guard let windowScene = window?.windowScene else {
                completeDismissal(transitionCover: transitionCover)
                return
            }

            let generation = beginOrientationChange()
            UIView.performWithoutAnimation {
                playerViewController.prepareForPortraitDismissal()
                presentingViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                windowScene.requestGeometryUpdate(
                    .iOS(interfaceOrientations: .portrait)
                ) { [weak self] error in
#if DEBUG
                    print("[Debug][Player] portrait request failed: \(error.localizedDescription)")
#endif
                    Task { @MainActor in
                        self?.finishOrientationChange(generation: generation)
                    }
                }
            }

            orientationWaitTask = Task { @MainActor [weak self, weak windowScene] in
                guard let self else { return }
                if let windowScene {
                    for _ in 0..<60 where !windowScene.interfaceOrientation.isPortrait {
                        try? await Task.sleep(nanoseconds: 16_000_000)
                    }
                }
                guard !Task.isCancelled,
                      generation == self.orientationRequestGeneration else {
                    return
                }
                self.finishOrientationChange(generation: generation)
                self.completeDismissal(transitionCover: transitionCover)
            }
        }

        private func beginOrientationChange() -> Int {
            orientationRequestGeneration += 1
            orientationWaitTask?.cancel()
            orientationWaitTask = nil
            disableAnimationsForOrientationChange()
            return orientationRequestGeneration
        }

        private func finishOrientationChange(generation: Int) {
            guard generation == orientationRequestGeneration else { return }
            orientationWaitTask = nil
            restoreAnimationsAfterOrientationChange()
        }

        private func disableAnimationsForOrientationChange() {
            guard previousAnimationsEnabled == nil else { return }
            previousAnimationsEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
        }

        private func restoreAnimationsAfterOrientationChange() {
            guard let previousAnimationsEnabled else { return }
            UIView.setAnimationsEnabled(previousAnimationsEnabled)
            self.previousAnimationsEnabled = nil
        }

        private func makeTransitionCover(in window: UIWindow) -> UIView? {
            guard let snapshot = window.snapshotView(afterScreenUpdates: false) else {
                return nil
            }

            let cover = UIView(frame: window.bounds)
            cover.backgroundColor = .black
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cover.clipsToBounds = true

            snapshot.translatesAutoresizingMaskIntoConstraints = false
            cover.addSubview(snapshot)
            NSLayoutConstraint.activate([
                snapshot.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
                snapshot.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
                snapshot.widthAnchor.constraint(equalToConstant: window.bounds.width),
                snapshot.heightAnchor.constraint(equalToConstant: window.bounds.height)
            ])

            window.addSubview(cover)
            return cover
        }

        private func completeDismissal(transitionCover: UIView?) {
            guard let playerViewController else {
                transitionCover?.removeFromSuperview()
                self.transitionCover = nil
                finishDismissal()
                return
            }

            playerViewController.dismiss(animated: false) { [weak self, weak transitionCover] in
                self?.finishDismissal()
                guard let transitionCover else { return }
                UIView.animate(
                    withDuration: 0.18,
                    delay: 0,
                    options: [.curveEaseOut, .beginFromCurrentState]
                ) {
                    transitionCover.alpha = 0
                    transitionCover.transform = CGAffineTransform(
                        translationX: transitionCover.bounds.width * 0.08,
                        y: 0
                    )
                } completion: { _ in
                    transitionCover.removeFromSuperview()
                    self?.transitionCover = nil
                }
            }
        }

        private func finishDismissal() {
            guard playerViewController != nil || isDismissing else { return }
            playerViewController = nil
            presentedItemID = nil
            isDismissing = false
            VanmoAppDelegate.orientationLock = .portrait
            onDismiss()
        }
    }
}

private final class LandscapePlayerHostingController: UIHostingController<AnyView> {
    var onDidAppear: (() -> Void)?
    private var isPreparingForPortraitDismissal = false
    private let initialPreferredOrientation: UIInterfaceOrientation

    init(rootView: AnyView, preferredOrientation: UIInterfaceOrientation) {
        initialPreferredOrientation = preferredOrientation
        super.init(rootView: rootView)
    }

    @MainActor
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .all
        }
        return isPreparingForPortraitDismissal ? .portrait : .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return initialPreferredOrientation
        }
        return isPreparingForPortraitDismissal ? .portrait : .landscapeRight
    }

    override var shouldAutorotate: Bool {
        true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }

    func prepareForPortraitDismissal() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        isPreparingForPortraitDismissal = true
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

private final class PlayerPresentationAnchorViewController: UIViewController {
    var onDidAppear: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }
}
