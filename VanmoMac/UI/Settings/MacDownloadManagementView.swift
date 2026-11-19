import AppKit
import SwiftUI
import VanmoCore

struct MacDownloadManagementView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Set<UUID> = []
    @State private var confirmsDeletion = false
    @State private var pendingSingleDeleteID: UUID?
    @State private var isSelectionMode = false
    @State private var lastLoggedTaskSignatures: [UUID: String] = [:]

    private var theme: MacThemeColors {
        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme) ? .dark : .light
    }

    private var isDark: Bool {
        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme)
    }

    private var activeTasks: [DownloadTaskSnapshot] {
        downloadManager.tasks.filter { $0.status != .completed }
    }

    private var completedTasks: [DownloadTaskSnapshot] {
        downloadManager.tasks.filter { $0.status == .completed }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacVibrancyBackground(isDark: isDark, blendingMode: .behindWindow)
                .ignoresSafeArea()

            theme.appBackground.opacity(0.92)
                .ignoresSafeArea()

            MacCatAmbientHalo()
                .offset(x: -40, y: -60)

            VStack(spacing: 0) {
                headerBar
                if let stats = storageStats {
                    storageCard(stats: stats)
                        .padding(.horizontal, MacDesignTokens.Layout.downloadContentPadding)
                        .padding(.bottom, 14)
                }

                if downloadManager.tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
        }
        .macTheme(theme)
        .preferredColorScheme(appState.appearanceMode.preferredColorScheme)
        .onAppear { logTaskSnapshots(reason: "appear") }
        .onChange(of: downloadManager.tasks) { _, _ in
            logTaskSnapshots(reason: "update")
        }
        .confirmationDialog(L10n.tr("删除选中的下载？"), isPresented: $confirmsDeletion) {
            Button(L10n.tr("删除文件和记录"), role: .destructive) {
                let targetSingleID = pendingSingleDeleteID
                let idsToDelete = targetSingleID.map { Set([$0]) } ?? selection
                Task {
                    await downloadManager.delete(idsToDelete)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let targetSingleID {
                            selection.remove(targetSingleID)
                            pendingSingleDeleteID = nil
                        } else {
                            selection.removeAll()
                            isSelectionMode = false
                        }
                    }
                }
            }
            Button(L10n.tr("取消"), role: .cancel) {
                pendingSingleDeleteID = nil
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 9) {
                Text(L10n.tr("下载"))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                statusBadgePill
            }

            Spacer(minLength: 12)

            if isSelectionMode {
                if !selection.isEmpty {
                    Button(L10n.tr("删除所选 (%d)", selection.count)) {
                        pendingSingleDeleteID = nil
                        confirmsDeletion = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.dangerRed)
                    .padding(.horizontal, 11)
                    .frame(height: 28)
                    .background(theme.dangerRed.opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(theme.dangerRed.opacity(0.4), lineWidth: 0.8)
                    }
                }

                let allSelected = !downloadManager.tasks.isEmpty && selection.count == downloadManager.tasks.count
                Button(allSelected ? L10n.tr("取消全选") : L10n.tr("全选")) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if allSelected {
                            selection.removeAll()
                        } else {
                            selection = Set(downloadManager.tasks.map(\.id))
                        }
                    }
                }
                .buttonStyle(MacCatGlassButtonStyle(height: 28, horizontalPadding: 11))

                Button(L10n.tr("取消")) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSelectionMode = false
                        selection.removeAll()
                    }
                }
                .buttonStyle(MacCatGlassButtonStyle(height: 28, horizontalPadding: 11))
            } else if !downloadManager.tasks.isEmpty {
                if downloadManager.hasPausableTasks {
                    Button(L10n.tr("全部暂停")) {
                        Task {
#if DEBUG
                            VanmoLogger.storage.info("[Debug][Downloads] action pauseAll")
#endif
                            await downloadManager.pauseAll()
                        }
                    }
                    .buttonStyle(MacCatGlassButtonStyle(height: 28, horizontalPadding: 11))
                }

                if downloadManager.hasResumableTasks {
                    Button(L10n.tr("全部继续")) {
                        Task {
#if DEBUG
                            VanmoLogger.storage.info("[Debug][Downloads] action resumeAll")
#endif
                            await downloadManager.resumeAll()
                        }
                    }
                    .buttonStyle(MacCatAmberGlassButtonStyle(height: 28, horizontalPadding: 11))
                }

                Button(L10n.tr("选择")) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSelectionMode = true
                    }
                }
                .buttonStyle(MacCatGlassButtonStyle(height: 28, horizontalPadding: 11))
            }
        }
        .padding(.leading, MacDesignTokens.Layout.trafficLightsLeadingInset)
        .padding(.trailing, MacDesignTokens.Layout.downloadContentPadding)
        .padding(.top, MacDesignTokens.Layout.trafficLightsTopInset + 10)
        .padding(.bottom, 14)
    }

    private var statusBadgePill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(theme.accentAmber)
                .frame(width: 5, height: 5)

            Text(summaryText)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.accentAmber)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(theme.amberTintFill, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
        }
    }

    private var summaryText: String {
        let total = downloadManager.tasks.count
        guard total > 0 else { return L10n.tr("暂无任务") }
        let active = downloadManager.tasks.filter {
            $0.status == .downloading || $0.status == .queued
        }.count
        let paused = downloadManager.tasks.filter { $0.status == .paused }.count
        let failed = downloadManager.tasks.filter { $0.status == .failed }.count
        var parts = [L10n.tr("%d 项", total)]
        if active > 0 { parts.append(L10n.tr("%d 进行中", active)) }
        if paused > 0 { parts.append(L10n.tr("%d 已暂停", paused)) }
        if failed > 0 { parts.append(L10n.tr("%d 失败", failed)) }
        if parts.count == 1 { parts.append(L10n.tr("全部完成")) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Storage Card

    private func storageCard(stats: (usedText: String, totalText: String, freeText: String, usedFraction: Double)) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.tr("本地媒体存储  ·  %@ / %@", stats.usedText, stats.totalText))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(L10n.tr("剩余 %@", stats.freeText))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accentAmber)
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.progressTrack)
                        .frame(height: 5)

                    Capsule()
                        .fill(MacDesignTokens.glowAmber)
                        .frame(width: max(6, width * stats.usedFraction), height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .macCatGlassCard(theme: theme, cornerRadius: 12)
    }

    private var storageStats: (usedText: String, totalText: String, freeText: String, usedFraction: Double)? {
        let targetURL = URL(fileURLWithPath: downloadManager.destination.rootPath)
        let values = try? targetURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }
        let available = values?.volumeAvailableCapacityForImportantUsage
            ?? Int64(values?.volumeAvailableCapacity ?? 0)
        let used = max(0, total - available)
        let fraction = min(max(Double(used) / Double(total), 0), 1)
        return (
            ByteCountFormatter.string(fromByteCount: used, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: total, countStyle: .file),
            ByteCountFormatter.string(fromByteCount: available, countStyle: .file),
            fraction
        )
    }

    // MARK: - Empty & List

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Image("MacCatFolderCurious")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 66)

            Text(L10n.tr("暂无下载"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

            Text(L10n.tr("从媒体详情或文件浏览器发起下载后，任务会显示在这里。"))
                .font(.system(size: 12.5))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !activeTasks.isEmpty {
                    groupSection(title: "\(L10n.tr("进行中").uppercased()) · \(activeTasks.count)", tasks: activeTasks)
                }
                if !completedTasks.isEmpty {
                    groupSection(title: "\(L10n.tr("已完成").uppercased()) · \(completedTasks.count)", tasks: completedTasks)
                }
            }
            .padding(.horizontal, MacDesignTokens.Layout.downloadContentPadding)
            .padding(.bottom, 24)
        }
    }

    private func groupSection(title: String, tasks: [DownloadTaskSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .tracking(0.5)

            ForEach(tasks) { task in
                MacDownloadTaskRow(
                    task: task,
                    isSelected: selection.contains(task.id),
                    isSelectionMode: isSelectionMode,
                    isDark: isDark,
                    play: { play(task) },
                    reveal: { reveal(task) },
                    retry: { Task { await downloadManager.retry(task.id) } },
                    pause: { Task { await downloadManager.pause(task.id) } },
                    resume: { Task { await downloadManager.resume(task.id) } },
                    deleteTask: {
                        pendingSingleDeleteID = task.id
                        confirmsDeletion = true
                    },
                    openDetail: { openDetail(for: task) },
                    toggleSelection: {
                        if selection.contains(task.id) {
                            selection.remove(task.id)
                        } else {
                            selection.insert(task.id)
                        }
                    }
                )
            }
        }
    }

    private func openDetail(for task: DownloadTaskSnapshot) {
#if DEBUG
        VanmoLogger.storage.info("[Debug][Downloads] open detail task=\(task.id.uuidString, privacy: .public) mediaType=\(task.request.mediaType.rawValue, privacy: .public)")
#endif
        appState.requestDownloadDetail(
            for: task.request,
            focusedEpisode: episodeLocator(for: task.request)
        )
        appState.activateMainWindow()
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
            VanmoLogger.storage.info("[Debug][Downloads] task=\(task.id.uuidString, privacy: .public) status=\(task.status.rawValue, privacy: .public) progress=\(percent, privacy: .public) received=\(task.receivedBytes, privacy: .public) total=\(task.totalBytes, privacy: .public) type=\(task.request.connectionType?.rawValue ?? "none", privacy: .public) media=\(task.request.mediaType.rawValue, privacy: .public)")
        }
#endif
    }

    private func episodeLocator(for request: DownloadRequest) -> MacEpisodeDetailLocator? {
        guard request.mediaType == .tvEpisode,
              let seasonNumber = request.seasonNumber,
              let episodeNumber = request.episodeNumber else {
            return nil
        }
        return MacEpisodeDetailLocator(
            serverID: request.sourceServerID,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
    }

    private func play(_ task: DownloadTaskSnapshot) {
        guard task.status == .completed,
              let url = try? downloadManager.completedFileURL(for: task.id),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let item = MediaItem(
            title: task.request.displayTitle,
            fileURL: url,
            mediaType: task.request.mediaType,
            fileSize: task.totalBytes
        )
        item.showTitle = task.request.showTitle
        item.seasonNumber = task.request.seasonNumber
        item.episodeNumber = task.request.episodeNumber
        item.episodeTitle = task.request.episodeTitle
        appState.play(item)
    }

    private func reveal(_ task: DownloadTaskSnapshot) {
        guard let url = try? downloadManager.completedFileURL(for: task.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct MacDownloadTaskRow: View {
    @Environment(\.macTheme) private var theme

    let task: DownloadTaskSnapshot
    let isSelected: Bool
    let isSelectionMode: Bool
    let isDark: Bool
    let play: () -> Void
    let reveal: () -> Void
    let retry: () -> Void
    let pause: () -> Void
    let resume: () -> Void
    let deleteTask: () -> Void
    let openDetail: () -> Void
    let toggleSelection: () -> Void

    private var isActiveRow: Bool {
        task.status == .downloading || task.status == .queued
    }

    var body: some View {
        HStack(spacing: 11) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            MacRemoteImage(url: task.request.postUrl)
                .frame(width: 38, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.downloadPoster, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Radius.downloadPoster, style: .continuous)
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.75)
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(task.request.displayTitle)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if task.status == .completed {
                        MacSleepingCatWatchedPill()
                    }
                }

                Text(subtitleLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)

                if task.status == .queued || task.status == .downloading || task.status == .paused {
                    MacCatProgressTrack(
                        progress: task.totalBytes > 0 ? task.progress : 0.15,
                        trackColor: theme.progressTrack,
                        height: 3,
                        showsPawThumb: true,
                        pawSize: 10
                    )
                }

                if let errorMessage = task.errorMessage, task.status == .failed {
                    Text(errorMessage)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.dangerRed)
                        .lineLimit(2)
                }
            }

            if !isSelectionMode {
                iconActions
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .macCatGlassCard(
            theme: theme,
            cornerRadius: MacDesignTokens.Radius.downloadCard,
            isHighlighted: isSelected || isActiveRow
        )
        .contentShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.downloadCard, style: .continuous))
        .onTapGesture {
            if isSelectionMode {
                toggleSelection()
            } else {
                openDetail()
            }
        }
        .contextMenu {
            Button(L10n.tr("查看详情"), action: openDetail)
            Divider()
            if task.status == .queued || task.status == .downloading {
                Button(L10n.tr("暂停"), action: pause)
            } else if task.status == .paused {
                Button(L10n.tr("继续"), action: resume)
            } else if task.status == .completed {
                Button(L10n.tr("播放"), action: play)
                Button(L10n.tr("在 Finder 中显示"), action: reveal)
            } else if task.status == .failed {
                Button(L10n.tr("重新下载"), action: retry)
            }
            Divider()
            Button(L10n.tr("删除"), role: .destructive, action: deleteTask)
        }
    }

    @ViewBuilder
    private var iconActions: some View {
        HStack(spacing: 5) {
            if task.status == .queued || task.status == .downloading {
                Button(action: pause) {
                    Image("MacCatEarPause")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: 26, height: 26)
                        .background(theme.amberTintFill, in: Circle())
                        .overlay {
                            Circle().strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .help(L10n.tr("暂停"))
            } else if task.status == .paused {
                Button(action: resume) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accentAmber)
                        .frame(width: 26, height: 26)
                        .background(theme.amberTintFill, in: Circle())
                        .overlay {
                            Circle().strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .help(L10n.tr("继续"))
            } else if task.status == .failed {
                Button(action: retry) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.dangerRed)
                        .frame(width: 26, height: 26)
                        .background(theme.dangerRed.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("重新下载"))
            }

            if task.status == .completed {
                Button(action: play) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.accentAmber)
                        .frame(width: 26, height: 26)
                        .background(theme.amberTintFill, in: Circle())
                        .overlay {
                            Circle().strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .help(L10n.tr("播放"))

                Button(action: reveal) {
                    Image("MacRevealFinder")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 26, height: 26)
                        .background(theme.surfacePill, in: Circle())
                }
                .buttonStyle(.plain)
                .help(L10n.tr("在 Finder 中显示"))
            }

            Button(action: deleteTask) {
                Image("MacTrashDelete")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(theme.surfacePill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("删除"))
        }
    }

    private var subtitleColor: Color {
        switch task.status {
        case .downloading, .queued: return theme.accentAmber
        case .failed: return theme.dangerRed
        default: return theme.secondaryText
        }
    }

    private var subtitleLine: String {
        var parts: [String] = []
        if let season = task.request.seasonNumber, let episode = task.request.episodeNumber {
            parts.append(String(format: "S%02d E%02d", season, episode))
        }
        if task.totalBytes > 0 {
            if task.status == .downloading || task.status == .queued || task.status == .paused {
                let received = ByteCountFormatter.string(fromByteCount: task.receivedBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
                parts.append("\(received) / \(total)")
            } else {
                parts.append(ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file))
            }
        }
        switch task.status {
        case .queued:
            parts.append(L10n.tr("等待中"))
        case .downloading:
            if task.totalBytes > 0 {
                parts.append("\(Int((task.progress * 100).rounded()))%")
            } else {
                parts.append(L10n.tr("下载中"))
            }
        case .paused:
            parts.append(L10n.tr("已暂停"))
        case .completed:
            parts.append(L10n.tr("可离线播放"))
        case .failed:
            parts.append(L10n.tr("失败"))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Downloads Dark") {
    MacDownloadManagementView()
        .environmentObject(MacAppState())
        .environmentObject(DownloadManager.shared)
        .macTheme(.dark)
        .frame(width: 560, height: 600)
}
