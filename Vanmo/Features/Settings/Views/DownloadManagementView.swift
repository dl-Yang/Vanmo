import SwiftData
import SwiftUI
import Kingfisher
import VanmoCore

/// iOS 下载管理页。对齐 Figma `11 · Downloads Management` (`693:1041`)。
struct DownloadManagementView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var deleteTargetTask: DownloadTaskSnapshot?
    @State private var presentedSurface: PresentedDownloadSurface?
    @State private var lastLoggedTaskSignatures: [UUID: String] = [:]
    @State private var currentSpeedBytesPerSecond: Double = 0
    @State private var lastSampleBytes: Int64 = 0
    @State private var lastSampleDate: Date?
    @State private var storageStats = DeviceStorageStats.current()

    private var activeTasks: [DownloadTaskSnapshot] {
        downloadManager.tasks.filter { $0.status != .completed }
    }

    private var completedTasks: [DownloadTaskSnapshot] {
        downloadManager.tasks.filter { $0.status == .completed }
    }

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            HStack {
                CatAmberHalo(width: 180, height: 110, opacity: 0.20)
                    .padding(.top, 90)
                    .padding(.leading, 20)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                navHeader

                if downloadManager.tasks.isEmpty {
                    emptyState
                } else {
                    downloadsScrollContent
                }
            }
        }
        .accessibilityIdentifier("screen.downloads")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .catTabBarHidden(true)
        .confirmationDialog(
            L10n.tr("删除下载？"),
            isPresented: Binding(
                get: { deleteTargetTask != nil },
                set: { if !$0 { deleteTargetTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let task = deleteTargetTask {
                Button(L10n.tr("删除文件和记录"), role: .destructive) {
                    Task {
                        await downloadManager.delete([task.id])
                        storageStats = DeviceStorageStats.current()
                    }
                    deleteTargetTask = nil
                }
            }
            Button(L10n.tr("取消"), role: .cancel) {
                deleteTargetTask = nil
            }
        }
        .onAppear {
            storageStats = DeviceStorageStats.current()
            logTaskSnapshots(reason: "appear")
        }
        .onChange(of: downloadManager.tasks) { _, _ in
            updateSpeedSample()
            logTaskSnapshots(reason: "update")
        }
        .onChange(of: appState.pendingDownloadDetailRequest, initial: true) { _, request in
            guard let request else { return }
            presentDetail(for: request)
            appState.consumeDownloadDetailRequest()
        }
        .fullScreenCover(item: $presentedSurface) { surface in
            NavigationStack {
                MediaDetailView(item: surface.item)
            }
        }
    }

    // MARK: - Nav Header

    private var navHeader: some View {
        HStack(spacing: 12) {
            CatBackButton(size: 36) { dismiss() }

            Text(L10n.tr("下载"))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Spacer(minLength: 8)

            if downloadManager.hasPausableTasks {
                Button {
                    Task { await downloadManager.pauseAll() }
                } label: {
                    Text(L10n.tr("全部暂停"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CatDesign.textMuted)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .catGlassCard(cornerRadius: CatDesign.radiusPill)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("downloads.pauseAll")
            } else if downloadManager.hasResumableTasks {
                Button {
                    Task { await downloadManager.resumeAll() }
                } label: {
                    Text(L10n.tr("全部继续"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .catGlassCard(cornerRadius: CatDesign.radiusPill, amberStroke: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("downloads.resumeAll")
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Scroll Content

    private var downloadsScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                storageSummaryCard
                    .padding(.top, 10)

                if !activeTasks.isEmpty {
                    activeSection
                }

                if !completedTasks.isEmpty {
                    completedSection
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.bottom, 34)
        }
    }

    private var storageSummaryCard: some View {
        HStack(spacing: 12) {
            CatStorageRingGauge(usedFraction: storageStats.usedFraction)

            VStack(alignment: .leading, spacing: 2) {
                Text(storageStats.headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(summarySubline)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            speedPill
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .catGlassCard(cornerRadius: 20, elevated: true)
    }

    private var summarySubline: String {
        L10n.tr("%d 进行中 · %d 已完成 · %@ 可用", activeTasks.count, completedTasks.count, storageStats.freeText)
    }

    private var speedPill: some View {
        let isDownloading = downloadManager.tasks.contains { $0.status == .downloading }
        let speedText: String = {
            guard isDownloading else { return L10n.tr("空闲") }
            if currentSpeedBytesPerSecond > 1024 {
                return "\(ByteCountFormatter.string(fromByteCount: Int64(currentSpeedBytesPerSecond), countStyle: .file))/s"
            }
            return L10n.tr("下载中")
        }()

        return HStack(spacing: 5) {
            Circle()
                .fill(isDownloading ? CatDesign.glowAmber : CatDesign.textDim)
                .frame(width: 5, height: 5)

            Text(speedText)
                .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                .foregroundStyle(isDownloading ? CatDesign.accentAmber : CatDesign.textMuted)
                .lineLimit(1)
        }
        .padding(.leading, 9)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(isDownloading ? CatDesign.amberTintFill : CatDesign.surfacePill, in: Capsule())
        .overlay(Capsule().strokeBorder(isDownloading ? CatDesign.strokeAmber : CatDesign.strokeGlass, lineWidth: 0.85))
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("正在下载 · %d", activeTasks.count))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)
                Spacer()
                CatStretchingDivider()
            }

            ForEach(activeTasks) { task in
                CatActiveDownloadCard(
                    task: task,
                    onPause: { Task { await downloadManager.pause(task.id) } },
                    onResume: { Task { await downloadManager.resume(task.id) } },
                    onRetry: { Task { await downloadManager.retry(task.id) } },
                    onDelete: { deleteTargetTask = task },
                    onOpenDetail: { appState.requestDownloadDetail(for: task.request) }
                )
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("已完成 · 离线媒体库"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(CatDesign.textMuted)
                .padding(.top, 4)

            ForEach(completedTasks) { task in
                CatCompletedDownloadCard(
                    task: task,
                    onPlay: { play(task) },
                    onDelete: { deleteTargetTask = task },
                    onOpenDetail: { appState.requestDownloadDetail(for: task.request) }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image("CatSittingInFolderBox")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 86)

            Text(L10n.tr("暂无下载"))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Text(L10n.tr("从媒体详情或文件浏览器发起下载后，任务会显示在这里。"))
                .font(.system(size: 13))
                .foregroundStyle(CatDesign.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Speed & Playback Helpers

    private func updateSpeedSample() {
        let totalReceived = downloadManager.tasks
            .filter { $0.status == .downloading }
            .reduce(Int64(0)) { $0 + $1.receivedBytes }
        let now = Date()
        if let lastDate = lastSampleDate {
            let dt = now.timeIntervalSince(lastDate)
            if dt >= 0.4 {
                let delta = max(0, totalReceived - lastSampleBytes)
                currentSpeedBytesPerSecond = Double(delta) / dt
                lastSampleBytes = totalReceived
                lastSampleDate = now
            }
        } else {
            lastSampleBytes = totalReceived
            lastSampleDate = now
        }
    }

    private func play(_ task: DownloadTaskSnapshot) {
        guard task.status == .completed else { return }
        let resolvedURL: URL
        do {
            resolvedURL = try downloadManager.completedFileURL(for: task.id)
        } catch {
            return
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else { return }
        let fileURL = URL(fileURLWithPath: resolvedURL.path, isDirectory: false)
        let item = MediaItem(
            title: task.request.displayTitle,
            fileURL: fileURL,
            mediaType: task.request.mediaType,
            fileSize: task.totalBytes
        )
        item.showTitle = task.request.showTitle
        item.seasonNumber = task.request.seasonNumber
        item.episodeNumber = task.request.episodeNumber
        item.episodeTitle = task.request.episodeTitle
        item.posterURL = task.request.postUrl
        item.container = fileURL.pathExtension.lowercased()
        item.originalFileName = task.request.fileName
        appState.play(item)
    }

    private func presentDetail(for request: DownloadRequest) {
        let stored = storedMediaItem(for: request)
        let item = stored ?? makeDownloadDetailFallback(for: request)
        presentedSurface = .detail(item)
    }

    private func logTaskSnapshots(reason: String) {
#if DEBUG
        let tasks = downloadManager.tasks
        VanmoLogger.storage.info("[Debug][Downloads] \(reason, privacy: .public) count=\(tasks.count, privacy: .public)")
        for task in tasks {
            let percent = task.totalBytes > 0 ? Int(task.progress * 100) : -1
            let bucket = percent < 0 ? -1 : (percent / 10) * 10
            let signature = "\(task.status.rawValue)|\(bucket)"
            guard lastLoggedTaskSignatures[task.id] != signature else { continue }
            lastLoggedTaskSignatures[task.id] = signature
            VanmoLogger.storage.info("[Debug][Downloads] task=\(task.id.uuidString, privacy: .public) status=\(task.status.rawValue, privacy: .public) progress=\(percent, privacy: .public) received=\(task.receivedBytes, privacy: .public) total=\(task.totalBytes, privacy: .public)")
        }
#endif
    }

    private func storedMediaItem(for request: DownloadRequest) -> MediaItem? {
        if request.mediaType == .tvEpisode,
           let seriesID = request.seriesServerID,
           let connectionID = request.sourceConnectionId {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate {
                    $0.serverId == seriesID && $0.sourceConnectionId == connectionID
                }
            )
            if let series = try? modelContext.fetch(descriptor).first {
                return series
            }
        }

        if let mediaID = request.sourceMediaItemID {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate { $0.id == mediaID }
            )
            if let item = try? modelContext.fetch(descriptor).first {
                if request.mediaType != .tvEpisode || item.mediaType == .tvShow {
                    return item
                }
            }
        }

        guard request.mediaType != .tvEpisode else { return nil }
        let serverID = request.sourceServerID
        guard let serverID, let connectionID = request.sourceConnectionId else {
            return nil
        }
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate {
                $0.serverId == serverID && $0.sourceConnectionId == connectionID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func makeDownloadDetailFallback(for request: DownloadRequest) -> MediaItem {
        let opensSeries = request.mediaType == .tvEpisode
        let item = MediaItem(
            title: opensSeries ? (request.showTitle ?? request.displayTitle) : request.displayTitle,
            fileURL: request.sourceFileURL ?? URL(fileURLWithPath: request.remotePath),
            mediaType: opensSeries ? .tvShow : request.mediaType,
            fileSize: request.totalBytes
        )
        item.posterURL = opensSeries ? request.seriesPosterURL : request.postUrl
        item.backdropURL = request.postUrl
        item.sourceConnectionId = request.sourceConnectionId
        item.serverId = opensSeries ? request.seriesServerID : request.sourceServerID
        item.seriesId = request.seriesServerID
        item.showTitle = request.showTitle
        return item
    }
}

// MARK: - Subviews

private struct CatStorageRingGauge: View {
    let usedFraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(CatDesign.progressTrack, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(max(usedFraction, 0.04), 1))
                .stroke(CatDesign.glowAmber, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image("CatStorageRing")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
        }
        .frame(width: 40, height: 40)
    }
}

private struct CatActiveDownloadCard: View {
    let task: DownloadTaskSnapshot
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void
    let onOpenDetail: () -> Void

    private var isDownloading: Bool {
        task.status == .downloading || task.status == .queued
    }

    private var isPaused: Bool {
        task.status == .paused
    }

    private var statsText: String {
        let received = ByteCountFormatter.string(fromByteCount: task.receivedBytes, countStyle: .file)
        let total = task.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file) : ""
        let pct = Int((task.progress * 100).rounded())
        switch task.status {
        case .queued:
            return L10n.tr("等待中 · 即将开始")
        case .downloading:
            return total.isEmpty ? L10n.tr("下载中") : "\(received) / \(total) · \(pct)%"
        case .paused:
            return total.isEmpty ? L10n.tr("已暂停") : L10n.tr("已暂停 · %@ / %@ (%d%%)", received, total, pct)
        case .failed:
            return task.errorMessage?.isEmpty == false ? "\(L10n.tr("下载失败")) · \(task.errorMessage!)" : L10n.tr("下载失败")
        case .completed:
            return total
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenDetail) {
                KFImage(task.request.postUrl)
                    .placeholder {
                        ZStack {
                            CatDesign.mediaPlaceholder
                            Image(systemName: "film")
                                .foregroundStyle(CatDesign.textMuted)
                        }
                    }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                Button(action: onOpenDetail) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.request.displayTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.textIvory)
                            .lineLimit(1)

                        Text(statsText)
                            .font(.system(size: 11))
                            .foregroundStyle(
                                task.status == .failed
                                    ? CatDesign.dangerRed
                                    : (isDownloading ? CatDesign.accentAmber : CatDesign.textMuted)
                            )
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                CatPawProgressBar(progress: task.progress, isPaused: isPaused)

                HStack(spacing: 8) {
                    primaryActionPill
                    deleteActionPill
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .catGlassCard(cornerRadius: 20, amberStroke: isDownloading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.request.displayTitle)
    }

    private var primaryActionPill: some View {
        Button {
            switch task.status {
            case .downloading, .queued: onPause()
            case .paused: onResume()
            case .failed: onRetry()
            case .completed: break
            }
        } label: {
            HStack(spacing: 5) {
                if task.status == .downloading || task.status == .queued {
                    Image("CatEarPause")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                    Text(L10n.tr("暂停"))
                } else if task.status == .paused {
                    Image("CatPlaySmall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                    Text(L10n.tr("继续"))
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                    Text(L10n.tr("重试"))
                }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(CatDesign.accentAmber)
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(height: 26)
            .background(CatDesign.surfacePill, in: Capsule())
            .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    private var deleteActionPill: some View {
        Button(action: onDelete) {
            HStack(spacing: 5) {
                Image("CatTrashDelete")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
                    .foregroundStyle(CatDesign.textMuted)

                Text(L10n.tr("删除"))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(CatDesign.textMuted)
            }
            .padding(.leading, 10)
            .padding(.trailing, 11)
            .frame(height: 26)
            .background(CatDesign.surfacePill, in: Capsule())
            .overlay(Capsule().strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }
}

private struct CatCompletedDownloadCard: View {
    let task: DownloadTaskSnapshot
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onOpenDetail: () -> Void

    private var sizeLine: String {
        let total = task.totalBytes > 0 ? ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file) : ""
        return total.isEmpty ? L10n.tr("离线就绪") : "\(total) · \(L10n.tr("离线就绪"))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenDetail) {
                HStack(spacing: 12) {
                    KFImage(task.request.postUrl)
                        .placeholder {
                            ZStack {
                                CatDesign.mediaPlaceholder
                                Image(systemName: "film")
                                    .foregroundStyle(CatDesign.textMuted)
                            }
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.request.displayTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.textIvory)
                            .lineLimit(1)

                        HStack(spacing: 7) {
                            Text(sizeLine)
                                .font(.system(size: 11))
                                .foregroundStyle(CatDesign.textMuted)
                                .lineLimit(1)

                            Image("CatSleepingBadge")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 18)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 6)

            Button(action: onPlay) {
                HStack(spacing: 5) {
                    Image("CatPlaySmall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text(L10n.tr("离线播放"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                }
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .frame(height: 32)
                .background(CatDesign.amberTintFill, in: Capsule())
                .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.9))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .catGlassCard(cornerRadius: 20)
        .contextMenu {
            Button(L10n.tr("查看详情"), action: onOpenDetail)
            Button(L10n.tr("播放"), action: onPlay)
            Button(L10n.tr("删除"), role: .destructive, action: onDelete)
        }
    }
}

private struct DeviceStorageStats {
    let usedFraction: Double
    let headline: String
    let freeText: String

    static func current() -> DeviceStorageStats {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? homeURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let free = values?.volumeAvailableCapacityForImportantUsage ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let used = max(0, total - free)

        let totalStr = ByteCountFormatter.string(fromByteCount: max(total, 1), countStyle: .file)
        let usedStr = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
        let freeStr = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        let fraction = total > 0 ? Double(used) / Double(total) : 0.35

        return DeviceStorageStats(
            usedFraction: fraction,
            headline: L10n.tr("已用 %@ / 共 %@", usedStr, totalStr),
            freeText: freeStr
        )
    }
}

private enum PresentedDownloadSurface: Identifiable {
    case detail(MediaItem)

    var id: String {
        switch self {
        case .detail(let item): return "detail-\(item.id.uuidString)"
        }
    }

    var item: MediaItem {
        switch self {
        case .detail(let item): return item
        }
    }
}

#Preview("Downloads") {
    NavigationStack {
        DownloadManagementView()
    }
    .environmentObject(AppState())
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.dark)
}
