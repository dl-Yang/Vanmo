import SwiftUI
import SwiftData
import VanmoCore

struct MacScanSyncBanner: View {
    @Environment(\.macTheme) private var theme

    @ObservedObject var coordinator: ScanCoordinator
    var onPause: () -> Void
    var onResume: () -> Void
    var onCancel: () -> Void

    var body: some View {
        if coordinator.isActive, let progress = coordinator.progress {
            let processed = progress.insertedCount + progress.updatedCount + progress.unchangedCount
            let total = max(progress.discoveredVideos, processed)
            let fraction = total > 0
                ? min(max(Double(processed) / Double(total), 0.12), 1)
                : 0.35
            let percent = total > 0
                ? Int((Double(processed) / Double(total) * 100).rounded())
                : 0

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(progress.summaryMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if total > 0 && processed > 0 {
                        Text("\(percent)%")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(theme.accentAmber)
                    }

                    Button(coordinator.controlState == .paused ? L10n.tr("继续") : L10n.tr("暂停")) {
                        if coordinator.controlState == .paused {
                            onResume()
                        } else {
                            onPause()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accentAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(theme.amberTintFill, in: Capsule())

                    Button(L10n.tr("取消"), action: onCancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.dangerRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }

                GeometryReader { proxy in
                    let width = max(proxy.size.width, 1)
                    let fillWidth = max(6, width * fraction)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.progressTrack)
                            .frame(height: 3)

                        Capsule()
                            .fill(MacDesignTokens.glowAmber)
                            .frame(width: fillWidth, height: 3)

                        Image("MacWalkingProgressTip")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 18)
                            .offset(x: min(max(fillWidth - 13, 0), max(0, width - 26)), y: -8)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 16)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .macCatGlassCard(theme: theme, cornerRadius: 15)
        }
    }
}

struct MacLowConfidenceItemsSheet: View {
    let connectionId: UUID
    let connectionName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macTheme) private var theme
    @Query private var items: [MediaItem]

    init(connectionId: UUID, connectionName: String) {
        self.connectionId = connectionId
        self.connectionName = connectionName
        let threshold = ScanLibraryQueries.defaultLowConfidenceThreshold
        _items = Query(
            filter: #Predicate<MediaItem> { item in
                item.sourceConnectionId == connectionId
                    && item.identificationConfidence != nil
                    && item.identificationConfidence! < threshold
            },
            sort: [SortDescriptor(\MediaItem.addedAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .foregroundStyle(theme.primaryText)
                    if let confidence = item.identificationConfidence {
                        Text(String(format: L10n.tr("置信度 %.0f%%"), confidence * 100))
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                    if let path = item.serverId {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(theme.surfacePanel)
            .navigationTitle("\(connectionName) · 待确认")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("关闭")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
