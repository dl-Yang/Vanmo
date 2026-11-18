import SwiftUI
import SwiftData
import UIKit
import VanmoCore

/// 「打开 URL 链接」：粘贴 http(s) 直链串流或下载。对齐 Figma `10 · Sheet — Open Direct Link` (`690:906`)。
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
        ZStack(alignment: .top) {
            CatDesign.surfaceSheet.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                content
            }
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(CatDesign.surfaceSheet)
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

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule()
                .fill(CatDesign.grabberFill)
                .frame(width: 44, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 14)

            HStack {
                HStack(spacing: 10) {
                    Text(L10n.tr("打开直链"))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)

                    Image("CatTailFlourish")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 14)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CatDesign.textMuted)
                        .frame(width: 28, height: 28)
                        .background(CatDesign.surfacePill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("关闭"))
            }

            Text(L10n.tr("支持 MP4、MKV、MOV 与 HLS 流媒体 · HTTPS"))
                .font(.system(size: 12))
                .foregroundStyle(CatDesign.textMuted)
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.bottom, 16)
    }

    private var content: some View {
        List {
            urlInputBar
                .directLinkListRow(top: 0, bottom: 12)

            if let error = model.inputError {
                DirectLinkFieldMessage(text: error)
                    .directLinkListRow(top: 0, bottom: 8)
            }

            primaryActionsRow
                .directLinkListRow(top: 0, bottom: 18)

            if model.entries.isEmpty {
                DirectLinkEmptyHint()
                    .directLinkListRow(top: 12, bottom: 12)
            } else {
                Section {
                    ForEach(model.entries) { item in
                        DirectLinkRow(
                            item: item,
                            task: DirectLinkLibrary.downloadTask(for: item.fileURL, in: downloadManager.tasks),
                            onPlay: {
                                dismiss()
                                appState.play(item)
                            },
                            onDownloadAction: { task in Task { await handleDownloadAction(for: item, task: task) } }
                        )
                        .directLinkListRow(top: 4, bottom: 4)
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
                .directLinkListRow(top: 14, bottom: 28)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var urlInputBar: some View {
        HStack(spacing: 10) {
            Image("CatWhiskerLink")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 18)

            TextField(
                "",
                text: $model.input,
                prompt: Text(verbatim: "https://cdn.cinema.io/video.mkv").foregroundStyle(CatDesign.textDim)
            )
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(CatDesign.textIvory)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($isFieldFocused)
            .onSubmit(playInput)
            .accessibilityLabel(L10n.tr("视频链接"))
            .accessibilityIdentifier("directLink.field")

            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in model.input = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .tint(hasClipboardLink ? CatDesign.accentAmber : CatDesign.textMuted)
            .accessibilityIdentifier("directLink.paste")
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .frame(height: 48)
        .catGlassCard(cornerRadius: 16, elevated: true, amberStroke: model.inputError == nil)
        .overlay {
            if model.inputError != nil {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(CatDesign.dangerRed, lineWidth: 1.4)
            }
        }
    }

    private var isInputEmpty: Bool {
        model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryActionsRow: some View {
        HStack(spacing: 10) {
            Button(action: playInput) {
                HStack(spacing: 8) {
                    Image("CatPlaySmall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    Text(L10n.tr("立即串流"))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(CatDesign.accentAmber)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(CatDesign.amberTintStrong, in: Capsule())
                .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 1))
            }
            .accessibilityIdentifier("directLink.play")

            Button(action: downloadInput) {
                HStack(spacing: 8) {
                    Image("CatDownloadFeline")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)

                    Text(L10n.tr("加入下载队列"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .catGlassCard(cornerRadius: CatDesign.radiusPill)
            }
            .accessibilityIdentifier("directLink.download")
        }
        .buttonStyle(.plain)
        .disabled(isInputEmpty)
        .opacity(isInputEmpty ? 0.45 : 1)
        .animation(.easeOut(duration: 0.2), value: isInputEmpty)
    }

    private var recentHeader: some View {
        HStack {
            Text(L10n.tr("最近链接 · %d", model.entries.count))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(CatDesign.textMuted)
            Spacer()
            CatStretchingDivider()
        }
        .padding(.top, 6)
        .padding(.bottom, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
        .background(CatDesign.surfaceSheet)
    }

    @ViewBuilder
    private func rowMenu(for item: MediaItem) -> some View {
        Button {
            dismiss()
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
        dismiss()
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

private struct DirectLinkFieldMessage: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12.5, weight: .semibold))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(CatDesign.dangerRed)
        .padding(.leading, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 列表行 (`Row / Recent Direct Link`)

private struct DirectLinkRow: View {
    let item: MediaItem
    let task: DownloadTaskSnapshot?
    let onPlay: () -> Void
    let onDownloadAction: (DownloadTaskSnapshot?) -> Void

    private var showsResumeBar: Bool {
        task == nil && !item.isWatched && item.lastPlaybackPosition > 0 && item.duration > 0
    }

    private var metaLine: String {
        let format = DirectLinkLibrary.formatLabel(for: item.fileURL)
        let host = item.fileURL.host ?? ""
        if DirectLinkLibrary.isStreamOnly(item.fileURL) {
            return "\(format) · \(L10n.tr("仅串流")) · \(host)"
        }
        if let task {
            let percent = Int((task.progress * 100).rounded())
            switch task.status {
            case .queued: return "\(format) · \(host) · \(L10n.tr("等待下载"))"
            case .downloading: return "\(format) · \(host) · \(L10n.tr("下载中 %d%%", percent))"
            case .paused: return "\(format) · \(host) · \(L10n.tr("已暂停 %d%%", percent))"
            case .completed: return "\(format) · \(host) · \(L10n.tr("已下载"))"
            case .failed: return "\(format) · \(host) · \(L10n.tr("下载失败"))"
            }
        }
        return "\(format) · \(host)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(metaLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(task?.status == .failed ? CatDesign.dangerRed : CatDesign.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                DirectLinkDownloadControl(
                    isStreamOnly: DirectLinkLibrary.isStreamOnly(item.fileURL),
                    task: task,
                    action: { onDownloadAction(task) }
                )

                Button(action: onPlay) {
                    Image("CatPlaySmall")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: 30, height: 30)
                        .background(CatDesign.surfacePill, in: Circle())
                        .overlay(
                            Circle().strokeBorder(
                                showsResumeBar ? CatDesign.strokeAmber : CatDesign.strokeGlass,
                                lineWidth: 0.85
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("播放"))
            }

            if showsResumeBar {
                HStack(spacing: 10) {
                    CatPawProgressBar(progress: item.playbackProgress)

                    Text(LocalizedFormat.remainingDuration(position: item.lastPlaybackPosition, total: item.duration))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(CatDesign.accentAmber)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .catGlassCard(cornerRadius: 16)
    }
}

private struct DirectLinkDownloadControl: View {
    let isStreamOnly: Bool
    let task: DownloadTaskSnapshot?
    let action: () -> Void

    var body: some View {
        if isStreamOnly {
            EmptyView()
        } else if task?.status == .completed {
            Image("CatEarCheck")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .frame(width: 30, height: 30)
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
                    .stroke(CatDesign.accentAmber.opacity(0.20), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(task?.progress ?? 0, 0.05))
                    .stroke(CatDesign.accentAmber, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: task?.status == .paused ? "arrow.down" : "stop.fill")
                    .font(.system(size: task?.status == .paused ? 11 : 8, weight: .bold))
                    .foregroundStyle(CatDesign.accentAmber)
            }
            .frame(width: 28, height: 28)
        case .failed:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CatDesign.dangerRed)
                .frame(width: 30, height: 30)
                .background(CatDesign.dangerRed.opacity(0.14), in: Circle())
        default:
            Image("CatDownloadFeline")
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
                .frame(width: 30, height: 30)
                .background(CatDesign.surfacePill, in: Circle())
                .overlay(Circle().strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75))
        }
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

private struct DirectLinkEmptyHint: View {
    var body: some View {
        VStack(spacing: 10) {
            Image("CatSittingInFolderBox")
                .resizable()
                .scaledToFit()
                .frame(width: 78, height: 60)
            Text(L10n.tr("还没有链接"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
            Text(L10n.tr("播放或下载过的链接会出现在这里，并保留续播进度。"))
                .font(.system(size: 12))
                .foregroundStyle(CatDesign.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .catGlassCard(cornerRadius: 18)
    }
}

private struct DirectLinkFootnote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CatDesign.textDim)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text(L10n.tr("链接只保存在本机。需要账号密码的地址请改用 WebDAV 连接。"))
                .font(.system(size: 11.5))
                .foregroundStyle(CatDesign.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }
}

private extension View {
    func directLinkListRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 24, bottom: bottom, trailing: 24))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

#Preview {
    DirectLinkView()
        .environmentObject(AppState())
        .environmentObject(DownloadManager.shared)
        .modelContainer(for: MediaItem.self, inMemory: true)
        .preferredColorScheme(.dark)
}
