import SwiftUI
import SwiftData
import UIKit
import VanmoCore

/// 「打开 URL 链接」：粘贴 http(s) 直链串流或下载。对齐 Figma `File` 页 `DirectLink-Light` / `-Dark` / `-States`。
struct DirectLinkView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var downloadManager: DownloadManager
    @StateObject private var model = DirectLinkListModel()
    @State private var hasClipboardLink = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            FilesHeader(title: L10n.tr("打开 URL 链接"), onBack: { dismiss() }) { EmptyView() }
            content
        }
        .background(FilesDesign.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            model.configure(modelContext: modelContext)
            refreshClipboardState()
        }
        .onChange(of: appState.isPlayerPresented) { _, isPresented in
            if !isPresented { model.reload() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshClipboardState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            refreshClipboardState()
        }
        .alert(L10n.tr("错误"), isPresented: alertBinding) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var content: some View {
        List {
            DirectLinkInputCard(
                model: model,
                hasClipboardLink: hasClipboardLink,
                isFieldFocused: $isFieldFocused,
                onPlay: playInput,
                onDownload: downloadInput
            )
            .directLinkListRow(top: 16, bottom: 12)

            if model.entries.isEmpty {
                DirectLinkEmptyHint()
                    .directLinkListRow(top: 12, bottom: 12)
            } else {
                Section {
                    ForEach(model.entries) { item in
                        DirectLinkRow(
                            item: item,
                            task: DirectLinkLibrary.downloadTask(for: item.fileURL, in: downloadManager.tasks),
                            onPlay: { appState.play(item) },
                            onDownloadAction: { task in Task { await handleDownloadAction(for: item, task: task) } }
                        )
                        .directLinkListRow(top: 2, bottom: 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                model.remove(item)
                            } label: {
                                Label(L10n.tr("移除"), systemImage: "trash")
                            }
                        }
                        .contextMenu { rowMenu(for: item) }
                    }
                } header: {
                    recentHeader
                }
            }

            DirectLinkFootnote()
                .directLinkListRow(top: 16, bottom: 24)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var recentHeader: some View {
        HStack {
            FilesSectionHeader(title: L10n.tr("最近链接"))
            Spacer()
            Text("\(model.entries.count)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FilesDesign.connectionDot)
                .padding(.horizontal, 8)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .background(FilesDesign.background)
    }

    @ViewBuilder
    private func rowMenu(for item: MediaItem) -> some View {
        Button {
            appState.play(item)
        } label: {
            Label(L10n.tr("播放"), systemImage: "play")
        }
        if !DirectLinkLibrary.isStreamOnly(item.fileURL),
           DirectLinkLibrary.downloadTask(for: item.fileURL, in: downloadManager.tasks) == nil {
            Button {
                Task { await model.download(item, using: downloadManager) }
            } label: {
                Label(L10n.tr("下载"), systemImage: "arrow.down.to.line")
            }
        }
        Button {
            UIPasteboard.general.url = item.fileURL
        } label: {
            Label(L10n.tr("拷贝链接"), systemImage: "doc.on.doc")
        }
        Button(role: .destructive) {
            model.remove(item)
        } label: {
            Label(L10n.tr("移除"), systemImage: "trash")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private func playInput() {
        guard let item = model.addInput() else { return }
        isFieldFocused = false
        appState.play(item)
    }

    private func downloadInput() {
        isFieldFocused = false
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

    /// `hasURLs` 与模式探测都不读取内容，不会触发系统粘贴提示。
    private func refreshClipboardState() {
        Task { @MainActor in
            let pasteboard = UIPasteboard.general
            if pasteboard.hasURLs {
                hasClipboardLink = true
                return
            }
            let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL])
            hasClipboardLink = patterns?.contains(\.probableWebURL) == true
        }
    }
}

// MARK: - 设计 Token

enum DirectLinkDesign {
    static let card          = FilesDesign.dyn("#FFFFFF", "#18181B")
    static let cardBorder    = FilesDesign.dyn("#E4E4E7", "#27272A")
    static let field         = FilesDesign.dyn("#F4F4F5", "#27272A")
    static let fieldBorder   = FilesDesign.dyn("#E4E4E7", "#3F3F47")
    static let placeholder   = FilesDesign.dyn("#9F9FA9", "#71717B")
    static let error         = FilesDesign.dyn("#E7000B", "#FF6467")
    static let formatBox     = Color.vanmoAccent.opacity(0.08)
    static let tintedFill    = Color.vanmoAccent.opacity(0.12)
    static let streamOnlyFill = FilesDesign.dyn("#E4E4E7", "#27272A")
}

// MARK: - 链接输入卡

private struct DirectLinkInputCard: View {
    @ObservedObject var model: DirectLinkListModel
    let hasClipboardLink: Bool
    var isFieldFocused: FocusState<Bool>.Binding
    let onPlay: () -> Void
    let onDownload: () -> Void

    private var isInputEmpty: Bool {
        model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            intro
            field
            if let error = model.inputError {
                DirectLinkFieldMessage(text: error)
            }
            actions
        }
        .padding(16)
        .background(DirectLinkDesign.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DirectLinkDesign.cardBorder, lineWidth: 1)
        }
    }

    private var intro: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FilesDesign.accent)
                .frame(width: 40, height: 40)
                .background(DirectLinkDesign.tintedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tr("串流或保存视频链接"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FilesDesign.title)
                Text(L10n.tr("支持 MP4、MKV、MOV、HLS 等格式"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FilesDesign.subtitle)
            }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField(
                "",
                text: $model.input,
                prompt: Text(verbatim: "https://").foregroundStyle(DirectLinkDesign.placeholder)
            )
            .font(.system(size: 15))
            .foregroundStyle(FilesDesign.title)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused(isFieldFocused)
            .onSubmit(onPlay)
            .accessibilityLabel(L10n.tr("视频链接"))
            .accessibilityIdentifier("directLink.field")

            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in model.input = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.small)
            .tint(hasClipboardLink ? FilesDesign.accent : FilesDesign.secondaryIcon)
            .accessibilityIdentifier("directLink.paste")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(DirectLinkDesign.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    model.inputError == nil ? DirectLinkDesign.fieldBorder : DirectLinkDesign.error,
                    lineWidth: model.inputError == nil ? 1 : 1.5
                )
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                Label(L10n.tr("播放"), systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(FilesDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("directLink.play")
            Button(action: onDownload) {
                Label(L10n.tr("下载"), systemImage: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FilesDesign.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(DirectLinkDesign.tintedFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityIdentifier("directLink.download")
        }
        .buttonStyle(.plain)
        .disabled(isInputEmpty)
        .opacity(isInputEmpty ? 0.5 : 1)
        .animation(.easeOut(duration: 0.2), value: isInputEmpty)
    }
}

private struct DirectLinkFieldMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DirectLinkDesign.error)
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 列表行

private struct DirectLinkRow: View {
    let item: MediaItem
    let task: DownloadTaskSnapshot?
    let onPlay: () -> Void
    let onDownloadAction: (DownloadTaskSnapshot?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPlay) {
                HStack(spacing: 0) {
                    FilesIconBox(background: DirectLinkDesign.formatBox) {
                        Text(DirectLinkLibrary.formatLabel(for: item.fileURL))
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(FilesDesign.accent)
                    }
                    textColumn
                    Spacer(minLength: 8)
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.tr("播放"))

            DirectLinkDownloadControl(
                isStreamOnly: DirectLinkLibrary.isStreamOnly(item.fileURL),
                task: task,
                action: { onDownloadAction(task) }
            )
            .padding(.trailing, 12)
        }
    }

    private var textColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilesDesign.title)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 6) {
                Text(item.fileURL.host ?? "")
                    .foregroundStyle(FilesDesign.subtitle)
                    .lineLimit(1)
                if let meta {
                    Circle()
                        .fill(FilesDesign.videoDot)
                        .frame(width: 4, height: 4)
                    Text(meta.text)
                        .foregroundStyle(meta.color)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.top, 2)
            if showsResumeBar {
                ResumeBar(fraction: item.playbackProgress)
                    .padding(.top, 6)
            }
        }
        .padding(.leading, 16)
    }

    private var showsResumeBar: Bool {
        task == nil && !item.isWatched && item.lastPlaybackPosition > 0 && item.duration > 0
    }

    private var meta: (text: String, color: Color)? {
        if let task {
            let percent = Int((task.progress * 100).rounded())
            switch task.status {
            case .queued:
                return (L10n.tr("等待下载"), FilesDesign.subtitle)
            case .downloading:
                return (L10n.tr("下载中 %d%%", percent), FilesDesign.accent)
            case .paused:
                return (L10n.tr("已暂停 %d%%", percent), FilesDesign.subtitle)
            case .completed:
                return (L10n.tr("已下载"), FilesDesign.statusConnected)
            case .failed:
                return (L10n.tr("下载失败"), DirectLinkDesign.error)
            }
        }
        if showsResumeBar {
            return (
                LocalizedFormat.remainingDuration(position: item.lastPlaybackPosition, total: item.duration),
                FilesDesign.subtitle
            )
        }
        return nil
    }
}

private struct ResumeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(FilesDesign.iconBoxGray)
                Capsule()
                    .fill(FilesDesign.accent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

private struct DirectLinkDownloadControl: View {
    let isStreamOnly: Bool
    let task: DownloadTaskSnapshot?
    let action: () -> Void

    var body: some View {
        if isStreamOnly {
            Text(L10n.tr("仅串流"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FilesDesign.secondaryIcon)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(DirectLinkDesign.streamOnlyFill, in: Capsule())
        } else if task?.status == .completed {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(FilesDesign.statusConnected)
                .frame(width: 36, height: 36)
                .background(FilesDesign.statusConnected.opacity(0.12), in: Circle())
                .accessibilityLabel(L10n.tr("已下载"))
        } else {
            Button(action: action) { glyph }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel)
        }
    }

    @ViewBuilder
    private var glyph: some View {
        switch task?.status {
        case .queued, .downloading, .paused:
            ZStack {
                Circle()
                    .stroke(FilesDesign.accent.opacity(0.16), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(task?.progress ?? 0, 0.02))
                    .stroke(FilesDesign.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: task?.progress)
                Image(systemName: task?.status == .paused ? "arrow.down" : "stop.fill")
                    .font(.system(size: task?.status == .paused ? 13 : 9, weight: .bold))
                    .foregroundStyle(FilesDesign.accent)
            }
            .frame(width: 30, height: 30)
            .frame(width: 36, height: 36)
        case .failed:
            circleGlyph("arrow.clockwise", tint: DirectLinkDesign.error, fill: DirectLinkDesign.error.opacity(0.1))
        default:
            circleGlyph("arrow.down.to.line", tint: FilesDesign.accent, fill: DirectLinkDesign.tintedFill)
        }
    }

    private func circleGlyph(_ name: String, tint: Color, fill: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(fill, in: Circle())
    }

    private var accessibilityLabel: String {
        switch task?.status {
        case .queued, .downloading: return L10n.tr("暂停")
        case .paused: return L10n.tr("继续")
        case .failed: return L10n.tr("重试")
        default: return L10n.tr("下载")
        }
    }
}

// MARK: - 空态 / 脚注

private struct DirectLinkEmptyHint: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "link")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(FilesDesign.secondaryIcon)
                .frame(width: 48, height: 48)
                .background(FilesDesign.iconBoxGray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(L10n.tr("还没有链接"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilesDesign.title)
            Text(L10n.tr("播放或下载过的链接会出现在这里，并保留续播进度。"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FilesDesign.subtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct DirectLinkFootnote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FilesDesign.connectionDot)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(L10n.tr("链接只保存在本机。需要账号密码的地址请改用 WebDAV 连接。"))
                .font(.system(size: 12))
                .foregroundStyle(FilesDesign.subtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
    }
}

private extension View {
    func directLinkListRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#Preview {
    NavigationStack {
        DirectLinkView()
    }
    .environmentObject(AppState())
    .environmentObject(DownloadManager.shared)
    .modelContainer(for: MediaItem.self, inMemory: true)
}
