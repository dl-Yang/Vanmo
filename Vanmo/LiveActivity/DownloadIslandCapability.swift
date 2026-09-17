import ActivityKit
import UIKit

enum DownloadIslandCapability {
    static var hasDynamicIsland: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        if let cachedHasDynamicIsland {
            return cachedHasDynamicIsland
        }
        let detected = maxKeyWindowSafeAreaInset >= 59
        if detected {
            cachedHasDynamicIsland = true
        }
        return detected
    }

    static var canUseLiveActivity: Bool {
        hasDynamicIsland && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Measured from an iPhone 17 Pro simulator screenshot at 3× (402×874 points).
    static let islandWidth: CGFloat = 125.33
    static let islandHeight: CGFloat = 36.67
    static let islandTopInset: CGFloat = 14
    /// Figma LibraryHome `569:38` Dynamic Island-Compact.
    static let compactWidth: CGFloat = 262.4
    static let compactHeight: CGFloat = 41
    /// Figma LibraryHome `570:259` Dynamic Island-Expended.
    static let expandedWidth: CGFloat = 354.84
    /// Figma body height for `570:259` before hardware-island clearance.
    static let expandedFigmaHeight: CGFloat = 186.2
    /// Figma content top padding inside `570:259`.
    static let expandedFigmaContentTop: CGFloat = 16.74
    /// Gap between the hardware island bottom and Expanded content.
    static let expandedIslandGap: CGFloat = 10
    /// Pushes poster/title below the hardware island; Figma internal gaps stay the same.
    static let expandedContentTopInset: CGFloat = islandHeight + expandedIslandGap
    static let expandedHeight: CGFloat = expandedFigmaHeight + (expandedContentTopInset - expandedFigmaContentTop)
    static let expandedCornerRadius: CGFloat = 30
    /// Extra tap strip below the hardware island, which owns the exclusive hit region.
    static let compactHitExtension: CGFloat = 28

    static func compactDisplayWidth(dismissProgress: CGFloat) -> CGFloat {
        compactWidth + (islandWidth - compactWidth) * min(max(dismissProgress, 0), 1)
    }

    static func compactDisplayHeight(dismissProgress: CGFloat) -> CGFloat {
        compactHeight + (islandHeight - compactHeight) * min(max(dismissProgress, 0), 1)
    }

    static func islandFrame(in screen: CGRect, safeAreaTop _: CGFloat) -> CGRect {
        centeredIslandFrame(width: islandWidth, in: screen)
    }

    static func compactFrame(in screen: CGRect, safeAreaTop _: CGFloat) -> CGRect {
        centeredIslandFrame(width: compactWidth, height: compactHeight, in: screen)
    }

    static func estimatedHeroCapsuleSize(title: String) -> CGSize {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
        let width = min(220, max(96, 6 + 24 + 8 + ceil(titleWidth) + 12))
        return CGSize(width: width, height: 36)
    }

    static func fallbackBarFrame(in screen: CGRect, safeAreaTop: CGFloat) -> CGRect {
        let horizontal: CGFloat = 16
        let topGap: CGFloat = 6
        let height: CGFloat = 44
        return CGRect(
            x: screen.minX + horizontal,
            y: screen.minY + safeAreaTop + topGap,
            width: max(screen.width - horizontal * 2, 1),
            height: height
        )
    }

    static func expandedFrame(in screen: CGRect, safeAreaTop _: CGFloat) -> CGRect {
        centeredIslandFrame(width: expandedWidth, height: expandedHeight, in: screen)
    }

    /// Keeps the blob top flush with the hardware island while height changes.
    static func topAlignedCenter(for size: CGSize, in island: CGRect) -> CGPoint {
        CGPoint(x: island.midX, y: island.minY + size.height / 2)
    }

    private static func centeredIslandFrame(width: CGFloat, in screen: CGRect) -> CGRect {
        centeredIslandFrame(width: width, height: islandHeight, in: screen)
    }

    private static func centeredIslandFrame(width: CGFloat, height: CGFloat, in screen: CGRect) -> CGRect {
        let x = screen.minX + (screen.width - width) / 2
        let y = screen.minY + islandTopInset
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static var cachedHasDynamicIsland: Bool?

    private static var maxKeyWindowSafeAreaInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? scenes.first?.windows.first
        guard let insets = window?.safeAreaInsets else { return 0 }
        return max(insets.top, insets.bottom, insets.left, insets.right)
    }
}
