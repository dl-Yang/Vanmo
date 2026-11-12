import AppKit
import SwiftData
import SwiftUI
import VanmoCore

/// macOS「打开 URL 链接」主内容区。对齐 Figma `Files` 页 `DirectLink-Light` / `-Dark` / `-States`。
struct MacDirectLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macTheme) private var theme
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @StateObject private var model = DirectLinkListModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    inputSection
                    recentSection
                }
                .padding(.bottom, 24)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.tr("打开 URL 链接"))
                .font(MacDesignTokens.Typography.headerTitle)
                .foregroundStyle(theme.primaryText)
            Text(L10n.tr("串流或下载 http(s) 直链视频"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .frame(height: MacDesignTokens.Layout.headerHeight)
        .background(theme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.primaryText.opacity(0.1))
                .frame(height: 1)
        }
    }

    // MARK: - 输入

    private var isInputEmpty: Bool {
        model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                urlField
                Button(action: playInput) {
                    Label(L10n.tr("播放"), systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(MacDesignTokens.accentBlue, in: RoundedRectangle(cornerRadius: 8))
                }
                Button(action: downloadInput) {
                    Label(L10n.tr("下载"), systemImage: "arrow.down.to.line")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(theme.secondaryButtonBackground, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .buttonStyle(.plain)

            if let error = model.inputError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemRed))
            }

            Text(L10n.tr("支持 MP4、MKV、MOV、HLS 等格式。链接只保存在本机；需要账号密码的地址请改用 WebDAV 连接。"))
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 20)
    }

    private var urlField: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
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
            .buttonBorderShape(.roundedRectangle(radius: 6))
            .controlSize(.small)
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 36)
        .background(theme.searchBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(fieldStroke, lineWidth: isFieldFocused || model.inputError != nil ? 2 : 0)
        }
    }

    private var fieldStroke: Color {
        model.inputError == nil ? MacDesignTokens.accentBlue : Color(nsColor: .systemRed)
    }

    // MARK: - 最近链接

    @ViewBuilder
    private var recentSection: some View {
        if model.entries.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L10n.tr("最近链接"))
                    Spacer()
                    Text("\(model.entries.count)")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.sectionHeader)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

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
            .padding(.horizontal, 12)
            .padding(.top, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 44, height: 44)
                .background(theme.emptyIconBackground, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).stroke(theme.emptyIconBorder, lineWidth: 1)
                }
            Text(L10n.tr("还没有链接"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(L10n.tr("播放或下载过的链接会出现在这里，并保留续播进度。"))
                .font(.system(size: 12))
                .foregroundStyle(theme.emptyDescriptionText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
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

// MARK: - 列表行

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
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(MacDesignTokens.accentBlue)
                .frame(width: 40, height: 40)
                .background(MacDesignTokens.accentBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            textColumn
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(isHovered ? theme.primaryText.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2, perform: onPlay)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L10n.tr("播放"), onPlay)
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Text(item.fileURL.host ?? "")
                    .foregroundStyle(theme.tertiaryText)
                if let meta {
                    Circle().fill(theme.sectionHeader).frame(width: 3, height: 3)
                    Text(meta.text).foregroundStyle(meta.color)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            if showsResumeBar {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.progressTrack)
                        Capsule()
                            .fill(MacDesignTokens.accentBlue)
                            .frame(width: proxy.size.width * min(max(item.playbackProgress, 0), 1))
                    }
                }
                .frame(width: 240, height: 3)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 6) {
            if isHovered {
                iconButton("play.fill", help: L10n.tr("播放"), action: onPlay)
            }
            if isStreamOnly {
                Text(L10n.tr("仅串流"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.chipText)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(theme.chipBackground, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip))
                    .overlay {
                        RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip).stroke(theme.chipBorder, lineWidth: 1)
                    }
            } else {
                downloadControl
            }
            if isHovered {
                iconButton("trash", help: L10n.tr("移除"), action: onRemove)
            }
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        switch task?.status {
        case .queued, .downloading, .paused:
            Button(action: onDownloadAction) {
                ZStack {
                    Circle().stroke(MacDesignTokens.accentBlue.opacity(0.18), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(task?.progress ?? 0, 0.02))
                        .stroke(MacDesignTokens.accentBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: task?.status == .paused ? "arrow.down" : "stop.fill")
                        .font(.system(size: task?.status == .paused ? 10 : 7, weight: .bold))
                        .foregroundStyle(MacDesignTokens.accentBlue)
                }
                .frame(width: 22, height: 22)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(task?.status == .paused ? L10n.tr("继续") : L10n.tr("暂停"))
        case .completed:
            iconButton("arrow.up.forward.square", help: L10n.tr("在 Finder 中显示"), action: onReveal)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .frame(width: 28, height: 28)
                .background(Color(nsColor: .systemGreen).opacity(0.14), in: Circle())
                .accessibilityLabel(L10n.tr("已下载"))
        case .failed:
            iconButton("arrow.clockwise", help: L10n.tr("重试"), tint: Color(nsColor: .systemRed), action: onDownloadAction)
        case nil:
            iconButton("arrow.down.to.line", help: L10n.tr("下载"), action: onDownloadAction)
        }
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint ?? theme.secondaryText)
                .frame(width: 28, height: 28)
                .background((tint ?? theme.primaryText).opacity(tint == nil ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 6))
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
            case .queued: return (L10n.tr("等待下载"), theme.tertiaryText)
            case .downloading: return (L10n.tr("下载中 %d%%", percent), MacDesignTokens.accentBlue)
            case .paused: return (L10n.tr("已暂停 %d%%", percent), theme.tertiaryText)
            case .completed: return (L10n.tr("已下载"), Color(nsColor: .systemGreen))
            case .failed: return (L10n.tr("下载失败"), Color(nsColor: .systemRed))
            }
        }
        if showsResumeBar {
            return (
                LocalizedFormat.remainingDuration(position: item.lastPlaybackPosition, total: item.duration),
                theme.tertiaryText
            )
        }
        return nil
    }
}
