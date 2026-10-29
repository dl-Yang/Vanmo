import SwiftUI
import SwiftData
import VanmoCore

struct ConnectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: ConnectionsViewModel
    @EnvironmentObject private var downloadManager: DownloadManager

    /// 当前正在浏览的连接 ID。nil = 显示连接列表根页（Files-Light）；
    /// 非 nil = 进入该连接的文件 / 文件夹浏览页（Files-Folders(-Videos)-Light）。
    @State private var enteredConnectionID: UUID?
    @State private var editingConnection: SavedConnection?
    @AppStorage("files.browserLayout") private var layoutRaw = FilesBrowserLayout.grid.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 正在打开的文件夹路径：保留旧内容并在该条目上显示打开态，加载完成后再做展开过渡。
    @State private var openingFolderPath: String?
    @State private var isNavigatingDirectory = false
    @State private var folderTransition = FolderTransitionState()
    @State private var tileFrames = FilesTileFrameStore()
    @State private var contentSize: CGSize = .zero
#if DEBUG
    /// 关闭播放器后 `.task` 会重跑；调试验收每个进程只触发一次。
    private static var didRunDebugSourceAcceptance = false
#endif

    var body: some View {
        ZStack {
            FilesDesign.background.ignoresSafeArea()

            if enteredConnectionID == nil {
                connectionsRoot
                    .transition(.move(edge: .leading).combined(with: .opacity))
            } else {
                fileBrowser
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if viewModel.isLoading && !viewModel.scanCoordinator.isActive {
                LoadingView(viewModel.loadingMessage)
            }
        }
        .overlay(alignment: .bottom) {
            ScanSyncBanner(
                coordinator: viewModel.scanCoordinator,
                onPause: { viewModel.pauseScan() },
                onResume: { viewModel.resumeScan() },
                onCancel: { viewModel.cancelScan() }
            )
        }
        .alert(L10n.tr("同步"), isPresented: Binding(
            get: { viewModel.scanToastMessage != nil },
            set: { if !$0 { viewModel.scanToastMessage = nil } }
        )) {
            Button(L10n.tr("确定")) { viewModel.scanToastMessage = nil }
        } message: {
            Text(viewModel.scanToastMessage ?? "")
        }
        .task {
            viewModel.setModelContext(modelContext)
            await openPendingFolderBookmarkIfNeeded()
#if DEBUG
            await runDebugSourceAcceptanceIfNeeded()
#endif
        }
        .onChange(of: viewModel.pendingFolderBookmarkNavigation?.id) { _, _ in
            Task { await openPendingFolderBookmarkIfNeeded() }
        }
        .onChange(of: appState.isPlayerPresented) { _, isPresented in
            if !isPresented { viewModel.refreshLibraryStates() }
        }
        .alert(L10n.tr("错误"), isPresented: $viewModel.showError) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $viewModel.showAddConnection) {
            AddConnectionView(viewModel: viewModel)
        }
        .sheet(item: $editingConnection) { connection in
            AddConnectionView(viewModel: viewModel, editingConnection: connection)
        }
    }

    // MARK: - 根页：连接列表（Files-Light）

    private var connectionsRoot: some View {
        VStack(spacing: 0) {
            FilesHeader(title: L10n.tr("文件")) {
                FilesCircleButton(asset: nil, systemName: "plus", tint: FilesDesign.accent, background: FilesDesign.addButtonBackground) {
                    viewModel.showAddConnection = true
                }
                .accessibilityIdentifier("files.addConnection")
            }

            if viewModel.savedConnections.isEmpty {
                EmptyStateView(
                    icon: "folder.badge.plus",
                    title: L10n.tr("暂无文件来源"),
                    message: L10n.tr("使用右上角按钮添加本地文件夹或服务器连接")
                ) {
                    viewModel.showAddConnection = true
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        FilesSectionHeader(title: L10n.tr("网络"))
                        VStack(spacing: 4) {
                            ForEach(viewModel.savedConnections) { connection in
                                connectionRow(connection)
                            }
                        }
                        .padding(.top, 16)
                    }
                    .padding(16)
                }
            }
        }
    }

    private func connectionRow(_ connection: SavedConnection) -> some View {
        Button {
            enter(connection)
        } label: {
            ConnectionCard(connection: connection)
        }
        .buttonStyle(FilesRowButtonStyle())
        .contextMenu {
            Button {
                editingConnection = connection
            } label: {
                Label(L10n.tr("编辑"), systemImage: "pencil")
            }
            if connection.type.requiresManualDirectorySync {
                Button {
                    Task { await viewModel.connectAndScan(connection) }
                } label: {
                    Label(L10n.tr("连接"), systemImage: "link")
                }
            } else {
                Button {
                    Task { await viewModel.connectAndScan(connection) }
                } label: {
                    Label(L10n.tr("同步到媒体库"), systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    Task { await viewModel.connectAndScan(connection, forceFullScan: true) }
                } label: {
                    Label(L10n.tr("全量重扫"), systemImage: "arrow.clockwise")
                }
            }
            Button(role: .destructive) {
                viewModel.deleteConnection(connection)
            } label: {
                Label(L10n.tr("删除"), systemImage: "trash")
            }
        }
    }

    // MARK: - 浏览页：文件夹 / 视频（Files-Folders(-Videos) 列表 / Files-Grid 网格）

    private static let contentSpace = "files.browser.content"
    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 12, alignment: .top),
        count: 3
    )

    private var layout: FilesBrowserLayout {
        FilesBrowserLayout(rawValue: layoutRaw) ?? .grid
    }

    private var fileBrowser: some View {
        VStack(spacing: 0) {
            FilesHeader(title: browserTitle, onBack: handleBack) {
                if isNavigatingDirectory && viewModel.isBrowsingFiles && openingFolderPath == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FilesDesign.accent)
                        .frame(width: 32, height: 32)
                }
                if !isIPTVBrowsing {
                    layoutToggle
                }
                Menu {
                    Button {
                        Task { await viewModel.refreshCurrentDirectory() }
                    } label: {
                        Label(L10n.tr("刷新"), systemImage: "arrow.clockwise")
                    }
                    Button {
                        Task { await viewModel.scanCurrentDirectory() }
                    } label: {
                        Label(L10n.tr("同步当前目录"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    FilesMenuGlyph()
                }
            }

            browserContent
        }
    }

    /// 图标显示点按后切换到的布局（网格态显示列表图标）。
    private var layoutToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                layoutRaw = (layout == .grid ? FilesBrowserLayout.list : .grid).rawValue
            }
        } label: {
            Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(FilesDesign.secondaryIcon)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .grid ? L10n.tr("切换为列表") : L10n.tr("切换为网格"))
        .accessibilityIdentifier("files.layoutToggle")
    }

    @ViewBuilder
    private var browserContent: some View {
        if viewModel.isBrowsingFiles && !isNavigatingDirectory {
            VStack(spacing: 10) {
                ProgressView()
                    .tint(FilesDesign.accent)
                Text(L10n.tr("正在加载目录..."))
                    .font(.subheadline)
                    .foregroundStyle(FilesDesign.subtitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.fileBrowserErrorMessage {
            FilesMessageView(icon: "exclamationmark.triangle", title: L10n.tr("无法加载目录"), message: message)
        } else if viewModel.files.isEmpty {
            if isIPTVBrowsing {
                FilesMessageView(icon: "tv.slash", title: L10n.tr("暂无频道"), message: "播放列表为空或无法解析，请检查 M3U 源后点击右上角刷新")
            } else {
                FilesMessageView(icon: "folder", title: L10n.tr("文件夹为空"), message: L10n.tr("此目录下没有可显示的文件"))
            }
        } else if isIPTVBrowsing {
            iptvChannelList
        } else {
            directoryContainer
        }
    }

    /// 以目录路径为身份做“文件夹打开”过渡：前进时新内容从被点文件夹处展开，返回时收回到该处。
    private var directoryContainer: some View {
        ZStack {
            directoryListing
                .id(viewModel.currentPath)
                .transition(FolderOpenTransition(
                    anchor: folderTransition.anchor,
                    isForward: folderTransition.isForward,
                    reduceMotion: reduceMotion
                ))
                .zIndex(Double(viewModel.pathStack.count))
        }
        .coordinateSpace(.named(Self.contentSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
        .animation(directoryAnimation, value: viewModel.currentPath)
    }

    private var directoryAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private var directoryListing: some View {
        ScrollView(showsIndicators: false) {
            if layout == .grid {
                gridListing
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.files) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .refreshable {
            await viewModel.refreshCurrentDirectory()
        }
    }

    private var gridListing: some View {
        let folders = viewModel.files.filter(\.isDirectory)
        let items = viewModel.files.filter { !$0.isDirectory }
        return VStack(alignment: .leading, spacing: 12) {
            if !folders.isEmpty {
                FilesSectionHeader(title: L10n.tr("文件夹"))
                LazyVGrid(columns: Self.gridColumns, spacing: 16) {
                    ForEach(folders) { folder in
                        folderGridTile(folder)
                    }
                }
            }
            if !items.isEmpty {
                FilesSectionHeader(title: items.allSatisfy(\.isVideo) ? L10n.tr("视频") : L10n.tr("文件"))
                    .padding(.top, folders.isEmpty ? 0 : 8)
                LazyVGrid(columns: Self.gridColumns, spacing: 16) {
                    ForEach(items) { file in
                        fileGridCard(file)
                    }
                }
            }
        }
        .padding(16)
    }

    private func folderGridTile(_ folder: RemoteFile) -> some View {
        Button {
            openFolder(folder)
        } label: {
            FolderGridTile(
                name: folder.name,
                isOpening: openingFolderPath == folder.path,
                isLoading: openingFolderPath == folder.path && viewModel.isBrowsingFiles,
                reduceMotion: reduceMotion
            )
        }
        .buttonStyle(FilesGridButtonStyle())
        .reportTileFrame(path: folder.path, in: Self.contentSpace, store: tileFrames)
        .contextMenu { fileContextMenu(folder) }
    }

    private func fileGridCard(_ file: RemoteFile) -> some View {
        Button {
            Task { await handleFileTap(file) }
        } label: {
            FileGridCard(
                file: file,
                artwork: artworkCandidates(for: file),
                progress: watchProgress(for: file),
                extract: extractedFrameLoader(for: file)
            )
        }
        .buttonStyle(FilesGridButtonStyle())
        .contextMenu { fileContextMenu(file) }
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        Button {
            Task { await handleFileTap(file) }
        } label: {
            FileCard(
                file: file,
                isOpening: openingFolderPath == file.path,
                artwork: artworkCandidates(for: file),
                extract: extractedFrameLoader(for: file)
            )
        }
        .buttonStyle(FilesRowButtonStyle())
        .reportTileFrame(path: file.isDirectory ? file.path : nil, in: Self.contentSpace, store: tileFrames)
        .contextMenu { fileContextMenu(file) }
    }

    @ViewBuilder
    private func fileContextMenu(_ file: RemoteFile) -> some View {
        if file.isDirectory {
            Button {
                openFolder(file)
            } label: {
                Label(L10n.tr("打开"), systemImage: "folder")
            }
            if viewModel.canBookmarkFoldersInSelectedConnection {
                Button {
                    viewModel.toggleFolderBookmark(file)
                } label: {
                    if viewModel.isFolderBookmarked(file) {
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
            if let connection = viewModel.selectedConnection,
               DownloadEligibility.isEligible(file: file, connectionType: connection.type) {
                Button {
                    Task { await download(file, connection: connection) }
                } label: {
                    Label(L10n.tr("下载"), systemImage: "arrow.down.circle")
                }
            }
        }
    }

    // MARK: - 封面 & 进度

    private func artworkCandidates(for file: RemoteFile) -> [URL] {
        guard file.isVideo else { return [] }
        return FileCoverResolver.artworkCandidates(for: file, library: viewModel.libraryStates[file.path])
    }

    private func watchProgress(for file: RemoteFile) -> FileWatchProgress? {
        guard file.isVideo else { return nil }
        return FileCoverResolver.progress(for: file, library: viewModel.libraryStates[file.path])
    }

    private func extractedFrameLoader(for file: RemoteFile) -> (() async -> URL?)? {
        guard file.isVideo else { return nil }
        let viewModel = viewModel
        return { await viewModel.thumbnailURL(for: file) }
    }

    // MARK: - IPTV 频道（分组 + 台标）

    private var isIPTVBrowsing: Bool {
        viewModel.selectedConnection?.type == .iptv
    }

    private var iptvChannelList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedChannels(viewModel.files), id: \.group) { section in
                    Section {
                        ForEach(section.channels) { channel in
                            iptvChannelRow(channel)
                        }
                    } header: {
                        FilesSectionHeader(title: section.group)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .refreshable {
            await viewModel.refreshCurrentDirectory()
        }
    }

    private func iptvChannelRow(_ channel: RemoteFile) -> some View {
        Button {
            Task { await play(channel) }
        } label: {
            IPTVChannelCard(
                channel: channel,
                epgGuide: viewModel.epgGuide,
                isLoadingEPG: viewModel.isLoadingEPG,
                isPlaybackFailed: viewModel.isChannelPlaybackFailed(channel)
            )
        }
        .buttonStyle(FilesRowButtonStyle())
    }

    /// 按 group-title 分组，保持频道在播放列表中的原始顺序；无分组归入「未分组」。
    private func groupedChannels(_ files: [RemoteFile]) -> [(group: String, channels: [RemoteFile])] {
        var order: [String] = []
        var grouped: [String: [RemoteFile]] = [:]
        for file in files {
            let group = (file.groupTitle?.isEmpty == false ? file.groupTitle : nil) ?? L10n.tr("未分组")
            if grouped[group] == nil { order.append(group) }
            grouped[group, default: []].append(file)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    // MARK: - 导航 & 标题

    private var browserTitle: String {
        guard let connection = viewModel.selectedConnection else { return L10n.tr("文件") }
        if viewModel.pathStack.isEmpty { return connection.name }
        let last = (viewModel.currentPath as NSString).lastPathComponent
        return last.isEmpty || last == "/" ? connection.name : last
    }

#if DEBUG
    private func runDebugSourceAcceptanceIfNeeded() async {
        let env = ProcessInfo.processInfo.environment
        guard !Self.didRunDebugSourceAcceptance,
              let name = env["VANMO_DEBUG_OPEN_CONNECTION"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }
        Self.didRunDebugSourceAcceptance = true
        guard let connection = viewModel.savedConnections.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            VanmoLogger.library.info("[Debug][LibraryScan] accept missing connection name=\(name, privacy: .public)")
            return
        }
        enter(connection)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for _ in 0..<20 where viewModel.files.isEmpty {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let openPath = (env["VANMO_DEBUG_OPEN_PATH"] ?? "").split(separator: "/").map(String.init)
        for component in openPath {
            guard let folder = viewModel.files.first(where: { $0.isDirectory && $0.name == component }) else {
                let listedCount = viewModel.files.count
                VanmoLogger.library.info("[Debug][LibraryScan] accept missing folder=\(component, privacy: .public) listed=\(listedCount, privacy: .public)")
                return
            }
            await viewModel.openDirectory(folder)
        }
        let playName = env["VANMO_DEBUG_PLAY_NAME"]
        var video = viewModel.files.first { $0.isVideo && (playName == nil || $0.name == playName) }
        var descended = 0
        while video == nil, openPath.isEmpty, descended < 4,
              let folder = viewModel.files.first(where: \.isDirectory) {
            await viewModel.openDirectory(folder)
            video = viewModel.files.first { $0.isVideo && (playName == nil || $0.name == playName) }
            descended += 1
        }
        let actions = Set(
            (env["VANMO_DEBUG_ACCEPT_ACTIONS"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let listedCount = viewModel.files.count
        let actionList = actions.sorted().joined(separator: ",")
        VanmoLogger.library.info("[Debug][LibraryScan] accept listed=\(listedCount, privacy: .public) hasVideo=\(video != nil, privacy: .public) actions=\(actionList, privacy: .public)")
        if actions.contains("connect") {
            _ = await viewModel.connectAndScan(connection, showErrorAlert: false)
            let control = String(describing: viewModel.scanCoordinator.controlState)
            VanmoLogger.library.info("[Debug][LibraryScan] accept connect done control=\(control, privacy: .public)")
        }
        if actions.contains("cancel") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                viewModel.cancelScan()
                VanmoLogger.library.info("[Debug][LibraryScan] accept cancel requested")
            }
            _ = await viewModel.scanCurrentDirectory()
            let control = String(describing: viewModel.scanCoordinator.controlState)
            VanmoLogger.library.info("[Debug][LibraryScan] accept cancel finished control=\(control, privacy: .public)")
        } else if actions.contains("scan") {
            _ = await viewModel.scanCurrentDirectory()
            let control = String(describing: viewModel.scanCoordinator.controlState)
            VanmoLogger.library.info("[Debug][LibraryScan] accept scan done control=\(control, privacy: .public)")
        }
        if actions.contains("play"), let video {
            await play(video)
        }
        if actions.contains("download"), let video {
            await download(video, connection: connection)
        }
        if actions.contains("delete") {
            viewModel.deleteConnection(connection)
            VanmoLogger.library.info("[Debug][LibraryScan] accept delete requested")
        }
    }
#endif

    private func enter(_ connection: SavedConnection) {
        folderTransition = FolderTransitionState()
        withAnimation(.easeInOut(duration: 0.25)) {
            enteredConnectionID = connection.id
        }
        Task { await viewModel.selectConnection(connection) }
    }

    private func openFolder(_ folder: RemoteFile) {
        guard folder.isDirectory, !isNavigatingDirectory else { return }
        let anchor = tileAnchor(for: folder.path)
        folderTransition.anchor = anchor
        folderTransition.isForward = true
        isNavigatingDirectory = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) {
            openingFolderPath = folder.path
        }
        Task {
            let depth = viewModel.pathStack.count
            await viewModel.openDirectory(folder)
            if viewModel.pathStack.count > depth {
                folderTransition.anchorStack.append(anchor)
            }
            openingFolderPath = nil
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

    private func openPendingFolderBookmarkIfNeeded() async {
        guard let request = viewModel.pendingFolderBookmarkNavigation else { return }
        await MainActor.run {
            folderTransition = FolderTransitionState()
            withAnimation(.easeInOut(duration: 0.25)) {
                enteredConnectionID = request.connectionId
            }
        }
        _ = await viewModel.openFolderBookmarkRequest(request)
    }

    private func handleBack() {
        if viewModel.pathStack.isEmpty {
            withAnimation(.easeInOut(duration: 0.25)) {
                enteredConnectionID = nil
            }
        } else {
            guard !isNavigatingDirectory else { return }
            let anchor = folderTransition.anchorStack.popLast() ?? .center
            folderTransition.anchor = anchor
            folderTransition.isForward = false
            isNavigatingDirectory = true
            Task {
                let depth = viewModel.pathStack.count
                await viewModel.goBackDirectory()
                if viewModel.pathStack.count >= depth {
                    folderTransition.anchorStack.append(anchor)
                }
                isNavigatingDirectory = false
            }
        }
    }

    // MARK: - 文件操作

    private func handleFileTap(_ file: RemoteFile) async {
        if file.isDirectory {
            openFolder(file)
        } else if file.isVideo {
            await play(file)
        }
    }

    private func play(_ file: RemoteFile) async {
        do {
            let url: URL
            if let connection = viewModel.selectedConnection, connection.type.usesEphemeralStreamURLs {
                url = connection.type.catalogPlaybackURL(serverPath: file.path)
            } else {
                url = try await viewModel.streamURL(for: file)
            }
            let item: MediaItem
            if isIPTVBrowsing {
                // 直播频道：用频道原名作标题，不跑文件名解析（避免把频道名误判成季集）。
                item = MediaItem(title: file.name, fileURL: url, mediaType: .movie, fileSize: file.size)
                item.isLiveStream = true
            } else if let connection = viewModel.selectedConnection,
                      let factoryItem = MediaItemFactory.makeMediaItem(
                          from: file,
                          streamURL: url,
                          connectionId: connection.id,
                          directoryPath: viewModel.currentPath
                      ) {
                item = factoryItem
            } else {
                item = MediaItem(title: file.name, fileURL: url, mediaType: .movie, fileSize: file.size)
                item.serverId = file.path
                item.sourceConnectionId = viewModel.selectedConnection?.id
                item.originalFileName = file.name
            }
            if item.serverId == nil {
                item.serverId = file.path
            }
            if item.sourceConnectionId == nil {
                item.sourceConnectionId = viewModel.selectedConnection?.id
            }
            if item.originalFileName == nil {
                item.originalFileName = file.name
            }
            if item.container == nil {
                let ext = (file.name as NSString).pathExtension
                item.container = ext.isEmpty ? nil : ext.lowercased()
            }
            appState.play(viewModel.persistentPlaybackItem(for: file, candidate: item))
        } catch {
            if isIPTVBrowsing {
                viewModel.markChannelPlaybackFailed(file)
            }
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
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
            let connectionType = connection.type.rawValue
            VanmoLogger.library.info("[Debug][Downloads] enqueued source=browser connection=\(connectionType, privacy: .public)")
#endif
        } catch {
#if DEBUG
            let nsError = error as NSError
            let domain = nsError.domain
            let code = nsError.code
            VanmoLogger.library.error("[Debug][Downloads] enqueue failed source=browser domain=\(domain, privacy: .public) code=\(code, privacy: .public)")
#endif
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }
}

// MARK: - 设计 Token（Files 页 · Light / Dark 自适应）

/// 严格取自 Figma `File` 页 Light / Dark 设计稿。动态色随有效 ColorScheme
/// （受 App 主题 `.preferredColorScheme` 驱动）自动在浅 / 深色间切换。
private enum FilesDesign {
    static let background        = dyn("#F4F4F5", "#000000")          // 页面背景
    static let headerBorder      = dyn("#E4E4E7", "#27272A")          // 头部底分割线（用时 0.5 透明）
    static let title             = dyn("#18181B", "#FFFFFF")          // 主文字 / 返回箭头
    static let sectionHeader     = dyn("#71717B", "#9F9FA9")          // “网络” 分组标题
    static let subtitle          = dyn("#71717B", "#71717B")          // 协议 / 大小 / items 次级文字
    static let accent            = Color.vanmoAccent                  // 强调蓝：+ / 连接 / 文件夹图标
    static let addButtonBackground = Color.vanmoAccent.opacity(0.12)  // “+” 按钮底
    static let iconBoxGray       = dyn("#E4E4E7", "#27272A")          // NAS / 视频图标底盒
    static let folderBoxBackground = Color.vanmoAccent.opacity(0.08)  // 文件夹图标底盒
    static let folderBoxPressed  = Color.vanmoAccent.opacity(0.16)    // 网格文件夹按下
    static let statusConnected   = dyn("#009966", "#00D492")          // 已连接绿
    static let connectionDot     = dyn("#9F9FA9", "#52525C")          // 连接副标题分隔圆点
    static let videoDot          = dyn("#D4D4D8", "#3F3F47")          // 视频信息分隔圆点
    static let secondaryIcon     = dyn("#52525C", "#9F9FA9")          // 视频图标 / 顶部菜单字形
    static let chevron           = dyn("#9F9FA9", "#52525C")          // 行尾箭头
    static let pressedHighlight  = dyn("#E4E4E7", "#27272A", 0.6, 0.6) // 行按下高亮

    /// 构造随明暗切换的动态颜色（可分别指定浅 / 深色透明度）。
    static func dyn(_ light: String, _ dark: String, _ lightAlpha: Double = 1, _ darkAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let base = Color(hex: isDark ? dark : light) ?? .clear
            return UIColor(base).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }
}

// MARK: - 顶部头部

private struct FilesHeader<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, onBack: (() -> Void)? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FilesDesign.title)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(FilesDesign.title)
                .lineLimit(1)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                trailing()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 17)
        .background(
            FilesDesign.background
                .overlay(alignment: .bottom) {
                    FilesDesign.headerBorder.opacity(0.5).frame(height: 1)
                }
        )
    }
}

private struct FilesSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(FilesDesign.sectionHeader)
            .padding(.horizontal, 8)
    }
}

// MARK: - 头部按钮

private struct FilesCircleButton: View {
    let asset: String?
    var systemName: String?
    let tint: Color
    var background: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            iconImage
                .frame(width: 20, height: 20)
                .frame(width: 32, height: 32)
                .background(background, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconImage: some View {
        if let asset {
            Image(asset).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(tint)
        } else if let systemName {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}

/// 头部右上角竖向三点菜单字形（对齐设计稿 lucide ellipsis-vertical）。
private struct FilesMenuGlyph: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 18, weight: .semibold))
            .rotationEffect(.degrees(90))
            .foregroundStyle(FilesDesign.secondaryIcon)
            .frame(width: 32, height: 32)
            .contentShape(Circle())
    }
}

// MARK: - 连接行卡片

private struct ConnectionCard: View {
    let connection: SavedConnection

    var body: some View {
        HStack(spacing: 0) {
            FilesIconBox(background: FilesDesign.iconBoxGray) {
                ConnectionProviderIcon(type: connection.type, size: 28, fallbackTint: FilesDesign.accent)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(connection.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FilesDesign.title)
                    .lineLimit(1)

                Text(connection.type.displayName)
                    .textCase(.uppercase)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FilesDesign.subtitle)
                    .padding(.top, 2)
            }
            .padding(.leading, 16)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FilesDesign.chevron)
                .frame(width: 20, height: 20)
        }
        .padding(12)
    }
}

// MARK: - 文件 / 文件夹行卡片

private struct FileCard: View {
    let file: RemoteFile
    var isOpening = false
    var artwork: [URL] = []
    var extract: (() async -> URL?)?

    var body: some View {
        HStack(spacing: 0) {
            FilesIconBox(background: file.isDirectory ? FilesDesign.folderBoxBackground : FilesDesign.iconBoxGray) {
                if file.isDirectory {
                    fileGlyph(name: isOpening ? "FilesFolderOpen" : "FilesFolder", color: FilesDesign.accent)
                } else if file.isVideo {
                    FilesCoverImage(candidates: artwork, extract: extract) {
                        fileGlyph(name: "FilesFileVideo", color: FilesDesign.secondaryIcon)
                    }
                    .frame(width: 24, height: 24)
                    .clipped()
                } else {
                    fileGlyph(name: "FilesFileVideo", color: FilesDesign.secondaryIcon)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(file.name)
                    .font(.system(size: file.isDirectory ? 15 : 14, weight: file.isDirectory ? .semibold : .medium))
                    .foregroundStyle(FilesDesign.title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                subtitle
                    .padding(.top, file.isDirectory ? 2 : 4)
            }
            .padding(.leading, 16)

            Spacer(minLength: 8)

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FilesDesign.chevron)
                    .frame(width: 20, height: 20)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var subtitle: some View {
        if file.isDirectory {
            Text(L10n.tr("文件夹"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FilesDesign.subtitle)
        } else if file.size > 0 {
            Text(file.size.formattedFileSize)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FilesDesign.subtitle)
        } else {
                Text(file.type.filesDisplayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FilesDesign.subtitle)
        }
    }

    private func fileGlyph(name: String, color: Color) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(color)
    }
}

/// 按优先级依次尝试封面地址（海报 → 背景图），全部缺失或加载失败后再抽帧，最后显示占位图标。
private struct FilesCoverImage<Placeholder: View>: View {
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
        .task(id: CoverStepKey(candidates: candidates, step: step)) {
            guard step == candidates.count, extractedURL == nil, let extract else { return }
            extractedURL = await extract()
        }
    }

    private var currentURL: URL? {
        if step < candidates.count { return candidates[step] }
        return step == candidates.count ? extractedURL : nil
    }
}

private struct CoverStepKey: Hashable {
    let candidates: [URL]
    let step: Int
}

// MARK: - 网格卡片（Files-Grid）

private struct FolderGridTile: View {
    let name: String
    let isOpening: Bool
    let isLoading: Bool
    let reduceMotion: Bool
    @Environment(\.filesGridPressed) private var isPressed

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isPressed ? FilesDesign.folderBoxPressed : FilesDesign.folderBoxBackground)
                .aspectRatio(103.0 / 84.0, contentMode: .fit)
                .overlay {
                    Image(isOpening ? "FilesFolderOpen" : "FilesFolder")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .foregroundStyle(FilesDesign.accent)
                }
                .overlay(alignment: .topTrailing) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FilesDesign.accent)
                            .padding(8)
                    }
                }
                .scaleEffect(isOpening && !reduceMotion ? 1.08 : 1)

            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FilesDesign.title)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FileGridCard: View {
    let file: RemoteFile
    let artwork: [URL]
    let progress: FileWatchProgress?
    let extract: (() async -> URL?)?
    @Environment(\.filesGridPressed) private var isPressed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cover
            Text(file.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FilesDesign.title)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progressDescription)
    }

    private var cover: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if file.isVideo {
                    FilesCoverImage(candidates: artwork, extract: extract) { placeholderGlyph }
                } else {
                    placeholderGlyph
                }
            }
            .overlay(alignment: .bottom) { progressBar }
            .overlay(alignment: .topTrailing) { watchedBadge }
            .overlay {
                if isPressed { Color.black.opacity(0.15) }
            }
            .background(FilesDesign.iconBoxGray)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var placeholderGlyph: some View {
        if file.isVideo {
            Image("FilesFileVideo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(FilesDesign.secondaryIcon)
        } else {
            Image(systemName: file.type.filesSystemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(FilesDesign.secondaryIcon)
        }
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress, !progress.isWatched, progress.fraction > 0 {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.35))
                        Capsule()
                            .fill(FilesDesign.accent)
                            .frame(width: max(3, proxy.size.width * progress.fraction))
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private var watchedBadge: some View {
        if progress?.isWatched == true {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Color.black.opacity(0.55), in: Circle())
                .padding(6)
        }
    }

    private var progressDescription: String {
        guard let progress else { return "" }
        if progress.isWatched { return L10n.tr("已看完") }
        return L10n.tr("已观看 %d%%", Int((progress.fraction * 100).rounded()))
    }
}

// MARK: - 布局 & 过渡状态

private enum FilesBrowserLayout: String {
    case grid
    case list
}

private struct FolderTransitionState {
    var anchor: UnitPoint = .center
    var isForward = true
    /// 每进入一级记录被点文件夹的锚点，返回时内容收回到对应位置。
    var anchorStack: [UnitPoint] = []
}

/// 文件夹条目在内容区的位置。引用类型：滚动时更新不触发视图刷新。
private final class FilesTileFrameStore {
    var frames: [String: CGRect] = [:]
}

private extension View {
    func reportTileFrame(path: String?, in space: String, store: FilesTileFrameStore) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(space))
        } action: { frame in
            guard let path else { return }
            store.frames[path] = frame
        }
    }
}

/// 前进：新目录从被点文件夹处放大展开，旧目录轻微放大淡出；返回：反向收回。Reduce Motion 只淡入淡出。
private struct FolderOpenTransition: Transition {
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
        case .willAppear: return isForward ? 0.2 : 1.04
        case .didDisappear: return isForward ? 1.04 : 0.2
        }
    }
}

private struct FilesGridPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var filesGridPressed: Bool {
        get { self[FilesGridPressedKey.self] }
        set { self[FilesGridPressedKey.self] = newValue }
    }
}

private struct FilesGridButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.filesGridPressed, configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - IPTV 频道行卡片

private struct IPTVChannelCard: View {
    let channel: RemoteFile
    let epgGuide: EPGGuide
    let isLoadingEPG: Bool
    let isPlaybackFailed: Bool

    var body: some View {
        HStack(spacing: 0) {
            FilesIconBox(background: FilesDesign.iconBoxGray) {
                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                        } else {
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isPlaybackFailed ? FilesDesign.subtitle : FilesDesign.title)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isPlaybackFailed {
                    Text(L10n.tr("无法播放，请检查频道源"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let currentProgramTitle {
                    Text("正在播放：\(currentProgramTitle)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FilesDesign.subtitle)
                        .lineLimit(1)
                    if let nextProgramTitle {
                        Text("下一档：\(nextProgramTitle)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FilesDesign.subtitle)
                            .lineLimit(1)
                    }
                } else if isLoadingEPG, channel.tvgId?.isEmpty == false {
                    Text(L10n.tr("节目单加载中..."))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FilesDesign.subtitle)
                        .lineLimit(1)
                } else if let group = channel.groupTitle, !group.isEmpty {
                    Text(group)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FilesDesign.subtitle)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 16)

            Spacer(minLength: 8)

            Image(systemName: "play.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(isPlaybackFailed ? FilesDesign.subtitle : FilesDesign.accent)
                .frame(width: 20, height: 20)
        }
        .padding(12)
        .opacity(isPlaybackFailed ? 0.65 : 1)
    }

    private var currentProgramTitle: String? {
        guard let channelId = channel.tvgId, !channelId.isEmpty else { return nil }
        return normalizedProgramTitle(epgGuide.current(for: channelId)?.title)
    }

    private var nextProgramTitle: String? {
        guard let channelId = channel.tvgId, !channelId.isEmpty else { return nil }
        return normalizedProgramTitle(epgGuide.next(for: channelId)?.title)
    }

    private func normalizedProgramTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var placeholderIcon: some View {
        Image(systemName: "tv")
            .resizable()
            .scaledToFit()
            .frame(width: 24, height: 24)
            .foregroundStyle(FilesDesign.secondaryIcon)
    }
}

// MARK: - 公共子组件

private struct FilesIconBox<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: 48, height: 48)
            .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FilesRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isPressed ? FilesDesign.pressedHighlight : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct FilesMessageView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(FilesDesign.connectionDot)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FilesDesign.title)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FilesDesign.subtitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - 类型映射

private extension RemoteFileType {
    var filesDisplayName: String {
        switch self {
        case .video:     return L10n.tr("视频")
        case .subtitle:  return L10n.tr("字幕")
        case .audio:     return L10n.tr("音频")
        case .image:     return L10n.tr("图片")
        case .directory: return L10n.tr("文件夹")
        case .other:     return L10n.tr("文件")
        }
    }

    var filesSystemImage: String {
        switch self {
        case .video:     return "film"
        case .subtitle:  return "captions.bubble"
        case .audio:     return "music.note"
        case .image:     return "photo"
        case .directory: return "folder"
        case .other:     return "doc"
        }
    }
}

// MARK: - Typealias for backward compatibility

typealias BrowserView = ConnectionsView

#Preview("Light") {
    NavigationStack {
        ConnectionsView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        ConnectionsView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}

#Preview("Grid states") {
    let video = RemoteFile(name: "Dune Prophecy S01E01.mkv", path: "/v1", size: 1, isDirectory: false, modifiedDate: nil, type: .video)
    let subtitle = RemoteFile(name: "Dune Prophecy S01E01.srt", path: "/s1", size: 1, isDirectory: false, modifiedDate: nil, type: .subtitle)
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 16) {
        FolderGridTile(name: "Specials", isOpening: false, isLoading: false, reduceMotion: false)
        FolderGridTile(name: "Extras", isOpening: true, isLoading: true, reduceMotion: false)
        FolderGridTile(name: "A very long folder name that wraps", isOpening: false, isLoading: false, reduceMotion: false)
        FileGridCard(file: video, artwork: [], progress: FileWatchProgress(fraction: 0.42, isWatched: false), extract: nil)
        FileGridCard(file: video, artwork: [], progress: FileWatchProgress(fraction: 1, isWatched: true), extract: nil)
        FileGridCard(file: subtitle, artwork: [], progress: nil, extract: nil)
    }
    .padding(16)
    .background(FilesDesign.background)
}
