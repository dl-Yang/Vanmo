import SwiftData
import SwiftUI
import Kingfisher
import VanmoCore

/// iOS 下载管理页。视觉对齐 Figma Download Light `456:4` / Dark `456:254`。
struct DownloadManagementView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var selection: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var deleteConfirmation = false
    @State private var presentedSurface: PresentedDownloadSurface?
    @State private var lastLoggedTaskSignatures: [UUID: String] = [:]

    private let actionBlue = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
    private let secondaryGray = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    private let failRed = Color(red: 255 / 255, green: 59 / 255, blue: 48 / 255)

    var body: some View {
        ZStack {
            pageBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                actionRow
                if downloadManager.tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
        }
        .accessibilityIdentifier("screen.downloads")
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isSelectionMode ? .hidden : .automatic, for: .tabBar)
        .confirmationDialog("删除选中的下载？", isPresented: $deleteConfirmation) {
            Button("删除文件和记录", role: .destructive) {
                Task {
                    await downloadManager.delete(selection)
                    selection.removeAll()
                    isSelectionMode = false
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            logTaskSnapshots(reason: "appear")
        }
        .onChange(of: downloadManager.tasks) { _, _ in
            logTaskSnapshots(reason: "update")
        }
        .onChange(of: appState.pendingDownloadDetailRequest, initial: true) { _, request in
            guard let request else { return }
            presentDetail(for: request)
            appState.consumeDownloadDetailRequest()
        }
        .fullScreenCover(item: $presentedSurface) { surface in
            switch surface {
            case .detail(let item):
                NavigationStack {
                    MediaDetailView(item: item)
                }
            case .player(let item):
                PlayerView(item: item)
            }
        }
    }

    private var pageBackground: Color {
        colorScheme == .dark ? .black : .white
    }

    private var header: some View {
        Text("下载")
            .font(.system(size: 34, weight: .bold))
            .tracking(-0.85)
            .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)
            if isSelectionMode {
                let allSelected = !downloadManager.tasks.isEmpty
                    && selection.count == downloadManager.tasks.count
                if !selection.isEmpty {
                    selectionAction("删除", role: .destructive) {
                        deleteConfirmation = true
                    }
                    .accessibilityIdentifier("downloads.deleteSelected")
                }

                selectionAction(allSelected ? "取消全选" : "全选") {
                    if allSelected {
                        selection.removeAll()
                    } else {
                        selection = Set(downloadManager.tasks.map(\.id))
                    }
                }

                selectionAction("取消") {
                    isSelectionMode = false
                    selection.removeAll()
                }
            } else if !downloadManager.tasks.isEmpty {
                if downloadManager.hasPausableTasks {
                    Button("全部暂停") {
                        Task { await downloadManager.pauseAll() }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(actionBlue)
                    .accessibilityIdentifier("downloads.pauseAll")
                } else if downloadManager.hasResumableTasks {
                    Button("全部继续") {
                        Task { await downloadManager.resumeAll() }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(actionBlue)
                    .accessibilityIdentifier("downloads.resumeAll")
                }

                Button("选择") {
                    isSelectionMode = true
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(actionBlue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func selectionAction(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        if #available(iOS 26.0, *) {
            Button(title, role: role, action: action)
                .buttonStyle(.glass)
                .controlSize(.small)
        } else {
            Button(title, role: role, action: action)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(role == .destructive ? failRed : actionBlue)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text(summaryText)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.325)
                    .foregroundStyle(secondaryGray)
                    .padding(.leading, 4)
                    .padding(.bottom, 8)

                ForEach(downloadManager.tasks) { task in
                    DownloadTaskRow(
                        task: task,
                        isSelected: selection.contains(task.id),
                        isSelectionMode: isSelectionMode,
                        actionBlue: actionBlue,
                        secondaryGray: secondaryGray,
                        failRed: failRed,
                        titleColor: colorScheme == .dark ? .white : .black,
                        play: { play(task) },
                        retry: { Task { await downloadManager.retry(task.id) } },
                        pause: { Task { await downloadManager.pause(task.id) } },
                        resume: { Task { await downloadManager.resume(task.id) } },
                        openDetail: { appState.requestDownloadDetail(for: task.request) },
                        toggleSelection: { toggleSelection(task.id) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.automatic)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(actionBlue)
            Text("暂无下载")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            Text("从媒体详情或文件浏览器发起下载后，任务会显示在这里。")
                .font(.system(size: 13))
                .foregroundStyle(secondaryGray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private var summaryText: String {
        let total = downloadManager.tasks.count
        guard total > 0 else { return "暂无任务" }
        let active = downloadManager.tasks.filter {
            $0.status == .downloading || $0.status == .queued
        }.count
        let paused = downloadManager.tasks.filter { $0.status == .paused }.count
        let failed = downloadManager.tasks.filter { $0.status == .failed }.count
        var parts = ["\(total) 项"]
        if active > 0 {
            parts.append("\(active) 进行中")
        }
        if paused > 0 {
            parts.append("\(paused) 已暂停")
        }
        if failed > 0 {
            parts.append("\(failed) 失败")
        }
        if parts.count == 1 {
            parts.append("全部完成")
        }
        return parts.joined(separator: " · ")
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func play(_ task: DownloadTaskSnapshot) {
        guard task.status == .completed else {
#if DEBUG
            print("[Debug][Downloads] play skipped task=\(task.id.uuidString) reason=status status=\(task.status.rawValue)")
#endif
            return
        }
        let resolvedURL: URL
        do {
            resolvedURL = try downloadManager.completedFileURL(for: task.id)
        } catch {
#if DEBUG
            print("[Debug][Downloads] play skipped task=\(task.id.uuidString) reason=resolve error=\(error.localizedDescription)")
#endif
            return
        }
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
#if DEBUG
            print("[Debug][Downloads] play skipped task=\(task.id.uuidString) reason=missing-file ext=\(resolvedURL.pathExtension.lowercased())")
#endif
            return
        }
        let url = resolvedURL
#if DEBUG
        print("[Debug][Downloads] play completed task=\(task.id.uuidString) ext=\(url.pathExtension.lowercased())")
#endif
        let fileURL = URL(fileURLWithPath: url.path, isDirectory: false)
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
        presentedSurface = .player(item)
#if DEBUG
        print("[Debug][Downloads] present player mediaType=\(item.mediaType.rawValue) ext=\(fileURL.pathExtension.lowercased())")
#endif
    }

    private func presentDetail(for request: DownloadRequest) {
        let stored = storedMediaItem(for: request)
        let item = stored ?? makeDownloadDetailFallback(for: request)
#if DEBUG
        print("[Debug][Downloads] open detail mediaType=\(item.mediaType.rawValue) resolved=\(stored == nil ? "fallback" : "stored")")
#endif
        presentedSurface = .detail(item)
    }

    private func logTaskSnapshots(reason: String) {
#if DEBUG
        let tasks = downloadManager.tasks
        print("[Debug][Downloads] \(reason) count=\(tasks.count)")
        for task in tasks {
            let percent = task.totalBytes > 0 ? Int(task.progress * 100) : -1
            let bucket = percent < 0 ? -1 : (percent / 10) * 10
            let signature = "\(task.status.rawValue)|\(bucket)"
            guard lastLoggedTaskSignatures[task.id] != signature else { continue }
            lastLoggedTaskSignatures[task.id] = signature
            print("[Debug][Downloads] task=\(task.id.uuidString) status=\(task.status.rawValue) progress=\(percent) received=\(task.receivedBytes) total=\(task.totalBytes) type=\(task.request.connectionType?.rawValue ?? "none") media=\(task.request.mediaType.rawValue)")
        }
#endif
    }

    private func storedMediaItem(for request: DownloadRequest) -> MediaItem? {
        if let mediaID = request.sourceMediaItemID {
            let descriptor = FetchDescriptor<MediaItem>(
                predicate: #Predicate { $0.id == mediaID }
            )
            if let item = try? modelContext.fetch(descriptor).first {
                return item
            }
        }

        let serverID = request.mediaType == .tvEpisode
            ? request.seriesServerID
            : request.sourceServerID
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
        item.posterURL = request.postUrl
        item.backdropURL = request.postUrl
        item.sourceConnectionId = request.sourceConnectionId
        item.serverId = opensSeries ? request.seriesServerID : request.sourceServerID
        item.seriesId = request.seriesServerID
        item.showTitle = request.showTitle
        return item
    }
}

private enum PresentedDownloadSurface: Identifiable {
    case detail(MediaItem)
    case player(MediaItem)

    var id: String {
        switch self {
        case .detail(let item):
            return "detail-\(item.id.uuidString)"
        case .player(let item):
            return "player-\(item.id.uuidString)"
        }
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTaskSnapshot
    let isSelected: Bool
    let isSelectionMode: Bool
    let actionBlue: Color
    let secondaryGray: Color
    let failRed: Color
    let titleColor: Color
    let play: () -> Void
    let retry: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let openDetail: () -> Void
    let toggleSelection: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: isSelectionMode ? toggleSelection : openDetail) {
                HStack(alignment: .center, spacing: 16) {
                    if isSelectionMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isSelected ? actionBlue : secondaryGray.opacity(0.7))
                    }

                    poster

                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.request.displayTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                        Text(statusText)
                            .font(.system(size: 13, weight: .medium))
                            .tracking(-0.325)
                            .foregroundStyle(task.status == .failed ? failRed : secondaryGray)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            if !isSelectionMode {
                DownloadCircularActionButton(
                    task: task,
                    actionBlue: actionBlue,
                    play: play,
                    retry: retry,
                    pause: pause,
                    resume: resume
                )
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.6)
        }
        .contextMenu {
            Button("查看详情", action: openDetail)
            if task.status == .queued || task.status == .downloading {
                Button("暂停", action: pause)
            } else if task.status == .paused {
                Button("继续", action: resume)
            } else if task.status == .completed {
                Button("播放", action: play)
            } else if task.status == .failed {
                Button("重新下载", action: retry)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.request.displayTitle)
        .accessibilityValue(statusText)
    }

    private var poster: some View {
        KFImage(task.request.postUrl)
            .placeholder {
                LinearGradient(
                    colors: [
                        Color(red: 160 / 255, green: 176 / 255, blue: 200 / 255),
                        Color(red: 96 / 255, green: 116 / 255, blue: 144 / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusText: String {
        let total = formattedBytes(task.totalBytes)
        let received = formattedBytes(task.receivedBytes)
        switch task.status {
        case .queued:
            return "等待中 · 即将开始"
        case .downloading:
            if task.totalBytes > 0 {
                return "下载中 \(Int(task.progress * 100))% · \(received) / \(total)"
            }
            return "下载中"
        case .paused:
            if task.totalBytes > 0 {
                return "已暂停 · \(received) / \(total)"
            }
            return "已暂停"
        case .completed:
            return total.isEmpty ? "已完成" : "已完成 · \(total)"
        case .failed:
            let reason = task.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let reason, !reason.isEmpty {
                return "下载失败 · \(reason)"
            }
            return "下载失败"
        }
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct DownloadCircularActionButton: View {
    let task: DownloadTaskSnapshot
    let actionBlue: Color
    let play: () -> Void
    let retry: () -> Void
    let pause: () -> Void
    let resume: () -> Void

    var body: some View {
        Button(action: performAction) {
            ZStack {
                switch task.status {
                case .downloading:
                    progressRing(
                        progress: task.totalBytes > 0 ? task.progress : nil,
                        tint: actionBlue
                    )
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(actionBlue)
                case .queued:
                    progressRing(progress: 0, tint: Color(white: 0.72))
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(white: 0.55))
                case .paused:
                    progressRing(
                        progress: task.totalBytes > 0 ? task.progress : 0,
                        tint: Color(white: 0.72)
                    )
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.45))
                        .offset(x: 1)
                case .completed:
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .offset(x: 1)
                case .failed:
                    Circle()
                        .fill(Color.primary.opacity(0.06))
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(actionLabel)
    }

    private func performAction() {
#if DEBUG
        print("[Debug][Downloads] action status=\(task.status.rawValue) task=\(task.id.uuidString)")
#endif
        switch task.status {
        case .queued, .downloading:
            pause()
        case .paused:
            resume()
        case .completed:
            play()
        case .failed:
            retry()
        }
    }

    private var actionLabel: String {
        switch task.status {
        case .queued, .downloading: return "暂停"
        case .paused: return "继续"
        case .completed: return "播放"
        case .failed: return "重新下载"
        }
    }

    private func progressRing(progress: Double?, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: 2.4)
            if let progress {
                Circle()
                    .trim(from: 0, to: min(max(progress, 0.02), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 32, height: 32)
    }
}

#Preview("Downloads") {
    NavigationStack {
        DownloadManagementView()
    }
    .environmentObject(AppState())
    .environmentObject(DownloadManager.shared)
}
