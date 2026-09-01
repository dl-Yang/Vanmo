import SwiftUI
import VanmoCore

struct MacConnectionsBrowseView: View {
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.macTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            breadcrumbBar
            Divider()
            browserContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appBackground)
        .overlay {
            if connectionsViewModel.isLoading && !connectionsViewModel.scanCoordinator.isActive {
                loadingOverlay
            }
        }
        .overlay(alignment: .bottom) {
            MacScanSyncBanner(
                coordinator: connectionsViewModel.scanCoordinator,
                onPause: { connectionsViewModel.pauseScan() },
                onResume: { connectionsViewModel.resumeScan() },
                onCancel: { connectionsViewModel.cancelScan() }
            )
        }
        .alert(L10n.tr("同步"), isPresented: Binding(
            get: { connectionsViewModel.scanToastMessage != nil },
            set: { if !$0 { connectionsViewModel.scanToastMessage = nil } }
        )) {
            Button(L10n.tr("确定")) { connectionsViewModel.scanToastMessage = nil }
        } message: {
            Text(connectionsViewModel.scanToastMessage ?? "")
        }
        .alert(L10n.tr("错误"), isPresented: $connectionsViewModel.showError) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(connectionsViewModel.errorMessage)
        }
        .task {
            await openPendingFolderBookmarkIfNeeded()
        }
        .onChange(of: connectionsViewModel.pendingFolderBookmarkNavigation?.id) { _, _ in
            Task { await openPendingFolderBookmarkIfNeeded() }
        }
        .contextMenu {
            connectionContextMenu
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            if let connection = connectionsViewModel.selectedConnection {
                MacConnectionProviderIcon(type: connection.type, size: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(MacDesignTokens.Typography.headerTitle)
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    Text(connectionStatusText(for: connection))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
            } else {
                Text(L10n.tr("连接浏览"))
                    .font(MacDesignTokens.Typography.headerTitle)
                    .foregroundStyle(theme.primaryText)
            }

            Spacer(minLength: 0)

            if connectionsViewModel.selectedConnection != nil {
                Button {
                    Task { await connectionsViewModel.refreshCurrentDirectory() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("刷新当前目录"))

                Button {
                    Task { await connectionsViewModel.scanCurrentDirectory() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("同步当前目录到媒体库"))

                Menu {
                    connectionContextMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .help(L10n.tr("更多操作"))
            }
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .frame(height: MacDesignTokens.Layout.headerHeight)
        .background(theme.headerBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.headerBorder)
                .frame(height: 1)
        }
        .contextMenu {
            connectionContextMenu
        }
    }

    @ViewBuilder
    private var connectionContextMenu: some View {
        if let connection = connectionsViewModel.selectedConnection {
            Button {
                Task { await connectionsViewModel.refreshCurrentDirectory() }
            } label: {
                Label(L10n.tr("刷新"), systemImage: "arrow.clockwise")
            }
            Button {
                Task { await connectionsViewModel.scanCurrentDirectory() }
            } label: {
                Label(L10n.tr("同步当前目录"), systemImage: "square.and.arrow.down")
            }
            Button {
                appState.presentEditConnection(connection)
            } label: {
                Label(L10n.tr("编辑"), systemImage: "pencil")
            }
            if !connection.type.requiresManualDirectorySync {
                Button {
                    Task { await fullRescanConnection(connection) }
                } label: {
                    Label(L10n.tr("全量重扫"), systemImage: "arrow.clockwise")
                }
            } else {
                Button {
                    Task { await connectionsViewModel.scanCurrentDirectory(forceFullScan: true) }
                } label: {
                    Label(L10n.tr("全量重扫当前目录"), systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                deleteConnection(connection)
            } label: {
                Label(L10n.tr("删除"), systemImage: "trash")
            }
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(breadcrumbItems.enumerated()), id: \.offset) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                    }

                    Button {
                        Task { await connectionsViewModel.navigateToDirectory(item.path) }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: index == breadcrumbItems.count - 1 ? .semibold : .medium))
                            .foregroundStyle(
                                index == breadcrumbItems.count - 1 ? theme.primaryText : theme.secondaryText
                            )
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == breadcrumbItems.count - 1)
                }
            }
            .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
            .padding(.vertical, 10)
        }
        .background(theme.appBackground)
    }

    // MARK: - Content

    @ViewBuilder
    private var browserContent: some View {
        if connectionsViewModel.selectedConnection == nil {
            emptySelectionState
        } else if connectionsViewModel.isBrowsingFiles {
            loadingState
        } else if let message = connectionsViewModel.fileBrowserErrorMessage {
            messageState(icon: "exclamationmark.triangle", title: L10n.tr("无法加载目录"), message: message)
        } else if connectionsViewModel.files.isEmpty {
            messageState(icon: "folder", title: L10n.tr("文件夹为空"), message: L10n.tr("此目录下没有可显示的文件"))
        } else {
            fileList
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(connectionsViewModel.files) { file in
                    fileRow(file)
                }
            }
            .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
            .padding(.vertical, 12)
        }
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        Button {
            Task { await handleFileTap(file) }
        } label: {
            MacConnectionFileRow(file: file)
        }
        .buttonStyle(MacConnectionFileRowButtonStyle(theme: theme))
        .contextMenu {
            fileContextMenu(for: file)
        }
    }

    @ViewBuilder
    private func fileContextMenu(for file: RemoteFile) -> some View {
        if file.isDirectory {
            Button {
                Task { await connectionsViewModel.openDirectory(file) }
            } label: {
                Label(L10n.tr("打开"), systemImage: "folder")
            }

            if connectionsViewModel.canBookmarkFoldersInSelectedConnection {
                Button {
                    toggleFolderBookmark(file)
                } label: {
                    if connectionsViewModel.isFolderBookmarked(file) {
                        Label(L10n.tr("取消书签"), systemImage: "bookmark.slash")
                    } else {
                        Label(L10n.tr("添加书签"), systemImage: "bookmark")
                    }
                }
            }
        }

        if file.isVideo {
            Button {
                Task { await play(file) }
            } label: {
                Label(L10n.tr("播放"), systemImage: "play.fill")
            }

            if let connection = connectionsViewModel.selectedConnection,
               DownloadEligibility.isEligible(file: file, connectionType: connection.type) {
                Button {
                    Task { await download(file, connection: connection) }
                } label: {
                    Label(L10n.tr("下载"), systemImage: "arrow.down.circle")
                }
            }

            if connectionsViewModel.selectedConnection?.type == .localFolder {
                Button {
                    Task { await quickLook(file) }
                } label: {
                    Label(L10n.tr("Quick Look 预览"), systemImage: "eye")
                }
            }
        }

        if let connection = connectionsViewModel.selectedConnection {
            Divider()
            Button {
                appState.presentEditConnection(connection)
            } label: {
                Label(L10n.tr("编辑"), systemImage: "pencil")
            }
            if connection.type.requiresManualDirectorySync {
                Button {
                    Task { await connectionsViewModel.scanCurrentDirectory(forceFullScan: true) }
                } label: {
                    Label(L10n.tr("全量重扫当前目录"), systemImage: "arrow.clockwise")
                }
            } else {
                Button {
                    Task { await fullRescanConnection(connection) }
                } label: {
                    Label(L10n.tr("全量重扫"), systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                deleteConnection(connection)
            } label: {
                Label(L10n.tr("删除"), systemImage: "trash")
            }
        }
    }

    private var emptySelectionState: some View {
        messageState(
            icon: "externaldrive",
            title: L10n.tr("未选择连接"),
            message: L10n.tr("请从侧边栏选择一个连接以浏览文件")
        )
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text(L10n.tr("正在加载目录..."))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.tertiaryText)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(connectionsViewModel.loadingMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private var breadcrumbItems: [(title: String, path: String)] {
        guard let connection = connectionsViewModel.selectedConnection else { return [] }

        var items: [(title: String, path: String)] = [(connection.name, "/")]
        let currentPath = connectionsViewModel.currentPath
        guard currentPath != "/" else { return items }

        var builtPath = ""
        let components = currentPath.split(separator: "/").map(String.init)
        for component in components {
            builtPath = builtPath.isEmpty ? "/\(component)" : (builtPath as NSString).appendingPathComponent(component)
            let title = component.isEmpty ? connection.name : component
            items.append((title, builtPath))
        }
        return items
    }

    private func connectionStatusText(for connection: SavedConnection) -> String {
        switch connectionsViewModel.connectionStatus(for: connection) {
        case .idle:
            return L10n.tr("未连接")
        case .connecting:
            return L10n.tr("连接中")
        case .connected:
            return L10n.tr("已连接")
        case .failed:
            return connectionsViewModel.connectionErrorMessage(for: connection) ?? L10n.tr("连接失败")
        }
    }

    private func openPendingFolderBookmarkIfNeeded() async {
        guard let request = connectionsViewModel.pendingFolderBookmarkNavigation else { return }
        _ = await connectionsViewModel.openFolderBookmarkRequest(request)
    }

    private func toggleFolderBookmark(_ file: RemoteFile) {
        connectionsViewModel.toggleFolderBookmark(file)
        libraryViewModel.refreshFolderBookmarks(connections: connectionsViewModel.savedConnections)
    }

    private func handleFileTap(_ file: RemoteFile) async {
        if file.isDirectory {
            await connectionsViewModel.openDirectory(file)
        } else if file.isVideo {
            await play(file)
        }
    }

    private func play(_ file: RemoteFile) async {
        await connectionsViewModel.play(file, via: appState)
    }

    private func download(_ file: RemoteFile, connection: SavedConnection) async {
        do {
            let request = try DownloadRequestFactory.make(
                from: file,
                connectionId: connection.id,
                connectionType: connection.type
            )
            try await downloadManager.enqueue(request)
#if DEBUG
            print("[Debug][Downloads] enqueued source=browser connection=\(connection.type.rawValue)")
#endif
        } catch {
#if DEBUG
            let nsError = error as NSError
            print("[Debug][Downloads] enqueue failed source=browser domain=\(nsError.domain) code=\(nsError.code)")
#endif
            connectionsViewModel.errorMessage = error.localizedDescription
            connectionsViewModel.showError = true
        }
    }

    private func quickLook(_ file: RemoteFile) async {
        guard let url = await connectionsViewModel.previewURL(for: file) else { return }
        MacQuickLookPresenter.preview(url)
    }

    private func fullRescanConnection(_ connection: SavedConnection) async {
        if connection.type.requiresManualDirectorySync {
            _ = await connectionsViewModel.scanCurrentDirectory(forceFullScan: true)
        } else {
            _ = await connectionsViewModel.connectAndScan(connection, forceFullScan: true)
        }
        if connectionsViewModel.selectedConnectionID == connection.id {
            await connectionsViewModel.refreshCurrentDirectory()
        }
    }

    private func deleteConnection(_ connection: SavedConnection) {
        MacConnectionDeletion.delete(
            connection,
            appState: appState,
            libraryViewModel: libraryViewModel,
            connectionsViewModel: connectionsViewModel,
            searchViewModel: searchViewModel
        )
    }
}

// MARK: - File Row

private struct MacConnectionFileRow: View {
    @Environment(\.macTheme) private var theme

    let file: RemoteFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(file.isDirectory ? MacDesignTokens.accentBlue : theme.secondaryText)
                .frame(width: 36, height: 36)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: file.isDirectory ? 15 : 14, weight: file.isDirectory ? .semibold : .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            } else if file.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MacDesignTokens.accentBlue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconName: String {
        if file.isDirectory {
            return "folder.fill"
        }
        if file.isVideo {
            return "film"
        }
        return "doc"
    }

    private var iconBackground: Color {
        file.isDirectory ? MacDesignTokens.accentBlue.opacity(0.12) : theme.secondaryButtonBackground
    }

    private var subtitle: String {
        if file.isDirectory {
            return L10n.tr("文件夹")
        }
        if file.size > 0 {
            return MacBrowseFormatters.fileSize(file.size)
        }
        return file.type.macBrowseDisplayName
    }
}

private struct MacConnectionFileRowButtonStyle: ButtonStyle {
    let theme: MacThemeColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? theme.secondaryButtonBackground : Color.clear)
            )
    }
}

private enum MacBrowseFormatters {
    static func fileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = false
        let result = formatter.string(fromByteCount: bytes)
        if result.hasPrefix("Zero") {
            return result.replacingOccurrences(of: "Zero", with: "0")
        }
        return result
    }
}

private extension RemoteFileType {
    var macBrowseDisplayName: String {
        switch self {
        case .video: L10n.tr("视频")
        case .subtitle: L10n.tr("字幕")
        case .audio: L10n.tr("音频")
        case .image: L10n.tr("图片")
        case .directory: L10n.tr("文件夹")
        case .other: L10n.tr("文件")
        }
    }
}

#Preview("Browse Light") {
    MacConnectionsBrowseView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .macTheme(.light)
        .frame(width: 960, height: 640)
}
