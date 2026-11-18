import SwiftUI
import SwiftData
import VanmoCore

struct ScanSyncBanner: View {
    @ObservedObject var coordinator: ScanCoordinator
    var onPause: () -> Void
    var onResume: () -> Void
    var onCancel: () -> Void

    var body: some View {
        if coordinator.isActive, let progress = coordinator.progress {
            let fraction = estimatedFraction(from: progress)
            let percent = Int((fraction * 100).rounded())

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(progress.summaryMessage)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(CatDesign.textIvory)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text("\(percent)%")
                        .font(.system(size: 11.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(CatDesign.accentAmber)

                    controlButtons
                }

                walkingCatProgressBar(fraction: fraction)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .catGlassCard(cornerRadius: 16, elevated: true, amberStroke: true)
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 6) {
            Button {
                if coordinator.controlState == .paused {
                    onResume()
                } else {
                    onPause()
                }
            } label: {
                Image(systemName: coordinator.controlState == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CatDesign.accentAmber)
                    .frame(width: 22, height: 22)
                    .background(CatDesign.amberTintFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(coordinator.controlState == .paused ? L10n.tr("继续") : L10n.tr("暂停"))

            Button(role: .destructive, action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CatDesign.textMuted)
                    .frame(width: 22, height: 22)
                    .background(CatDesign.surfacePill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("取消"))
        }
    }

    private func walkingCatProgressBar(fraction: Double) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let clamped = min(max(fraction, 0.04), 1)
            let fillWidth = width * clamped
            let catX = min(max(fillWidth - 13, 0), max(width - 26, 0))

            ZStack(alignment: .bottomLeading) {
                Capsule()
                    .fill(CatDesign.progressTrack)
                    .frame(height: 3)

                Capsule()
                    .fill(CatDesign.glowAmber)
                    .frame(width: fillWidth, height: 3)

                Image("CatWalkingProgressTip")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 18)
                    .offset(x: catX, y: -2)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }

    private func estimatedFraction(from progress: ScanProgress) -> Double {
        let processed = progress.insertedCount + progress.updatedCount + progress.unchangedCount
        if progress.discoveredVideos > 0 {
            return min(max(Double(processed) / Double(progress.discoveredVideos), 0.12), 1)
        }
        return progress.scannedDirectories > 0 ? 0.35 : 0.15
    }
}

struct LowConfidenceItemsSheet: View {
    let connectionId: UUID
    let connectionName: String
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
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
                        .font(.headline)
                        .foregroundStyle(CatDesign.textIvory)
                    if let confidence = item.identificationConfidence {
                        Text(String(format: L10n.tr("置信度 %.0f%%"), confidence * 100))
                            .font(.caption)
                            .foregroundStyle(CatDesign.textMuted)
                    }
                    if let path = item.serverId {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(CatDesign.textDim)
                            .lineLimit(1)
                    }
                }
                .listRowBackground(CatDesign.surfaceGlass)
            }
            .scrollContentBackground(.hidden)
            .background(CatDesign.bgObsidian)
            .navigationTitle("\(connectionName) · 待确认")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("关闭")) { dismiss() }
                        .foregroundStyle(CatDesign.accentAmber)
                }
            }
        }
    }
}
