import SwiftUI
import VanmoCore

struct MacConnectionsBrowseView: View {
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @EnvironmentObject private var downloadManager: DownloadManager
    @Environment(\.macTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("files.browserLayout") private var layoutRaw = MacFilesBrowserLayout.grid.rawValue
    /// 正在打开的文件夹路径：保留旧内容并在该条目上显示打开态，加载完成后再做展开过渡。
    @State private var openingFolderPath: String?
    @State private var isNavigatingDirectory = false
    @State private var folderTransition = MacFolderTransitionState()
    @State private var tileFrames = MacFilesTileFrameStore()
    @State private var contentSize: CGSize = .zero

    private static let contentSpace = "mac.files.browser.content"
    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
        count: 3
    )

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
        .onChange(of: appState.isPlayerPresented) { _, isPresented in
            if !isPresented { connectionsViewModel.refreshLibraryStates() }
        }
        .onChange(of: connectionsViewModel.selectedConnectionID) { _, _ in
            folderTransition = MacFolderTransitionState()
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

                if connectionsViewModel.selectedConnection?.type != .iptv {
                    layoutToggle
                }

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
                        navigateToBreadcrumb(item.path)
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
        } else if connectionsViewModel.isBrowsingFiles && !isNavigatingDirectory {
            loadingState
        } else if let message = connectionsViewModel.fileBrowserErrorMessage {
            messageState(icon: "exclamationmark.triangle", title: L10n.tr("无法加载目录"), message: message)
        } else if connectionsViewModel.files.isEmpty {
            messageState(icon: "folder", title: L10n.tr("文件夹为空"), message: L10n.tr("此目录下没有可显示的文件"))
        } else {
            directoryContainer
        }
    }

    // MARK: - Layout

    private var layout: MacFilesBrowserLayout {
        guard connectionsViewModel.selectedConnection?.type != .iptv else { return .list }
        return MacFilesBrowserLayout(rawValue: layoutRaw) ?? .grid
    }

    /// 图标显示点击后切换到的布局（网格态显示列表图标）。
    private var layoutToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                layoutRaw = (layout == .grid ? MacFilesBrowserLayout.list : .grid).rawValue
            }
        } label: {
            Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(layout == .grid ? L10n.tr("切换为列表") : L10n.tr("切换为网格"))
        .accessibilityLabel(layout == .grid ? L10n.tr("切换为列表") : L10n.tr("切换为网格"))
    }

    /// 以连接 + 目录路径为身份做“文件夹打开”过渡：前进时从被点文件夹处展开，返回时收回到对应位置。
    private var directoryContainer: some View {
        ZStack {
            directoryListing
                .id("\(connectionsViewModel.selectedConnectionID?.uuidString ?? "")|\(connectionsViewModel.currentPath)")
                .transition(MacFolderOpenTransition(
                    anchor: folderTransition.anchor,
                    isForward: folderTransition.isForward,
                    reduceMotion: reduceMotion
                ))
                .zIndex(Double(connectionsViewModel.pathStack.count))
        }
        .coordinateSpace(.named(Self.contentSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.88),
            value: connectionsViewModel.currentPath
        )
    }

    private var directoryListing: some View {
        ScrollView {
            if layout == .grid {
                gridListing
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(connectionsViewModel.files) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
                .padding(.vertical, 12)
            }
        }
    }

    private var gridListing: some View {
        let folders = connectionsViewModel.files.filter(\.isDirectory)
        let items = connectionsViewModel.files.filter { !$0.isDirectory }
        return VStack(alignment: .leading, spacing: 12) {
            if !folders.isEmpty {
                gridSectionHeader(L10n.tr("文件夹"))
                LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                    ForEach(folders) { folder in
                        folderGridTile(folder)
                    }
                }
            }
            if !items.isEmpty {
                gridSectionHeader(items.allSatisfy(\.isVideo) ? L10n.tr("视频") : L10n.tr("文件"))
                    .padding(.top, folders.isEmpty ? 0 : 8)
                LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                    ForEach(items) { file in
                        fileGridCard(file)
                    }
                }
            }
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func gridSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.sectionHeader)
    }

    private func folderGridTile(_ folder: RemoteFile) -> some View {
        Button {
            openFolder(folder)
        } label: {
            MacFolderGridTile(
                name: folder.name,
                isOpening: openingFolderPath == folder.path,
                isLoading: openingFolderPath == folder.path && connectionsViewModel.isBrowsingFiles,
                reduceMotion: reduceMotion
            )
        }
        .buttonStyle(.plain)
        .reportMacTileFrame(path: folder.path, in: Self.contentSpace, store: tileFrames)
        .contextMenu {
            fileContextMenu(for: folder)
        }
    }

    private func fileGridCard(_ file: RemoteFile) -> some View {
        Button {
            Task { await handleFileTap(file) }
        } label: {
            MacVideoGridCard(
                file: file,
                artwork: artworkCandidates(for: file),
                progress: watchProgress(for: file),
                extract: extractedFrameLoader(for: file)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            fileContextMenu(for: file)
        }
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        Button {
            Task { await handleFileTap(file) }
        } label: {
            MacConnectionFileRow(
                file: file,
                isOpening: openingFolderPath == file.path,
                artwork: artworkCandidates(for: file),
                extract: extractedFrameLoader(for: file)
            )
        }
        .buttonStyle(MacConnectionFileRowButtonStyle(theme: theme))
        .reportMacTileFrame(path: file.isDirectory ? file.path : nil, in: Self.contentSpace, store: tileFrames)
        .contextMenu {
            fileContextMenu(for: file)
        }
    }

    private func artworkCandidates(for file: RemoteFile) -> [URL] {
        guard file.isVideo else { return [] }
        return FileCoverResolver.artworkCandidates(for: file, library: connectionsViewModel.libraryStates[file.path])
    }

    private func watchProgress(for file: RemoteFile) -> FileWatchProgress? {
        guard file.isVideo else { return nil }
        return FileCoverResolver.progress(for: file, library: connectionsViewModel.libraryStates[file.path])
    }

    private func extractedFrameLoader(for file: RemoteFile) -> (() async -> URL?)? {
        guard file.isVideo else { return nil }
        let viewModel = connectionsViewModel
        return { await viewModel.thumbnailURL(for: file) }
    }

    @ViewBuilder
    private func fileContextMenu(for file: RemoteFile) -> some View {
        if file.isDirectory {
            Button {
                openFolder(file)
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
            openFolder(file)
        } else if file.isVideo {
            await play(file)
        }
    }

    private func openFolder(_ folder: RemoteFile) {
        guard folder.isDirectory, !isNavigatingDirectory, !connectionsViewModel.isBrowsingFiles else { return }
        let anchor = tileAnchor(for: folder.path)
        folderTransition.anchor = anchor
        folderTransition.isForward = true
        isNavigatingDirectory = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) {
            openingFolderPath = folder.path
        }
        Task {
            let depth = connectionsViewModel.pathStack.count
            await connectionsViewModel.openDirectory(folder)
            if connectionsViewModel.pathStack.count > depth {
                folderTransition.anchorStack.append(anchor)
            }
            openingFolderPath = nil
            isNavigatingDirectory = false
        }
    }

    /// 面包屑只指向祖先目录：按 `pathStack` 中的位置算出后退层数（Emby 等 ID 路径没有可用的路径深度），
    /// 内容收回到进入那一层时记录的锚点。
    private func navigateToBreadcrumb(_ path: String) {
        guard !isNavigatingDirectory else { return }
        let pathStack = connectionsViewModel.pathStack
        let levelsUp = path == "/"
            ? pathStack.count
            : pathStack.lastIndex(of: path).map { pathStack.count - $0 } ?? 0
        let originalStack = folderTransition.anchorStack
        let remaining = max(originalStack.count - levelsUp, 0)
        folderTransition.anchor = levelsUp > 0 && remaining < originalStack.count ? originalStack[remaining] : .center
        folderTransition.isForward = false
        isNavigatingDirectory = true
        Task {
            await connectionsViewModel.navigateToDirectory(path)
            folderTransition.anchorStack = Array(originalStack.prefix(connectionsViewModel.pathStack.count))
            isNavigatingDirectory = false
        }
    }

    private func tileAnchor(for path: String) -> UnitPoint {
        guard let frame = tileFrames.frames[path], contentSize.width > 0, contentSize.height > 0 else {
            return .center
        }
        return UnitPoint(
            x: min(max(frame.midX / contentSize.width, 0), 1),
            y: min(max(frame.midY / contentSize.height, 0), 1)
        )
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
            VanmoLogger.storage.info("[Debug][Downloads] enqueued source=browser connection=\(connection.type.rawValue, privacy: .public)")
#endif
        } catch {
#if DEBUG
            let nsError = error as NSError
            VanmoLogger.storage.info("[Debug][Downloads] enqueue failed source=browser domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public)")
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
    var isOpening = false
    var artwork: [URL] = []
    var extract: (() async -> URL?)?

    var body: some View {
        HStack(spacing: 12) {
            fileIcon
                .frame(width: 36, height: 36)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipped()

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

    @ViewBuilder
    private var fileIcon: some View {
        if file.isDirectory {
            Image(isOpening ? "MacFilesFolderOpen" : "MacFilesFolder")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(MacDesignTokens.accentBlue)
        } else if file.isVideo {
            MacFilesCoverImage(candidates: artwork, extract: extract) {
                systemGlyph("film")
            }
        } else {
            systemGlyph(iconName)
        }
    }

    private func systemGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(file.isDirectory ? MacDesignTokens.accentBlue : theme.secondaryText)
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

/// 按优先级依次尝试封面地址（海报 → 背景图），全部缺失或加载失败后再抽帧，最后显示占位图标。
private struct MacFilesCoverImage<Placeholder: View>: View {
    let candidates: [URL]
    let extract: (() async -> URL?)?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var step = 0
    @State private var extractedURL: URL?

    var body: some View {
        Group {
            if let url = currentURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder().onAppear { step += 1 }
                    default:
                        placeholder()
                    }
                }
                .id(url)
            } else {
                placeholder()
            }
        }
        .onChange(of: candidates) { _, _ in
            step = 0
            extractedURL = nil
        }
        .task(id: MacCoverStepKey(candidates: candidates, step: step)) {
            guard step == candidates.count, extractedURL == nil, let extract else { return }
            extractedURL = await extract()
        }
    }

    private var currentURL: URL? {
        if step < candidates.count { return candidates[step] }
        return step == candidates.count ? extractedURL : nil
    }
}

private struct MacCoverStepKey: Hashable {
    let candidates: [URL]
    let step: Int
}

// MARK: - Grid (Files-Grid)

private struct MacFolderGridTile: View {
    @Environment(\.macTheme) private var theme
    @State private var isHovered = false

    let name: String
    let isOpening: Bool
    let isLoading: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MacDesignTokens.accentBlue.opacity(isHovered ? 0.16 : 0.12))
                .frame(height: 112)
                .overlay {
                    Image(isOpening ? "MacFilesFolderOpen" : "MacFilesFolder")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .foregroundStyle(MacDesignTokens.accentBlue)
                }
                .overlay(alignment: .topTrailing) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                    }
                }
                .scaleEffect(isOpening && !reduceMotion ? 1.06 : 1)

            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
    }
}

private struct MacVideoGridCard: View {
    @Environment(\.macTheme) private var theme
    @State private var isHovered = false

    let file: RemoteFile
    let artwork: [URL]
    let progress: FileWatchProgress?
    let extract: (() async -> URL?)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            Text(file.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityValue(progressDescription)
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if file.isVideo {
                    MacFilesCoverImage(candidates: artwork, extract: extract) { placeholderGlyph }
                } else {
                    placeholderGlyph
                }
            }
            .overlay(alignment: .bottom) { progressBar }
            .overlay(alignment: .topTrailing) { watchedBadge }
            .overlay {
                if isHovered && file.isVideo {
                    ZStack {
                        Color.black.opacity(0.25)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .background(theme.secondaryButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholderGlyph: some View {
        Image(systemName: file.isVideo ? "film" : file.type.macBrowseSystemImage)
            .font(.system(size: 28, weight: .light))
            .foregroundStyle(theme.tertiaryText)
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress, !progress.isWatched, progress.fraction > 0 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.35))
                    Capsule()
                        .fill(MacDesignTokens.accentBlue)
                        .frame(width: max(4, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var watchedBadge: some View {
        if progress?.isWatched == true {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(8)
        }
    }

    private var progressDescription: String {
        guard let progress else { return "" }
        if progress.isWatched { return L10n.tr("已看完") }
        return L10n.tr("已观看 %d%%", Int((progress.fraction * 100).rounded()))
    }
}

// MARK: - Layout & Transition State

private enum MacFilesBrowserLayout: String {
    case grid
    case list
}

private struct MacFolderTransitionState {
    var anchor: UnitPoint = .center
    var isForward = false
    /// 每进入一级记录被点文件夹的锚点，返回时内容收回到对应位置。
    var anchorStack: [UnitPoint] = []
}

/// 文件夹条目在内容区的位置。引用类型：滚动时更新不触发视图刷新。
private final class MacFilesTileFrameStore {
    var frames: [String: CGRect] = [:]
}

private extension View {
    func reportMacTileFrame(path: String?, in space: String, store: MacFilesTileFrameStore) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { frame in
            guard let path else { return }
            store.frames[path] = frame
        }
    }
}

/// 前进：新目录从被点文件夹处放大展开，旧目录轻微放大淡出；返回：反向收回。Reduce Motion 只淡入淡出。
private struct MacFolderOpenTransition: Transition {
    let anchor: UnitPoint
    let isForward: Bool
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .scaleEffect(scale(for: phase), anchor: anchor)
            .opacity(phase.isIdentity ? 1 : 0)
    }

    private func scale(for phase: TransitionPhase) -> CGFloat {
        guard !reduceMotion else { return 1 }
        switch phase {
        case .identity: return 1
        case .willAppear: return isForward ? 0.2 : 1.03
        case .didDisappear: return isForward ? 1.03 : 0.2
        }
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

    var macBrowseSystemImage: String {
        switch self {
        case .video: "film"
        case .subtitle: "captions.bubble"
        case .audio: "music.note"
        case .image: "photo"
        case .directory: "folder"
        case .other: "doc"
        }
    }
}

#Preview("Grid States") {
    let video = RemoteFile(name: "Dune Prophecy S01E01.mkv", path: "/v1", size: 1, isDirectory: false, modifiedDate: nil, type: .video)
    let subtitle = RemoteFile(name: "Dune Prophecy S01E01.srt", path: "/s1", size: 1, isDirectory: false, modifiedDate: nil, type: .subtitle)
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3), spacing: 20) {
        MacFolderGridTile(name: "Specials", isOpening: false, isLoading: false, reduceMotion: false)
        MacFolderGridTile(name: "Extras", isOpening: true, isLoading: true, reduceMotion: false)
        MacFolderGridTile(name: "A very long folder name that wraps onto two lines", isOpening: false, isLoading: false, reduceMotion: false)
        MacVideoGridCard(file: video, artwork: [], progress: FileWatchProgress(fraction: 0.42, isWatched: false), extract: nil)
        MacVideoGridCard(file: video, artwork: [], progress: FileWatchProgress(fraction: 1, isWatched: true), extract: nil)
        MacVideoGridCard(file: subtitle, artwork: [], progress: nil, extract: nil)
    }
    .padding(24)
    .frame(width: 944)
    .macTheme(.light)
}

#Preview("Browse Light") {
    MacConnectionsBrowseView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .macTheme(.light)
        .frame(width: 960, height: 640)
}
