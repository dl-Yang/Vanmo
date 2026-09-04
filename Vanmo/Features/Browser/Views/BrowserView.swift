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

    // MARK: - 浏览页：文件夹 / 视频列表（Files-Folders(-Videos)-Light）

    private var fileBrowser: some View {
        VStack(spacing: 0) {
            FilesHeader(title: browserTitle, onBack: handleBack) {
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

    @ViewBuilder
    private var browserContent: some View {
        if viewModel.isBrowsingFiles {
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
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(viewModel.files) { file in
                        fileRow(file)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .refreshable {
                await viewModel.refreshCurrentDirectory()
            }
        }
    }

    private func fileRow(_ file: RemoteFile) -> some View {
        Button {
            Task { await handleFileTap(file) }
        } label: {
            FileCard(file: file)
        }
        .buttonStyle(FilesRowButtonStyle())
        .contextMenu {
            if file.isDirectory {
                Button {
                    Task { await viewModel.openDirectory(file) }
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
        guard let name = env["VANMO_DEBUG_OPEN_CONNECTION"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }
        guard let connection = viewModel.savedConnections.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            print("[Debug][FTP] accept missing connection name=\(name)")
            return
        }
        enter(connection)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        var video = viewModel.files.first(where: \.isVideo)
        if video == nil, let folder = viewModel.files.first(where: \.isDirectory) {
            await viewModel.openDirectory(folder)
            video = viewModel.files.first(where: \.isVideo)
        }
        let actions = Set(
            (env["VANMO_DEBUG_ACCEPT_ACTIONS"] ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        print("[Debug][FTP] accept listed=\(viewModel.files.count) hasVideo=\(video != nil) actions=\(actions.sorted().joined(separator: ","))")
        guard let video else { return }
        if actions.contains("play") {
            await play(video)
        }
        if actions.contains("download") {
            await download(video, connection: connection)
        }
    }
#endif

    private func enter(_ connection: SavedConnection) {
        withAnimation(.easeInOut(duration: 0.25)) {
            enteredConnectionID = connection.id
        }
        Task { await viewModel.selectConnection(connection) }
    }

    private func openPendingFolderBookmarkIfNeeded() async {
        guard let request = viewModel.pendingFolderBookmarkNavigation else { return }
        await MainActor.run {
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
            Task { await viewModel.goBackDirectory() }
        }
    }

    // MARK: - 文件操作

    private func handleFileTap(_ file: RemoteFile) async {
        if file.isDirectory {
            await viewModel.openDirectory(file)
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
            appState.play(item)
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
            print("[Debug][Downloads] enqueued source=browser connection=\(connection.type.rawValue)")
#endif
        } catch {
#if DEBUG
            let nsError = error as NSError
            print("[Debug][Downloads] enqueue failed source=browser domain=\(nsError.domain) code=\(nsError.code)")
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

    var body: some View {
        HStack(spacing: 0) {
            FilesIconBox(background: file.isDirectory ? FilesDesign.folderBoxBackground : FilesDesign.iconBoxGray) {
                Image(file.isDirectory ? "FilesFolder" : "FilesFileVideo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(file.isDirectory ? FilesDesign.accent : FilesDesign.secondaryIcon)
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
