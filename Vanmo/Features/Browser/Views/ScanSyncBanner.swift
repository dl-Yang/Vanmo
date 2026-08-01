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
                        .font(.caption.weight(.semibold))
                } else {
                    Button("暂停", action: onPause)
                        .font(.caption.weight(.semibold))
                }

                Button("取消", role: .destructive, action: onCancel)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
                    if let confidence = item.identificationConfidence {
                        Text(String(format: "置信度 %.0f%%", confidence * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let path = item.serverId {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
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
    }
}
