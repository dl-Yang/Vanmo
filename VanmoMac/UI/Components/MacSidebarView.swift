import SwiftData
import SwiftUI
import AppKit
import VanmoCore

struct MacSearchField: View {
    @Environment(\.macTheme) private var theme

    @Binding var text: String
    var onFocus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.searchPlaceholder)
                .padding(.leading, 10)

            TextField(L10n.tr("搜索"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(theme.primaryText)
                .onSubmit(onFocus)
                .onChange(of: text) { _, newValue in
                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onFocus()
                    }
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.searchPlaceholder)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 28)
        .background(theme.searchBackground)
        .overlay {
            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.searchField)
                .stroke(theme.searchBorder, lineWidth: theme.searchBorder == .clear ? 0 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.searchField))
    }
}

struct MacSidebarRow: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(MacDesignTokens.Typography.sidebarItem)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? theme.sidebarSelectedText : theme.sidebarItemText)
            .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
            .frame(height: MacDesignTokens.Layout.sidebarRowHeight)
            .background(isSelected ? theme.sidebarSelectedBackground : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius))
        }
        .buttonStyle(.plain)
    }
}

struct MacConnectionSidebarRow: View {
    @Environment(\.macTheme) private var theme
    @ObservedObject var connectionsViewModel: MacConnectionsViewModel

    let connection: SavedConnection
    let isSelected: Bool
    let action: () -> Void

    private var status: MacConnectionStatus {
        connectionsViewModel.connectionStatus(for: connection)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let imageName = connection.type.macSidebarImageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: connection.type.macSidebarIcon)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(MacDesignTokens.Typography.sidebarItem)
                        .lineLimit(1)
                    if status == .failed {
                        Text(L10n.tr("连接失败"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                statusIndicator
            }
            .foregroundStyle(isSelected ? theme.sidebarSelectedText : theme.sidebarItemText)
            .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
            .frame(minHeight: MacDesignTokens.Layout.sidebarRowHeight)
            .background(isSelected ? theme.sidebarSelectedBackground : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius))
        }
        .buttonStyle(.plain)
        .opacity(status == .failed ? 0.72 : 1)
        .help(failureHelpText)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
                .help(failureHelpText)
        default:
            EmptyView()
        }
    }

    private var failureHelpText: String {
        guard status == .failed else { return "" }
        return connectionsViewModel.connectionErrorMessage(for: connection) ?? L10n.tr("连接失败")
    }
}

struct MacSidebarView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @Environment(\.macTheme) private var theme
    @Environment(\.openSettings) private var openSettings
    @Query(
        filter: #Predicate<SavedConnection> { $0.deletedAt == nil },
        sort: \SavedConnection.name
    ) private var connections: [SavedConnection]

    @State private var dragStartWidth: CGFloat?
    @State private var liveSidebarWidth: CGFloat?
    @State private var isResizeHandleHovered = false

    private var displayedSidebarWidth: CGFloat {
        liveSidebarWidth ?? appState.sidebarWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 展开/折叠控制行已移出为顶部悬浮层，这里保留等高占位避免内容位置变化。
            Color.clear
                .frame(height: MacDesignTokens.Layout.sidebarControlRowHeight)

            MacSearchField(text: $searchViewModel.searchText) {
                appState.selectSearch()
                searchViewModel.search()
            }

            Spacer(minLength: 12)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(MacSidebarSection.allCases) { section in
                        MacSidebarRow(
                            title: section.title,
                            systemImage: section.systemImage,
                            isSelected: isLibrarySectionSelected(section)
                        ) {
                            appState.selectLibrarySection(section)
                        }
                    }

                    HStack {
                        Text(L10n.tr("连接").uppercased())
                            .font(MacDesignTokens.Typography.sidebarSection)
                            .foregroundStyle(theme.sectionHeader)
                            .tracking(0.6)

                        Spacer(minLength: 0)

                        Button {
                            appState.presentAddConnection()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.sectionHeader)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(L10n.tr("添加连接"))
                    }
                    .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding + 4)
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                    ForEach(connections) { connection in
                        MacConnectionSidebarRow(
                            connectionsViewModel: connectionsViewModel,
                            connection: connection,
                            isSelected: appState.activeConnectionId == connection.id
                        ) {
                            appState.enterConnectionBrowser(connection)
                            Task {
                                await connectionsViewModel.selectConnection(connection)
                            }
                        }
                        .contextMenu {
                            Button {
                                appState.presentEditConnection(connection)
                            } label: {
                                Label(L10n.tr("编辑"), systemImage: "pencil")
                            }
                            Button {
                                syncConnection(connection)
                            } label: {
                                Label(
                                    sidebarSyncLabel(for: connection),
                                    systemImage: sidebarSyncIcon(for: connection)
                                )
                            }
                            if !connection.type.requiresManualDirectorySync {
                                Button {
                                    Task { _ = await connectionsViewModel.syncAllBookmarks(for: connection) }
                                } label: {
                                    Label(L10n.tr("同步全部书签"), systemImage: "bookmark.circle")
                                }
                            }
                            if !connection.type.requiresManualDirectorySync {
                                Button {
                                    fullRescanConnection(connection)
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
                }
                .padding(.horizontal, MacDesignTokens.Layout.sidebarHorizontalPadding)
                .padding(.bottom, 16)
            }

            settingsFooter
        }
        .frame(width: displayedSidebarWidth)
        .background(theme.sidebarBackground)
        .overlay(alignment: .trailing) {
            sidebarResizeHandle
        }
    }

    private var sidebarResizeHandle: some View {
        // Hit target is local; width changes must not feed back into DragGesture
        // translation, or the sidebar will oscillate while dragging.
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(isResizeHandleHovered || liveSidebarWidth != nil
                          ? theme.primaryText.opacity(0.28)
                          : theme.primaryText.opacity(0.08))
                    .frame(width: 1)
            }
            .onHover { hovering in
                isResizeHandleHovered = hovering
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else if liveSidebarWidth == nil {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = appState.sidebarWidth
                        }
                        guard let dragStartWidth else { return }
                        // Global delta stays stable even as the handle moves with width.
                        let delta = value.location.x - value.startLocation.x
                        let nextWidth = MacAppState.clampedSidebarWidth(dragStartWidth + delta)
                        guard liveSidebarWidth != nextWidth else {
                            NSCursor.resizeLeftRight.set()
                            return
                        }
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            liveSidebarWidth = nextWidth
                        }
                        NSCursor.resizeLeftRight.set()
                    }
                    .onEnded { _ in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            if let liveSidebarWidth {
                                appState.sidebarWidth = liveSidebarWidth
                            }
                            dragStartWidth = nil
                            self.liveSidebarWidth = nil
                        }
                        if !isResizeHandleHovered {
                            NSCursor.arrow.set()
                        }
                    }
            )
    }

    private var settingsFooter: some View {
        MacSidebarRow(
            title: L10n.tr("设置"),
            systemImage: "gearshape",
            isSelected: false
        ) {
            openSettings()
        }
        .padding(.horizontal, MacDesignTokens.Layout.sidebarHorizontalPadding)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.sidebarBorder)
                .frame(height: 1)
        }
    }

    private func sidebarSyncLabel(for connection: SavedConnection) -> String {
        if connection.type.requiresManualDirectorySync {
            return connectionsViewModel.selectedConnection?.id == connection.id
                ? L10n.tr("同步当前目录")
                : L10n.tr("连接")
        }
        return L10n.tr("同步到媒体库")
    }

    private func sidebarSyncIcon(for connection: SavedConnection) -> String {
        if connection.type.requiresManualDirectorySync {
            return connectionsViewModel.selectedConnection?.id == connection.id
                ? "square.and.arrow.down"
                : "link"
        }
        return "arrow.triangle.2.circlepath"
    }

    private func syncConnection(_ connection: SavedConnection) {
        Task {
            if connection.type.requiresManualDirectorySync,
               connectionsViewModel.selectedConnection?.id == connection.id {
                _ = await connectionsViewModel.scanCurrentDirectory()
            } else {
                _ = await connectionsViewModel.connectAndScan(connection)
            }
        }
    }

    private func fullRescanConnection(_ connection: SavedConnection) {
        Task {
            if connection.type.requiresManualDirectorySync,
               connectionsViewModel.selectedConnection?.id == connection.id {
                _ = await connectionsViewModel.scanCurrentDirectory(forceFullScan: true)
            } else if connection.type.requiresManualDirectorySync {
                _ = await connectionsViewModel.connectAndScan(connection)
            } else {
                _ = await connectionsViewModel.connectAndScan(connection, forceFullScan: true)
            }
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
    private func isLibrarySectionSelected(_ section: MacSidebarSection) -> Bool {
        guard appState.selectedMediaItem == nil else { return false }
        switch appState.contentRoute {
        case .library:
            return appState.selectedSection == section
        case .libraryFavorites:
            return section == .favorites
        case .libraryHistory:
            return section == .history
        default:
            return false
        }
    }
}

private extension ConnectionType {
    var macSidebarImageName: String? {
        switch self {
        case .localFolder: return "MacConnLocalFolder"
        case .smb: return "MacConnSMB"
        case .ftp: return "MacConnFTP"
        case .sftp: return "MacConnSFTP"
        case .webdav: return "MacConnWebDAV"
        case .alist: return "MacConnAList"
        case .removedOfficialCloudDrive: return "MacConnAliyunDrive"
        case .baiduNetdisk: return "MacConnBaiduNetdisk"
        case .drive115: return "MacConnDrive115"
        case .quarkDrive: return "MacConnQuarkDrive"
        case .googleDrive: return "MacConnGoogleDrive"
        case .oneDrive: return "MacConnOneDrive"
        case .box: return "MacConnBox"
        case .pCloudDrive: return "MacConnPCloud"
        case .yandexDisk: return "MacConnYandexDisk"
        case .mega: return "MacConnMEGA"
        case .iptv: return "MacConnIPTV"
        case .fnos: return "MacConnFnOS"
        case .nfs: return "MacConnNFS"
        case .dlna: return "MacConnDLNA"
        case .plex: return "MacConnPlex"
        case .emby: return "MacConnEmby"
        case .jellyfin: return "MacConnJellyfin"
        }
    }

    var macSidebarIcon: String {
        switch self {
        case .localFolder:
            return "folder"
        case .googleDrive, .oneDrive, .box, .pCloudDrive, .yandexDisk, .mega, .baiduNetdisk, .drive115, .quarkDrive:
            return "icloud"
        default:
            return "externaldrive"
        }
    }
}
