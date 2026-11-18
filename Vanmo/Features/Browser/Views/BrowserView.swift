import SwiftUI
import SwiftData
import VanmoCore

struct ConnectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: ConnectionsViewModel
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var enteredConnectionID: UUID?
    @State private var editingConnection: SavedConnection?
    @State private var showDirectLinks = false
    @AppStorage("files.browserLayout") private var layoutRaw = FilesBrowserLayout.grid.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openingFolderPath: String?
    @State private var isNavigatingDirectory = false
    @State private var folderTransition = FolderTransitionState()
    @State private var tileFrames = FilesTileFrameStore()
    @State private var contentSize: CGSize = .zero
#if DEBUG
    private static var didRunDebugSourceAcceptance = false
#endif

    var body: some View {
        ZStack(alignment: .top) {
            CatDesign.bgObsidian.ignoresSafeArea()

            ambientHalo

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
        .sheet(isPresented: $showDirectLinks) {
            DirectLinkView()
        }
    }

    @ViewBuilder
    private var ambientHalo: some View {
        if enteredConnectionID == nil {
            HStack {
                Spacer()
                CatAmberHalo(width: 170, height: 110, opacity: 0.22)
                    .padding(.top, 95)
                    .padding(.trailing, 16)
            }
            .ignoresSafeArea()
        } else {
            HStack {
                CatAmberHalo(width: 220, height: 80, opacity: 0.18)
                    .padding(.top, 70)
                    .padding(.leading, 40)
                Spacer()
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - 根页：连接列表（`03 · Files Sources Hub`）

    private var onlineCount: Int {
        viewModel.savedConnections.filter { isConnectionOnline($0) }.count
    }

    private func isConnectionOnline(_ connection: SavedConnection) -> Bool {
        viewModel.connectionErrorMessage(for: connection) == nil && connection.lastConnectedAt != nil
    }

    private var connectionsRoot: some View {
        VStack(spacing: 0) {
            hubHeader

            if viewModel.savedConnections.isEmpty {
                ScrollView(showsIndicators: false) {
                    emptySourcesCard
                        .padding(.horizontal, CatDesign.horizontalMargin)
                        .padding(.top, 24)
                        .padding(.bottom, 110)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("已连接与云端 · %d 在线", onlineCount))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(CatDesign.textMuted)
                            .padding(.top, 14)

                        ForEach(Array(viewModel.savedConnections.enumerated()), id: \.element.id) { index, connection in
                            connectionRow(connection, isFirst: index == 0)
                                .padding(.top, index == 0 ? 28 : 0)
                        }
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                    .padding(.bottom, 110)
                }
            }
        }
    }

    private var hubHeader: some View {
        HStack(spacing: 8) {
            Text(L10n.tr("文件"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)

            Spacer(minLength: 8)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showDirectLinks = true
            } label: {
                HStack(spacing: 5) {
                    Image("CatDirectUrlLink")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 15, height: 15)
                        .foregroundStyle(CatDesign.textIvory)

                    Text(L10n.tr("直链"))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(CatDesign.textIvory)
                }
                .padding(.horizontal, 11)
                .frame(height: 34)
                .catGlassCard(cornerRadius: CatDesign.radiusPill)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("files.openURL")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.showAddConnection = true
            } label: {
                HStack(spacing: 5) {
                    Image("CatAddSourceIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)

                    Text(L10n.tr("添加来源"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                }
                .padding(.leading, 11)
                .padding(.trailing, 12)
                .frame(height: 34)
                .catGlassCard(cornerRadius: CatDesign.radiusPill, elevated: true, amberStroke: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("files.addConnection")
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var emptySourcesCard: some View {
        Button {
            viewModel.showAddConnection = true
        } label: {
            HStack(spacing: 12) {
                Image("CatSittingInFolderBox")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 74)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("暂无文件来源"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CatDesign.textIvory)

                    Text(L10n.tr("连接 Emby、Jellyfin、Plex、SMB 或云盘即可开始浏览。"))
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(CatDesign.surfaceGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        CatDesign.strokeGlass,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func connectionRow(_ connection: SavedConnection, isFirst: Bool) -> some View {
        Button {
            enter(connection)
        } label: {
            CatStorageSourceCard(
                connection: connection,
                isOnline: isConnectionOnline(connection),
                errorMessage: viewModel.connectionErrorMessage(for: connection)
            )
        }
        .buttonStyle(CatRowPressStyle())
        .overlay(alignment: .topTrailing) {
            if isFirst {
                Image("CatPeekingServerCorner")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 50)
                    .offset(x: -16, y: -37)
                    .allowsHitTesting(false)
            }
        }
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

    // MARK: - 浏览页：文件夹 / 视频（`04 · Media Folder Browser`）

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
            browserTopBar

            ScanSyncBanner(
                coordinator: viewModel.scanCoordinator,
                onPause: { viewModel.pauseScan() },
                onResume: { viewModel.resumeScan() },
                onCancel: { viewModel.cancelScan() }
            )

            browserContent
        }
    }

    private var browserTopBar: some View {
        HStack(spacing: 10) {
            CatBackButton(size: 36, action: handleBack)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.selectedConnection?.name ?? L10n.tr("文件"))
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)

                Text(browserTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isNavigatingDirectory && viewModel.isBrowsingFiles && openingFolderPath == nil {
                ProgressView()
                    .controlSize(.small)
                    .tint(CatDesign.accentAmber)
            }

            if !isIPTVBrowsing {
                viewModeTogglePill
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
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)
                    .frame(width: 36, height: 36)
                    .catGlassCard(cornerRadius: CatDesign.radiusPill)
            }
            .accessibilityLabel(L10n.tr("更多操作"))
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var viewModeTogglePill: some View {
        HStack(spacing: 4) {
            modeToggleButton(target: .grid, assetName: "CatGridToggle", label: L10n.tr("切换为网格"))
            modeToggleButton(target: .list, assetName: "CatListToggle", label: L10n.tr("切换为列表"))
        }
        .padding(4)
        .frame(height: 36)
        .catGlassCard(cornerRadius: CatDesign.radiusPill)
        .accessibilityIdentifier("files.layoutToggle")
    }

    private func modeToggleButton(target: FilesBrowserLayout, assetName: String, label: String) -> some View {
        let isActive = layout == target
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                layoutRaw = target.rawValue
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(isActive ? CatDesign.accentAmber : CatDesign.textMuted)
                    .frame(width: 32, height: 28)
                    .background(
                        isActive ? CatDesign.amberTintFill : .clear,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(isActive ? CatDesign.strokeAmber : .clear, lineWidth: 0.75)
                    )

                if isActive {
                    Image("CatPawDot")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 10, height: 10)
                        .foregroundStyle(CatDesign.accentAmber)
                        .offset(x: 1, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var browserContent: some View {
        if viewModel.isBrowsingFiles && !isNavigatingDirectory {
            VStack(spacing: 10) {
                ProgressView()
                    .tint(CatDesign.accentAmber)
                Text(L10n.tr("正在加载目录..."))
                    .font(.subheadline)
                    .foregroundStyle(CatDesign.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.fileBrowserErrorMessage {
            CatFilesMessageView(icon: "exclamationmark.triangle", title: L10n.tr("无法加载目录"), message: message)
        } else if viewModel.files.isEmpty {
            if isIPTVBrowsing {
                CatFilesMessageView(icon: "tv.slash", title: L10n.tr("暂无频道"), message: L10n.tr("播放列表为空或无法解析，请检查 M3U 源后点击右上角刷新"))
            } else {
                CatFilesMessageView(icon: "folder", title: L10n.tr("文件夹为空"), message: L10n.tr("此目录下没有可显示的文件"))
            }
        } else if isIPTVBrowsing {
            iptvChannelList
        } else {
            directoryContainer
        }
    }

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
                VStack(spacing: 8) {
                    ForEach(viewModel.files) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, CatDesign.horizontalMargin)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
        }
        .refreshable {
            await viewModel.refreshCurrentDirectory()
        }
    }

    private var gridListing: some View {
        let folders = viewModel.files.filter(\.isDirectory)
        let items = viewModel.files.filter { !$0.isDirectory }
        return VStack(alignment: .leading, spacing: 14) {
            if !folders.isEmpty {
                Text("\(L10n.tr("文件夹").uppercased()) · \(folders.count)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)

                LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                    ForEach(folders) { folder in
                        folderGridTile(folder)
                    }
                }
            }
            if !items.isEmpty {
                HStack {
                    let heading = items.allSatisfy(\.isVideo) ? L10n.tr("视频") : L10n.tr("文件")
                    Text("\(heading.uppercased()) · \(items.count)")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textMuted)

                    Spacer()

                    CatStretchingDivider()
                }
                .padding(.top, folders.isEmpty ? 0 : 6)

                LazyVGrid(columns: Self.gridColumns, spacing: 12) {
                    ForEach(items) { file in
                        fileGridCard(file)
                    }
                }
            }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 14)
        .padding(.bottom, 110)
    }

    private func folderGridTile(_ folder: RemoteFile) -> some View {
        Button {
            openFolder(folder)
        } label: {
            CatFolderGridTile(
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
            CatFileGridCard(
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
            CatFileRowCard(
                file: file,
                isOpening: openingFolderPath == file.path,
                artwork: artworkCandidates(for: file),
                progress: watchProgress(for: file),
                extract: extractedFrameLoader(for: file)
            )
        }
        .buttonStyle(CatRowPressStyle())
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

    // MARK: - IPTV 频道

    private var isIPTVBrowsing: Bool {
        viewModel.selectedConnection?.type == .iptv
    }

    private var iptvChannelList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedChannels(viewModel.files), id: \.group) { section in
                    Section {
                        ForEach(section.channels) { channel in
                            iptvChannelRow(channel)
                        }
                    } header: {
                        Text(section.group.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CatDesign.textMuted)
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.top, 10)
            .padding(.bottom, 110)
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
        .buttonStyle(CatRowPressStyle())
    }

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
        if let name = viewModel.displayName(forPath: viewModel.currentPath) { return name }
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
            if item.serverId == nil { item.serverId = file.path }
            if item.sourceConnectionId == nil { item.sourceConnectionId = viewModel.selectedConnection?.id }
            if item.originalFileName == nil { item.originalFileName = file.name }
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

// MARK: - 源卡片 & 文件夹 / 视频卡

private struct CatStorageSourceCard: View {
    let connection: SavedConnection
    let isOnline: Bool
    let errorMessage: String?

    private var subtitleText: String {
        if let errorMessage, !errorMessage.isEmpty {
            return errorMessage
        }
        let target = connection.host.isEmpty ? (connection.path ?? "") : connection.host
        if target.isEmpty {
            return connection.type.displayName
        }
        return "\(connection.type.displayName) · \(target)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: CatDesign.radiusSquircleSm, style: .continuous)
                    .fill(isOnline ? CatDesign.amberTintFill : CatDesign.surfacePill)
                RoundedRectangle(cornerRadius: CatDesign.radiusSquircleSm, style: .continuous)
                    .strokeBorder(isOnline ? CatDesign.strokeAmber : CatDesign.strokeGlass, lineWidth: 0.75)

                Text(connection.type.catShortCode)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isOnline ? CatDesign.accentAmber : CatDesign.textMuted)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(errorMessage != nil ? CatDesign.dangerRed : CatDesign.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if isOnline {
                    Image("CatEyeStatus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 8)
                        .shadow(color: CatDesign.glowAmber.opacity(0.75), radius: 2)
                } else {
                    Circle()
                        .fill(errorMessage != nil ? CatDesign.dangerRed : CatDesign.textDim)
                        .frame(width: 6, height: 6)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .catGlassCard(cornerRadius: 20, amberStroke: false)
    }
}

private struct CatFolderGridTile: View {
    let name: String
    let isOpening: Bool
    let isLoading: Bool
    let reduceMotion: Bool
    @Environment(\.filesGridPressed) private var isPressed

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image("CatFolderTileAmber")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 22)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(CatDesign.accentAmber)
                }
            }

            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .catGlassCard(cornerRadius: 16, elevated: isPressed, amberStroke: isOpening)
        .scaleEffect(isOpening && !reduceMotion ? 1.04 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct CatFileGridCard: View {
    let file: RemoteFile
    let artwork: [URL]
    let progress: FileWatchProgress?
    let extract: (() async -> URL?)?
    @Environment(\.filesGridPressed) private var isPressed

    private var metaText: String {
        if let progress {
            if progress.isWatched {
                return file.size > 0 ? L10n.tr("已看完 · %@", file.size.formattedFileSize) : L10n.tr("已看完")
            }
            let pct = Int((progress.fraction * 100).rounded())
            return file.size > 0 ? "\(pct)% · \(file.size.formattedFileSize)" : "\(pct)%"
        }
        return file.size > 0 ? file.size.formattedFileSize : file.type.filesDisplayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverFrame
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metaText)
                    .font(.system(size: 10))
                    .foregroundStyle(progress?.isWatched == true ? CatDesign.accentAmber : CatDesign.textMuted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(progressDescription)
    }

    private var coverFrame: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if file.isVideo {
                    FilesCoverImage(candidates: artwork, extract: extract) { placeholderGlyph }
                } else {
                    placeholderGlyph
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, CatDesign.catSilhouette.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
            }
            .overlay(alignment: .bottom) {
                if let progress, !progress.isWatched, progress.fraction > 0 {
                    CatPawProgressBar(progress: progress.fraction, trackColor: Color.white.opacity(0.22))
                        .padding(.horizontal, 6)
                        .padding(.bottom, 5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if progress?.isWatched == true {
                    CatSleepingPillBadge()
                        .scaleEffect(0.75, anchor: .topTrailing)
                        .padding(5)
                }
            }
            .overlay {
                if isPressed { Color.black.opacity(0.18) }
            }
            .background(CatDesign.mediaPlaceholder)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.85)
            )
    }

    @ViewBuilder
    private var placeholderGlyph: some View {
        if file.isVideo {
            Image(systemName: "film")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CatDesign.textMuted.opacity(0.6))
        } else {
            Image(systemName: file.type.filesSystemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CatDesign.textMuted.opacity(0.6))
        }
    }

    private var progressDescription: String {
        guard let progress else { return "" }
        if progress.isWatched { return L10n.tr("已看完") }
        return L10n.tr("已观看 %d%%", Int((progress.fraction * 100).rounded()))
    }
}

private struct CatFileRowCard: View {
    let file: RemoteFile
    var isOpening = false
    var artwork: [URL] = []
    var progress: FileWatchProgress?
    var extract: (() async -> URL?)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(file.isDirectory ? CatDesign.amberTintFill : CatDesign.surfacePill)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(file.isDirectory ? CatDesign.strokeAmber : CatDesign.strokeGlass, lineWidth: 0.75)

                if file.isDirectory {
                    Image("CatFolderTileAmber")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 18)
                } else if file.isVideo {
                    FilesCoverImage(candidates: artwork, extract: extract) {
                        Image(systemName: "film")
                            .font(.system(size: 16))
                            .foregroundStyle(CatDesign.textMuted)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: file.type.filesSystemImage)
                        .font(.system(size: 16))
                        .foregroundStyle(CatDesign.textMuted)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(CatDesign.textIvory)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CatDesign.textDim)
            } else if progress?.isWatched == true {
                CatWatchedEarBadge(padding: 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .catGlassCard(cornerRadius: 16, amberStroke: isOpening)
    }

    private var subtitleText: String {
        if file.isDirectory { return L10n.tr("文件夹") }
        if file.size > 0 { return file.size.formattedFileSize }
        return file.type.filesDisplayName
    }
}

/// 按优先级依次尝试封面地址，全部缺失或加载失败后再抽帧。
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

// MARK: - 布局 & 过渡状态

private enum FilesBrowserLayout: String {
    case grid
    case list
}

private struct FolderTransitionState {
    var anchor: UnitPoint = .center
    var isForward = true
    var anchorStack: [UnitPoint] = []
}

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

private struct CatRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - IPTV 频道行卡片

private struct IPTVChannelCard: View {
    let channel: RemoteFile
    let epgGuide: EPGGuide
    let isLoadingEPG: Bool
    let isPlaybackFailed: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CatDesign.surfacePill)

                if let logoURL = channel.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                        } else {
                            placeholderIcon
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .frame(width: 44, height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CatDesign.strokeGlass, lineWidth: 0.75)
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(isPlaybackFailed ? CatDesign.textMuted : CatDesign.textIvory)
                    .lineLimit(1)

                if isPlaybackFailed {
                    Text(L10n.tr("无法播放，请检查频道源"))
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.dangerRed)
                        .lineLimit(1)
                } else if let currentProgramTitle {
                    Text("正在播放：\(currentProgramTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(1)
                } else if isLoadingEPG, channel.tvgId?.isEmpty == false {
                    Text(L10n.tr("节目单加载中..."))
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(1)
                } else if let group = channel.groupTitle, !group.isEmpty {
                    Text(group)
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image("CatPlaySmall")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .padding(7)
                .background(CatDesign.amberTintFill, in: Circle())
                .overlay(Circle().strokeBorder(CatDesign.strokeAmber, lineWidth: 0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .catGlassCard(cornerRadius: 16)
        .opacity(isPlaybackFailed ? 0.65 : 1)
    }

    private var currentProgramTitle: String? {
        guard let channelId = channel.tvgId, !channelId.isEmpty else { return nil }
        let trimmed = epgGuide.current(for: channelId)?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var placeholderIcon: some View {
        Image(systemName: "tv")
            .font(.system(size: 18))
            .foregroundStyle(CatDesign.textMuted)
    }
}

private struct CatFilesMessageView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(CatDesign.accentAmber)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CatDesign.textIvory)
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(CatDesign.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }
}

// MARK: - ConnectionType 协议短码

extension ConnectionType {
    var catShortCode: String {
        switch self {
        case .emby: return "EMB"
        case .jellyfin: return "JLY"
        case .plex: return "PLX"
        case .smb: return "SMB"
        case .ftp: return "FTP"
        case .sftp: return "SFT"
        case .webdav: return "DAV"
        case .alist: return "LST"
        case .fnos: return "FN"
        case .nfs: return "NFS"
        case .dlna: return "DLN"
        case .iptv: return "TV"
        case .googleDrive: return "GDR"
        case .oneDrive: return "ODV"
        case .box: return "BOX"
        case .pCloudDrive: return "PCL"
        case .yandexDisk: return "YDX"
        case .baiduNetdisk: return "BDN"
        case .localFolder: return "DIR"
        case .drive115: return "115"
        case .quarkDrive: return "QRK"
        case .mega: return "MGA"
        case .removedOfficialCloudDrive: return "OLD"
        }
    }

    var catShortHint: String {
        switch self {
        case .emby: return L10n.tr("媒体服务器")
        case .jellyfin: return L10n.tr("开源服务器")
        case .plex: return L10n.tr("PIN 授权")
        case .smb: return L10n.tr("局域网 / NAS")
        case .ftp: return L10n.tr("FTP 文件传输")
        case .sftp: return L10n.tr("SSH 文件传输")
        case .webdav: return L10n.tr("WebDAV 协议")
        case .alist: return L10n.tr("网盘聚合")
        case .fnos: return L10n.tr("飞牛 NAS")
        case .iptv: return L10n.tr("M3U 直播源")
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk:
            return "OAuth 2.0"
        case .baiduNetdisk:
            return L10n.tr("云端 OAuth")
        case .localFolder:
            return L10n.tr("本地目录书签")
        default:
            return L10n.tr("云端占位")
        }
    }
}

// MARK: - 兼容旧辅助声明（供 DirectLinkView Phase 5 之前过渡编译）

enum FilesDesign {
    static let background = CatDesign.bgObsidian
    static let headerBorder = CatDesign.hairSeparator
    static let title = CatDesign.textIvory
    static let sectionHeader = CatDesign.textMuted
    static let subtitle = CatDesign.textMuted
    static let accent = CatDesign.accentAmber
    static let addButtonBackground = CatDesign.amberTintFill
    static let iconBoxGray = CatDesign.surfacePill
    static let folderBoxBackground = CatDesign.amberTintFill
    static let folderBoxPressed = CatDesign.amberTintStrong
    static let statusConnected = CatDesign.accentAmber
    static let connectionDot = CatDesign.textDim
    static let videoDot = CatDesign.textDim
    static let secondaryIcon = CatDesign.textMuted
    static let chevron = CatDesign.textDim
    static let pressedHighlight = CatDesign.surfacePill

    static func dyn(_ light: String, _ dark: String, _ lightAlpha: Double = 1, _ darkAlpha: Double = 1) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let base = Color(hex: isDark ? dark : light) ?? .clear
            return UIColor(base).withAlphaComponent(isDark ? darkAlpha : lightAlpha)
        })
    }
}

struct FilesHeader<Trailing: View>: View {
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
                CatBackButton(size: 36, action: onBack)
            }
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(CatDesign.textIvory)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(spacing: 8) { trailing() }
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

struct FilesSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(CatDesign.textMuted)
    }
}

struct FilesIconBox<Content: View>: View {
    let background: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .frame(width: 44, height: 44)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

typealias BrowserView = ConnectionsView

#Preview("Light") {
    NavigationStack {
        ConnectionsView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        ConnectionsView()
    }
    .environmentObject(AppState())
    .environmentObject(ConnectionsViewModel())
    .environmentObject(DownloadManager.shared)
    .preferredColorScheme(.dark)
}
