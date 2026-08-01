import SwiftUI
import SwiftData
import VanmoCore

struct MacScanSyncBanner: View {
    @ObservedObject var coordinator: ScanCoordinator
    var onPause: () -> Void
    var onResume: () -> Void
    var onCancel: () -> Void

    var body: some View {
        if coordinator.isActive, let progress = coordinator.progress {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text("正在同步媒体库")
                        .font(.subheadline.weight(.semibold))
                    Text(progress.summaryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if coordinator.controlState == .paused {
                    Button("继续", action: onResume)
                } else {
                    Button("暂停", action: onPause)
                }

                Button("取消", role: .destructive, action: onCancel)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}

struct MacLowConfidenceItemsSheet: View {
    let connectionId: UUID
    let connectionName: String
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
                    if let confidence = item.identificationConfidence {
                        Text(String(format: "置信度 %.0f%%", confidence * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let path = item.serverId {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("\(connectionName) · 待确认")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}
