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

    @State private var filterText = ""
    @State private var openingFolderPath: String?
    @State private var isNavigatingDirectory = false
    @State private var folderTransition = MacFolderTransitionState()
    @State private var tileFrames = MacFilesTileFrameStore()
    @State private var contentSize: CGSize = .zero

    private static let contentSpace = "mac.files.browser.content"
    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 20, alignment: .top),
        count: 4
    )

    private var filteredFiles: [RemoteFile] {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return connectionsViewModel.files }
        return connectionsViewModel.files.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MacCatAmbientHalo()
                .offset(x: -70, y: -30)

            VStack(spacing: 0) {
                topToolbar

                if connectionsViewModel.scanCoordinator.isActive {
                    MacScanSyncBanner(
                        coordinator: connectionsViewModel.scanCoordinator,
                        onPause: { connectionsViewModel.pauseScan() },
                        onResume: { connectionsViewModel.resumeScan() },
                        onCancel: { connectionsViewModel.cancelScan() }
                    )
                    .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
                    .padding(.bottom, 12)
                }

                browserContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.appBackground)
        .overlay {
            if connectionsViewModel.isLoading && !connectionsViewModel.scanCoordinator.isActive {
                loadingOverlay
            }
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
            filterText = ""
        }
        .onChange(of: connectionsViewModel.currentPath) { _, _ in
            filterText = ""
        }
        .contextMenu {
            connectionContextMenu
        }
    }

    // MARK: - Top Toolbar (Breadcrumb + Filter + Layout + Sync/Scan)

    private var topToolbar: some View {
        HStack(spacing: 12) {
            breadcrumbGroup

            Spacer(minLength: 12)

            if connectionsViewModel.selectedConnection != nil {
                folderFilterField

                if connectionsViewModel.selectedConnection?.type != .iptv {
                    layoutToggle
                }

                Button {
                    Task { await connectionsViewModel.scanCurrentDirectory() }
                } label: {
                    HStack(spacing: 6) {
                        Image("MacSyncScan")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                        Text(L10n.tr("同步扫描"))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accentAmber)
                    .padding(.leading, 12)
                    .padding(.trailing, 13)
                    .frame(height: 34)
                    .background(theme.amberTintFill, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(theme.strokeAmber, lineWidth: 0.9)
                    }
                }
                .buttonStyle(.plain)
                .help(L10n.tr("同步当前目录到媒体库"))

                Menu {
                    connectionContextMenu
                } label: {
                    Image("MacMoreDots")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(theme.secondaryText)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 34, height: 34)
                .background(theme.surfaceGlass, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                }
                .fixedSize()
                .help(L10n.tr("更多操作"))
            }
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .contextMenu {
            connectionContextMenu
        }
    }

    private var breadcrumbGroup: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if breadcrumbItems.isEmpty {
                    Text(L10n.tr("连接浏览"))
                        .font(MacDesignTokens.Typography.headerTitle)
                        .foregroundStyle(theme.primaryText)
                } else {
                    ForEach(Array(breadcrumbItems.enumerated()), id: \.offset) { index, item in
                        let isLast = index == breadcrumbItems.count - 1
                        if index > 0 {
                            Text("›")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(theme.tertiaryText)
                        }

                        Button {
                            navigateToBreadcrumb(item.path)
                        } label: {
                            Text(item.title)
                                .font(.system(size: isLast ? 18 : 15, weight: isLast ? .bold : .medium))
                                .foregroundStyle(isLast ? theme.primaryText : theme.secondaryText)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLast)
                    }
                }
            }
        }
    }

    private var currentDirectoryTitle: String {
        breadcrumbItems.last?.title ?? L10n.tr("当前目录")
    }

    private var folderFilterField: some View {
        HStack(spacing: 7) {
            Image("MacSearchCat")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(filterText.isEmpty ? theme.secondaryText : theme.accentAmber)

            TextField(L10n.tr("过滤 %@...", currentDirectoryTitle), text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText)

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 10)
        .frame(width: 210, height: 34)
        .background(theme.surfaceGlass, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(filterText.isEmpty ? theme.strokeGlass : theme.strokeAmber, lineWidth: 0.9)
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

    // MARK: - Content

    @ViewBuilder
    private var browserContent: some View {
        if connectionsViewModel.selectedConnection == nil {
            emptySelectionState
        } else if connectionsViewModel.isBrowsingFiles && !isNavigatingDirectory {
            loadingState
        } else if let message = connectionsViewModel.fileBrowserErrorMessage {
            emptyOrDisconnectedCard(
                title: L10n.tr("无法加载目录"),
                message: message,
                actionTitle: L10n.tr("重新连接并扫描")
            ) {
                if let conn = connectionsViewModel.selectedConnection {
                    Task { _ = await connectionsViewModel.connectAndScan(conn) }
                }
            }
        } else if connectionsViewModel.files.isEmpty {
            emptyOrDisconnectedCard(
                title: L10n.tr("空文件夹或连接已断开"),
                message: L10n.tr("此目录下没有可显示的文件，或者连接暂时离线。"),
                actionTitle: L10n.tr("重新连接并扫描")
            ) {
                Task { await connectionsViewModel.refreshCurrentDirectory() }
            }
        } else if filteredFiles.isEmpty {
            emptyOrDisconnectedCard(
                title: L10n.tr("没有匹配项"),
                message: L10n.tr("当前目录下没有匹配「%@」的文件。", filterText),
                actionTitle: L10n.tr("清除过滤")
            ) {
                filterText = ""
            }
        } else {
            directoryContainer
        }
    }

    // MARK: - Layout

    private var layout: MacFilesBrowserLayout {
        guard connectionsViewModel.selectedConnection?.type != .iptv else { return .list }
        return MacFilesBrowserLayout(rawValue: layoutRaw) ?? .grid
    }

    private var layoutToggle: some View {
        HStack(spacing: 3) {
            layoutSegmentButton(mode: .grid, assetName: "MacGridView", help: L10n.tr("切换为网格"))
            layoutSegmentButton(mode: .list, assetName: "MacListView", help: L10n.tr("切换为列表"))
        }
        .padding(4)
        .frame(height: 34)
        .background(theme.surfaceGlass, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
        }
    }

    private func layoutSegmentButton(mode: MacFilesBrowserLayout, assetName: String, help: String) -> some View {
        let isSelected = layout == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                layoutRaw = mode.rawValue
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)
                    .frame(width: 32, height: 26)
                    .background(
                        isSelected ? theme.amberTintFill : Color.clear,
                        in: Capsule()
                    )
                    .overlay {
                        if isSelected {
                            Capsule()
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                        }
                    }

                if isSelected {
                    MacPawDotIndicator(size: 7)
                        .offset(x: -3, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

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
                LazyVStack(spacing: 6) {
                    ForEach(filteredFiles) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
                .padding(.bottom, 24)
            }
        }
    }

    private var gridListing: some View {
        let folders = filteredFiles.filter(\.isDirectory)
        let items = filteredFiles.filter { !$0.isDirectory }
        return VStack(alignment: .leading, spacing: 14) {
            if !folders.isEmpty {
                gridSectionHeader(
                    L10n.tr("文件夹 · %d 项", folders.count),
                    showsCat: items.isEmpty
                )
                LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                    ForEach(folders) { folder in
                        folderGridTile(folder)
                    }
                }
            }
            if !items.isEmpty {
                let sectionTitle = items.allSatisfy(\.isVideo)
                    ? L10n.tr("视频 · %d 项", items.count)
                    : L10n.tr("文件 · %d 项", items.count)
                gridSectionHeader(sectionTitle, showsCat: true)
                    .padding(.top, folders.isEmpty ? 0 : 8)
                LazyVGrid(columns: Self.gridColumns, spacing: 20) {
                    ForEach(items) { file in
                        fileGridCard(file)
                    }
                }
            }
        }
        .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
        .padding(.bottom, 28)
    }

    private func gridSectionHeader(_ title: String, showsCat: Bool) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .tracking(0.5)

            Spacer()

            if showsCat {
                Image("MacStretchingCat")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 14)
                    .foregroundStyle(theme.secondaryText.opacity(0.75))
            }
        }
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
        .buttonStyle(.plain)
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
        emptyOrDisconnectedCard(
            title: L10n.tr("未选择连接"),
            message: L10n.tr("请从侧边栏选择一个连接以浏览文件"),
            actionTitle: nil,
            action: {}
        )
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.tr("正在加载目录..."))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyOrDisconnectedCard(
        title: String,
        message: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack {
            HStack(spacing: 18) {
                Image("MacCatFolderCurious")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 66)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(theme.primaryText)

                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.accentAmber)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(theme.amberTintFill, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(theme.strokeAmber, lineWidth: 0.9)
                        }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(theme.strokeGlass, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            }
            .padding(.horizontal, MacDesignTokens.Layout.contentPadding)
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(connectionsViewModel.loadingMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.primaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .macCatGlassCard(theme: theme, cornerRadius: 14)
        }
        .ignoresSafeArea()
    }

    // MARK: - Helpers

    private var breadcrumbItems: [(title: String, path: String)] {
        guard let connection = connectionsViewModel.selectedConnection else { return [] }

        var items: [(title: String, path: String)] = [(connection.name, "/")]
        let currentPath = connectionsViewModel.currentPath
        guard currentPath != "/" else { return items }

        var ancestorPaths = connectionsViewModel.pathStack.filter { $0 != "/" }
        if ancestorPaths.isEmpty {
            let components = currentPath.split(separator: "/").map(String.init)
            if components.first != "item", components.count > 1 {
                var built = ""
                for component in components.dropLast() {
                    built = built.isEmpty ? "/\(component)" : (built as NSString).appendingPathComponent(component)
                    ancestorPaths.append(built)
                }
            }
        }
        for path in ancestorPaths {
            let title = connectionsViewModel.displayName(forPath: path)
                ?? (path as NSString).lastPathComponent
            items.append((title, path))
        }
        let title = connectionsViewModel.displayName(forPath: currentPath)
            ?? (currentPath as NSString).lastPathComponent
        items.append((title, currentPath))
        return items
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

// MARK: - File Row (List Mode)

private struct MacConnectionFileRow: View {
    @Environment(\.macTheme) private var theme

    let file: RemoteFile
    var isOpening = false
    var artwork: [URL] = []
    var extract: (() async -> URL?)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            fileIcon
                .frame(width: 40, height: 40)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: file.isDirectory ? 14 : 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            } else if file.isVideo {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(theme.accentAmber)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .macCatGlassCard(theme: theme, cornerRadius: 14, isHighlighted: isHovered)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder
    private var fileIcon: some View {
        if file.isDirectory {
            Image(isOpening ? "MacFilesFolderOpen" : "MacFilesFolder")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(theme.accentAmber)
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
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(file.isDirectory ? theme.accentAmber : theme.secondaryText)
    }

    private var iconName: String {
        if file.isDirectory { return "folder.fill" }
        if file.isVideo { return "film" }
        return "doc"
    }

    private var iconBackground: Color {
        file.isDirectory ? theme.amberTintFill : theme.surfacePill
    }

    private var subtitle: String {
        if file.isDirectory { return L10n.tr("文件夹") }
        if file.size > 0 { return MacBrowseFormatters.fileSize(file.size) }
        return file.type.macBrowseDisplayName
    }
}

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

// MARK: - Grid Tiles (4-Column Black Cat Cards)

private struct MacFolderGridTile: View {
    @Environment(\.macTheme) private var theme
    @State private var isHovered = false

    let name: String
    let isOpening: Bool
    let isLoading: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isHovered ? theme.amberTintFill : theme.surfaceGlass)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isHovered ? theme.strokeAmber : theme.strokeGlass, lineWidth: isHovered ? 1.15 : 0.9)
                    }
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)

                Image(isOpening ? "MacFilesFolderOpen" : "MacFilesFolder")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .foregroundStyle(theme.accentAmber)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(10)
                }
            }
            .scaleEffect(isOpening && !reduceMotion ? 1.04 : 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(L10n.tr("文件夹"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.secondaryText)
            }
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

    private var isHighlighted: Bool {
        isHovered || (progress != nil && progress?.isWatched == false && (progress?.fraction ?? 0) > 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cover

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metaLine)
                    .font(.system(size: 10.5))
                    .foregroundStyle((progress?.isWatched == true || (progress?.fraction ?? 0) > 0) ? theme.accentAmber : theme.secondaryText)
                    .lineLimit(1)
            }
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
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.clear, MacDesignTokens.catSilhouette.opacity(0.91)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 68)
            }
            .overlay(alignment: .bottom) { progressBar }
            .overlay(alignment: .topTrailing) { watchedBadge }
            .overlay {
                if isHovered && file.isVideo {
                    ZStack {
                        Color.black.opacity(0.28)
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(MacDesignTokens.glowAmber)
                    }
                }
            }
            .background(theme.surfaceGlass)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isHighlighted ? theme.strokeAmber : theme.strokeGlass,
                        lineWidth: isHighlighted ? 1.15 : 0.9
                    )
            }
    }

    private var placeholderGlyph: some View {
        Image(systemName: file.isVideo ? "film" : file.type.macBrowseSystemImage)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(theme.tertiaryText)
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress, !progress.isWatched, progress.fraction > 0 {
            MacCatProgressTrack(progress: progress.fraction)
                .padding(.horizontal, 11)
                .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var watchedBadge: some View {
        if progress?.isWatched == true {
            MacSleepingCatWatchedPill()
                .padding(9)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let progress {
            if progress.isWatched {
                parts.append(L10n.tr("已看"))
            } else if progress.fraction > 0 {
                parts.append("\(Int((progress.fraction * 100).rounded()))%")
            }
        }
        let ext = (file.name as NSString).pathExtension.uppercased()
        if !ext.isEmpty {
            parts.append(ext)
        }
        if file.size > 0 {
            parts.append(MacBrowseFormatters.fileSize(file.size))
        }
        return parts.isEmpty ? file.type.macBrowseDisplayName : parts.joined(separator: " · ")
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
    var anchorStack: [UnitPoint] = []
}

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

#Preview("Browse Dark") {
    MacConnectionsBrowseView()
        .environmentObject(MacAppState())
        .environmentObject(MacLibraryViewModel())
        .environmentObject(MacConnectionsViewModel())
        .environmentObject(MacSearchViewModel())
        .environmentObject(DownloadManager.shared)
        .macTheme(.dark)
        .frame(width: 1199, height: 760)
}
