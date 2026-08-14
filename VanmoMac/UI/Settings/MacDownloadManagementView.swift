import AppKit
import SwiftUI
import VanmoCore

struct MacDownloadManagementView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var selection: Set<UUID> = []
    @State private var confirmsDeletion = false
    @State private var isSelectionMode = false

    private var theme: MacThemeColors {
        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme) ? .dark : .light
    }

    private var isDark: Bool {
        appState.appearanceMode.resolvedIsDark(systemColorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            MacVibrancyBackground(isDark: isDark, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if downloadManager.tasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
        }
        .macTheme(theme)
        .confirmationDialog("删除选中的下载？", isPresented: $confirmsDeletion) {
            Button("删除文件和记录", role: .destructive) {
                Task {
                    await downloadManager.delete(selection)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection.removeAll()
                        isSelectionMode = false
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("下载")
                    .font(MacDesignTokens.Typography.sectionTitle)
                    .foregroundStyle(theme.primaryText)
                Text(summaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 12)

            if isSelectionMode {
                if !selection.isEmpty {
                    deleteSelectionButton
                }

                let allSelected = !downloadManager.tasks.isEmpty && selection.count == downloadManager.tasks.count
                Button(allSelected ? "取消全选" : "全选") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if allSelected {
                            selection.removeAll()
                        } else {
                            selection = Set(downloadManager.tasks.map { $0.id })
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("取消") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isSelectionMode = false
                        selection.removeAll()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            } else {
                if !downloadManager.tasks.isEmpty {
                    Button("选择") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isSelectionMode = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .padding(.leading, MacDesignTokens.Layout.trafficLightsLeadingInset)
        .padding(.trailing, MacDesignTokens.Layout.downloadContentPadding)
        .padding(.top, MacDesignTokens.Layout.trafficLightsTopInset + 12)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var deleteSelectionButton: some View {
        let label = "删除所选 (\(selection.count))"
        if #available(macOS 26.0, *) {
            Button(label, role: .destructive) {
                confirmsDeletion = true
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
            .tint(.red)
        } else {
            Button(label, role: .destructive) {
                confirmsDeletion = true
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private var summaryText: String {
        let total = downloadManager.tasks.count
        guard total > 0 else { return "暂无任务" }
        let active = downloadManager.tasks.filter {
            $0.status == .downloading || $0.status == .queued
        }.count
        let failed = downloadManager.tasks.filter { $0.status == .failed }.count
        if active > 0 {
            return "\(total) 项 · \(active) 进行中"
        }
        if failed > 0 {
            return "\(total) 项 · \(failed) 失败"
        }
        return "\(total) 项 · 全部完成"
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            emptyIcon
                .padding(.bottom, 8)

            Text("暂无下载")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Text("从媒体详情或文件浏览器发起下载后，任务会显示在这里。")
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var emptyIcon: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return ZStack {
            if #available(macOS 26.0, *) {
                Color.clear
                    .frame(width: 88, height: 88)
                    .glassEffect(.regular.tint(MacDesignTokens.accentBlue.opacity(0.18)), in: shape)
            } else {
                shape
                    .fill(theme.emptyIconBackground)
                    .frame(width: 88, height: 88)
                    .overlay {
                        shape.stroke(theme.emptyIconBorder, lineWidth: 1)
                    }
            }

            Image(systemName: "arrow.down.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(MacDesignTokens.accentBlue)
        }
    }

    private var taskList: some View {
        List {
            ForEach(downloadManager.tasks) { task in
                MacDownloadTaskRow(
                    task: task,
                    isSelected: selection.contains(task.id),
                    isSelectionMode: isSelectionMode,
                    isDark: isDark,
                    play: { play(task) },
                    reveal: { reveal(task) },
                    retry: { Task { await downloadManager.retry(task.id) } },
                    toggleSelection: {
                        if selection.contains(task.id) {
                            selection.remove(task.id)
                        } else {
                            selection.insert(task.id)
                        }
                    }
                )
                .tag(task.id)
                .listRowInsets(EdgeInsets(
                    top: 6,
                    leading: MacDesignTokens.Layout.downloadContentPadding,
                    bottom: 6,
                    trailing: MacDesignTokens.Layout.downloadContentPadding
                ))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.automatic)
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
    let toggleSelection: () -> Void

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MacDesignTokens.Radius.downloadCard, style: .continuous)
    }

    var body: some View {
        HStack(spacing: MacDesignTokens.Layout.downloadRowSpacing) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? MacDesignTokens.accentBlue : theme.secondaryText.opacity(0.5))
                    .padding(.leading, 8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            poster

            VStack(alignment: .leading, spacing: 8) {
                Text(task.request.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    statusBadge
                    if let detailText {
                        Text(detailText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                if task.status == .queued || task.status == .downloading {
                    ProgressView(value: task.totalBytes > 0 ? task.progress : nil)
                        .tint(MacDesignTokens.accentBlue)
                        .controlSize(.small)
                }

                if let errorMessage = task.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(MacDesignTokens.ratingRed)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if !isSelectionMode {
                actionButtons
                    .transition(.opacity)
            }
        }
        .padding(14)
        .background { cardBackground }
        .overlay {
            cardShape
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .contentShape(cardShape)
        .onTapGesture {
            if isSelectionMode {
                toggleSelection()
            }
        }
        .contextMenu {
            if task.status == .completed {
                Button("播放", action: play)
                Button("在 Finder 中显示", action: reveal)
            } else if task.status == .failed {
                Button("重新下载", action: retry)
            }
        }
    }

    private var poster: some View {
        MacRemoteImage(url: task.request.postUrl)
            .frame(
                width: MacDesignTokens.Layout.downloadWidth,
                height: MacDesignTokens.Layout.downloadHeight
            )
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.downloadPoster, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.downloadPoster, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isDark ? 0.18 : 0.08), lineWidth: 1)
            }
    }

    private var statusBadge: some View {
        Text(statusText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(statusForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusTint, in: Capsule())
    }

    @ViewBuilder
    private var actionButtons: some View {
        if task.status == .completed {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button("播放", action: play)
                            .buttonStyle(.glassProminent)
                            .controlSize(.small)
                            .tint(MacDesignTokens.accentBlue)

                        Button(action: reveal) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .help("在 Finder 中显示")
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button("播放", action: play)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(action: reveal) {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("在 Finder 中显示")
                }
            }
        } else if task.status == .failed {
            if #available(macOS 26.0, *) {
                Button("重新下载", action: retry)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .tint(MacDesignTokens.accentBlue)
            } else {
                Button("重新下载", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        let tint = isSelected
            ? MacDesignTokens.accentBlue.opacity(isDark ? 0.22 : 0.12)
            : (isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.55))

        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.tint(tint), in: cardShape)
        } else {
            cardShape
                .fill(isSelected ? MacDesignTokens.accentBlue.opacity(0.1) : theme.secondaryButtonBackground)
                .background(.ultraThinMaterial, in: cardShape)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return MacDesignTokens.accentBlue.opacity(0.45)
        }
        return isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var detailText: String? {
        if let season = task.request.seasonNumber, let episode = task.request.episodeNumber {
            var parts = ["S\(season)E\(episode)"]
            if let episodeTitle = task.request.episodeTitle, !episodeTitle.isEmpty {
                parts.append(episodeTitle)
            }
            return parts.joined(separator: " · ")
        }
        if task.totalBytes > 0 {
            if task.status == .downloading || task.status == .queued {
                let received = ByteCountFormatter.string(fromByteCount: task.receivedBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
                return "\(received) / \(total)"
            }
            return ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
        }
        return nil
    }

    private var statusText: String {
        switch task.status {
        case .queued: return "等待中"
        case .downloading: return task.totalBytes > 0 ? "\(Int(task.progress * 100))%" : "下载中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }

    private var statusTint: Color {
        switch task.status {
        case .queued: return theme.secondaryText.opacity(0.2)
        case .downloading: return MacDesignTokens.accentBlue.opacity(0.28)
        case .completed: return Color.green.opacity(0.28)
        case .failed: return MacDesignTokens.ratingRed.opacity(0.28)
        }
    }

    private var statusForeground: Color {
        switch task.status {
        case .queued: return theme.secondaryText
        case .downloading: return MacDesignTokens.accentBlue
        case .completed: return Color.green
        case .failed: return MacDesignTokens.ratingRed
        }
    }
}

#Preview("Downloads") {
    MacDownloadManagementView()
        .environmentObject(MacAppState())
        .environmentObject(DownloadManager.shared)
        .macTheme(.dark)
        .frame(width: 720, height: 640)
}
