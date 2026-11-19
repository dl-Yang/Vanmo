import AppKit
import SwiftData
import SwiftUI
import VanmoCore

struct MacDirectLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macTheme) private var theme
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @StateObject private var model = DirectLinkListModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacCatAmbientHalo()
                .offset(x: -70, y: -30)

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        inputSection
                        recentSection
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appBackground)
        .task {
            model.configure(modelContext: modelContext)
            isFieldFocused = true
        }
        .onChange(of: appState.isPlayerPresented) { _, isPresented in
            if !isPresented { model.reload() }
        }
        .alert(L10n.tr("错误"), isPresented: alertBinding) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.tr("打开 URL 链接"))
                .font(MacDesignTokens.Typography.headerTitle)
                .foregroundStyle(theme.primaryText)
            Text(L10n.tr("串流或下载 http(s) 直链视频"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    // MARK: - 输入

    private var isInputEmpty: Bool {
        model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                urlField
                Button(action: playInput) {
                    Label(L10n.tr("播放"), systemImage: "play.fill")
                }
                .buttonStyle(MacCatAmberButtonStyle(height: 38, horizontalPadding: 18))

                Button(action: downloadInput) {
                    Label(L10n.tr("下载"), systemImage: "arrow.down.to.line")
                }
                .buttonStyle(MacCatGlassButtonStyle(height: 38, horizontalPadding: 16))
            }

            if let error = model.inputError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.dangerRed)
            }

            Text(L10n.tr("支持 MP4、MKV、MOV、HLS 等格式。链接只保存在本机；需要账号密码的地址请改用 WebDAV 连接。"))
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 12)
    }

    private var urlField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isFieldFocused ? theme.accentAmber : theme.secondaryText)
            TextField(L10n.tr("粘贴或输入 https:// 链接"), text: $model.input)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.primaryText)
                .focused($isFieldFocused)
                .onSubmit(playInput)
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in model.input = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 38)
        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                .strokeBorder(fieldStroke, lineWidth: isFieldFocused || model.inputError != nil ? 1.2 : 0.9)
        }
    }

    private var fieldStroke: Color {
        if model.inputError != nil { return theme.dangerRed }
        return isFieldFocused ? theme.strokeAmber : theme.strokeGlass
    }

    // MARK: - 最近链接

    @ViewBuilder
    private var recentSection: some View {
        if model.entries.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MacCatSectionHeaderRow(
                    title: L10n.tr("最近链接"),
                    badgeText: "\(model.entries.count)",
                    showsStretchingCat: true
                )

                ForEach(model.entries) { item in
                    let task = DirectLinkLibrary.downloadTask(for: item.fileURL, in: downloadManager.tasks)
                    MacDirectLinkRow(
                        item: item,
                        task: task,
                        onPlay: { appState.play(item) },
                        onDownloadAction: { Task { await handleDownloadAction(for: item, task: task) } },
                        onReveal: { reveal(task) },
                        onRemove: { model.remove(item) }
                    )
                    .contextMenu { rowMenu(for: item, task: task) }
                }
            }
            .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
            .padding(.top, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("MacCatFolderCurious")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 56)
            Text(L10n.tr("还没有链接"))
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(theme.primaryText)
            Text(L10n.tr("播放或下载过的链接会出现在这里，并保留续播进度。"))
                .font(.system(size: 12))
                .foregroundStyle(theme.emptyDescriptionText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.strokeGlass, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 32)
    }

    @ViewBuilder
    private func rowMenu(for item: MediaItem, task: DownloadTaskSnapshot?) -> some View {
        Button(L10n.tr("播放")) { appState.play(item) }
        if !DirectLinkLibrary.isStreamOnly(item.fileURL) {
            if task == nil {
                Button(L10n.tr("下载")) { Task { await model.download(item, using: downloadManager) } }
            } else if task?.status == .failed {
                Button(L10n.tr("重试")) { Task { await handleDownloadAction(for: item, task: task) } }
            }
        }
        Button(L10n.tr("拷贝链接")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.fileURL.absoluteString, forType: .string)
        }
        if task?.status == .completed {
            Button(L10n.tr("在 Finder 中显示")) { reveal(task) }
        }
        Divider()
        Button(L10n.tr("移除"), role: .destructive) { model.remove(item) }
    }

    // MARK: - 操作

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private func playInput() {
        guard let item = model.addInput() else { return }
        appState.play(item)
    }

    private func downloadInput() {
        guard !isInputEmpty else { return }
        Task { await model.downloadInput(using: downloadManager) }
    }

    private func handleDownloadAction(for item: MediaItem, task: DownloadTaskSnapshot?) async {
        guard let task else {
            await model.download(item, using: downloadManager)
            return
        }
        switch task.status {
        case .queued, .downloading:
            await downloadManager.pause(task.id)
        case .paused:
            await downloadManager.resume(task.id)
        case .failed:
            await downloadManager.retry(task.id)
        case .completed:
            break
        }
    }

    private func reveal(_ task: DownloadTaskSnapshot?) {
        guard let task, let url = try? downloadManager.completedFileURL(for: task.id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct MacDirectLinkRow: View {
    @Environment(\.macTheme) private var theme

    let item: MediaItem
    let task: DownloadTaskSnapshot?
    let onPlay: () -> Void
    let onDownloadAction: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    private var isStreamOnly: Bool { DirectLinkLibrary.isStreamOnly(item.fileURL) }

    var body: some View {
        HStack(spacing: 12) {
            Text(DirectLinkLibrary.formatLabel(for: item.fileURL))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(theme.accentAmber)
                .frame(width: 40, height: 40)
                .background(theme.amberTintFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.strokeAmber, lineWidth: 0.8)
                }
            textColumn
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 62)
        .macCatGlassCard(theme: theme, cornerRadius: 14, isHighlighted: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L10n.tr("播放"), onPlay)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Text(item.fileURL.host ?? "")
                    .foregroundStyle(theme.secondaryText)
                if let meta {
                    Circle().fill(theme.tertiaryText).frame(width: 3, height: 3)
                    Text(meta.text).foregroundStyle(meta.color)
                }
            }
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            if showsResumeBar {
                MacCatProgressTrack(
                    progress: item.playbackProgress,
                    trackColor: theme.progressTrack,
                    height: 3,
                    showsPawThumb: true,
                    pawSize: 8
                )
                .frame(width: 240)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if isHovered {
                iconButton("play.fill", tint: theme.accentAmber, help: L10n.tr("播放"), action: onPlay)
            }
            if isStreamOnly {
                Text(L10n.tr("仅串流"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.chipText)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(theme.chipBackground, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(theme.chipBorder, lineWidth: 0.8)
                    }
            } else {
                downloadControl
            }
            if isHovered {
                iconButton("trash", tint: theme.dangerRed, help: L10n.tr("移除"), action: onRemove)
            }
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        switch task?.status {
        case .queued, .downloading, .paused:
            Button(action: onDownloadAction) {
                ZStack {
                    Circle().stroke(theme.amberTintFill, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(task?.progress ?? 0, 0.02))
                        .stroke(theme.accentAmber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: task?.status == .paused ? "arrow.down" : "stop.fill")
                        .font(.system(size: task?.status == .paused ? 10 : 7, weight: .bold))
                        .foregroundStyle(theme.accentAmber)
                }
                .frame(width: 22, height: 22)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task?.status == .paused ? L10n.tr("继续") : L10n.tr("暂停"))
        case .completed:
            iconButton("arrow.up.forward.square", help: L10n.tr("在 Finder 中显示"), action: onReveal)
            MacSleepingCatWatchedPill()
        case .failed:
            iconButton("arrow.clockwise", tint: theme.dangerRed, help: L10n.tr("重试"), action: onDownloadAction)
        case nil:
            Button(action: onDownloadAction) {
                Image("MacDownloadsTray")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(theme.surfacePill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("下载"))
        }
    }

    private func iconButton(
        _ systemName: String,
        tint: Color? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint ?? theme.secondaryText)
                .frame(width: 28, height: 28)
                .background(theme.surfacePill, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var showsResumeBar: Bool {
        task == nil && !item.isWatched && item.lastPlaybackPosition > 0 && item.duration > 0
    }

    private var meta: (text: String, color: Color)? {
        if let task {
            let percent = Int((task.progress * 100).rounded())
            switch task.status {
            case .queued: return (L10n.tr("等待下载"), theme.secondaryText)
            case .downloading: return (L10n.tr("下载中 %d%%", percent), theme.accentAmber)
            case .paused: return (L10n.tr("已暂停 %d%%", percent), theme.secondaryText)
            case .completed: return (L10n.tr("已下载"), theme.successGreen)
            case .failed: return (L10n.tr("下载失败"), theme.dangerRed)
            }
        }
        if showsResumeBar {
            return (
                LocalizedFormat.remainingDuration(position: item.lastPlaybackPosition, total: item.duration),
                theme.accentAmber
            )
        }
        return nil
    }
}
