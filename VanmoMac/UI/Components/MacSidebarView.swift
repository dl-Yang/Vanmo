import AppKit
import SwiftData
import SwiftUI
import VanmoCore

struct MacSearchField: View {
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.macTheme) private var theme
    @FocusState private var isFocused: Bool

    @Binding var text: String
    var onFocus: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image("MacSearchCat")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(isFocused ? theme.accentAmber : theme.secondaryText)

            TextField(L10n.tr("搜索"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.primaryText)
                .focused($isFocused)
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
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘F")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(theme.surfacePill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(theme.searchBackground, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.searchField, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.searchField, style: .continuous)
                .strokeBorder(isFocused ? theme.strokeAmber : theme.searchBorder, lineWidth: 0.9)
        }
        .onChange(of: appState.searchFocusNonce) { _, _ in
            isFocused = true
        }
    }
}

struct MacSidebarRow: View {
    @Environment(\.macTheme) private var theme

    let title: String
    let iconAssetName: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(iconAssetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? theme.accentAmber : theme.secondaryText)

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.sidebarItemText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    MacPawDotIndicator(size: 10)
                }
            }
            .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
            .frame(height: MacDesignTokens.Layout.sidebarRowHeight)
            .background(
                rowBackground,
                in: RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
                        .strokeBorder(theme.strokeAmber, lineWidth: 0.85)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected { return theme.amberTintFill }
        if isHovered { return theme.surfaceRowSubtle }
        return .clear
    }
}

struct MacConnectionSidebarRow: View {
    @Environment(\.macTheme) private var theme
    @ObservedObject var connectionsViewModel: MacConnectionsViewModel

    let connection: SavedConnection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var status: MacConnectionStatus {
        connectionsViewModel.connectionStatus(for: connection)
    }

    private var isConnectedOrSelected: Bool {
        status == .connected || isSelected
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                protocolBadge

                VStack(alignment: .leading, spacing: 1) {
                    Text(connection.name)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isConnectedOrSelected ? theme.primaryText : theme.secondaryText)
                        .lineLimit(1)

                    if status == .failed {
                        Text(L10n.tr("连接失败"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.dangerRed)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                statusIndicator
            }
            .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
            .frame(minHeight: MacDesignTokens.Layout.sidebarRowHeight)
            .background(
                rowBackground,
                in: RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
                        .strokeBorder(theme.strokeAmber, lineWidth: 0.85)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(status == .failed ? 0.82 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var rowBackground: Color {
        if isSelected { return theme.amberTintFill }
        if isHovered { return theme.surfaceRowSubtle }
        return .clear
    }

    private var protocolBadge: some View {
        Text(connection.type.macShortBadge)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(isConnectedOrSelected ? theme.accentAmber : theme.secondaryText)
            .frame(width: 22, height: 22)
            .background(
                isConnectedOrSelected ? theme.amberTintFill : theme.surfacePill,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isConnectedOrSelected ? theme.strokeAmber : theme.strokeGlass, lineWidth: 0.75)
            }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .connecting:
            ProgressView()
                .controlSize(.mini)
        case .connected:
            Image("MacCatEyeStatus")
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 7)
                .shadow(color: MacDesignTokens.glowAmber.opacity(0.75), radius: 2)
                .accessibilityLabel(L10n.tr("已连接"))
                .help(L10n.tr("已连接"))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.dangerRed)
                .help(failureHelpText)
        case .idle:
            Circle()
                .fill(theme.tertiaryText.opacity(0.65))
                .frame(width: 5, height: 5)
                .help(L10n.tr("未连接"))
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
    @Query(sort: \SavedConnection.name) private var connections: [SavedConnection]
    @Query private var tombstones: [ConnectionTombstone]
    @Query(filter: #Predicate<MediaItem> { $0.sourceConnectionId == nil })
    private var connectionlessItems: [MediaItem]

    @State private var dragStartWidth: CGFloat?
    @State private var liveSidebarWidth: CGFloat?
    @State private var isResizeHandleHovered = false
    @State private var isSettingsHovered = false

    private var displayedSidebarWidth: CGFloat {
        liveSidebarWidth ?? appState.sidebarWidth
    }

    private var showsDirectLinksRow: Bool {
        appState.contentRoute == .directLinks || connectionlessItems.contains(where: DirectLinkLibrary.isDirectLink)
    }

    private var visibleConnections: [SavedConnection] {
        let hiddenIDs = Set(
            tombstones.compactMap { tombstone in
                tombstone.deviceId == CloudSyncDevice.id ? tombstone.connectionId : nil
            }
        )
        return ConnectionVisibility.visibleConnections(from: connections, hiddenIDs: hiddenIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部留空给交通灯与悬浮 Downloads / Collapse 按钮
            Color.clear
                .frame(height: MacDesignTokens.Layout.sidebarControlRowHeight)

            MacSearchField(text: $searchViewModel.searchText) {
                appState.selectSearch()
                searchViewModel.search()
            }
            .padding(.horizontal, MacDesignTokens.Layout.sidebarHorizontalPadding)
            .padding(.top, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("媒体库").uppercased())
                        .font(MacDesignTokens.Typography.sidebarSection)
                        .foregroundStyle(theme.sectionHeader)
                        .tracking(0.6)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                    ForEach(MacSidebarSection.allCases) { section in
                        MacSidebarRow(
                            title: section.title,
                            iconAssetName: section.catIconName,
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

                        Menu {
                            Button {
                                appState.presentAddConnection()
                            } label: {
                                Label(L10n.tr("添加连接…"), systemImage: "server.rack")
                            }
                            Button {
                                appState.openDirectLinks()
                            } label: {
                                Label(L10n.tr("打开 URL 链接…"), systemImage: "link")
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image("MacPlusCat")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 14, height: 14)
                                    .foregroundStyle(theme.accentAmber)
                                Text("▾")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .padding(.leading, 6)
                        .padding(.trailing, 7)
                        .frame(height: 22)
                        .background(theme.surfacePill, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.75)
                        }
                        .fixedSize()
                        .help(L10n.tr("添加"))
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 6)

                    ForEach(visibleConnections) { connection in
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

                    if showsDirectLinksRow {
                        directLinksSidebarRow
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

    private var directLinksSidebarRow: some View {
        let isSelected = appState.contentRoute == .directLinks && appState.selectedMediaItem == nil
        return Button {
            appState.openDirectLinks()
        } label: {
            HStack(spacing: 9) {
                Text("URL")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(theme.accentAmber)
                    .frame(width: 22, height: 22)
                    .background(theme.amberTintFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(theme.strokeAmber, lineWidth: 0.75)
                    }

                Text(L10n.tr("URL 链接"))
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image("MacCatEyeStatus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 7)
                    .shadow(color: MacDesignTokens.glowAmber.opacity(0.75), radius: 2)
            }
            .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
            .frame(height: MacDesignTokens.Layout.sidebarRowHeight)
            .background(
                isSelected ? theme.amberTintFill : Color.clear,
                in: RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
                        .strokeBorder(theme.strokeAmber, lineWidth: 0.85)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarResizeHandle: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(isResizeHandleHovered || liveSidebarWidth != nil ? theme.strokeAmber : Color.clear)
                    .frame(width: 1.5)
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
        VStack(spacing: 10) {
            Rectangle()
                .fill(theme.strokeSubtle)
                .frame(height: 0.75)

            Button {
                openSettings()
            } label: {
                HStack(spacing: 10) {
                    Image("MacSettingsYarn")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(isSettingsHovered ? theme.accentAmber : theme.secondaryText)

                    Text(L10n.tr("设置"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSettingsHovered ? theme.primaryText : theme.sidebarItemText)

                    Spacer(minLength: 0)

                    Text("⌘,")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
                .frame(height: 36)
                .background(
                    isSettingsHovered ? theme.surfaceRowSubtle : Color.clear,
                    in: RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius, style: .continuous)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isSettingsHovered = $0 }
        }
        .padding(.horizontal, MacDesignTokens.Layout.sidebarHorizontalPadding)
        .padding(.bottom, 14)
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

extension ConnectionType {
    var macShortBadge: String {
        switch self {
        case .emby: return "EMB"
        case .jellyfin: return "JLY"
        case .plex: return "PLX"
        case .smb: return "SMB"
        case .ftp: return "FTP"
        case .sftp: return "SFT"
        case .webdav: return "DAV"
        case .alist: return "ALS"
        case .fnos: return "FNO"
        case .nfs: return "NFS"
        case .dlna: return "DLN"
        case .iptv: return "IPT"
        case .googleDrive: return "GDR"
        case .oneDrive: return "OND"
        case .box: return "BOX"
        case .baiduNetdisk: return "BDN"
        case .pCloudDrive: return "PCL"
        case .yandexDisk: return "YND"
        case .drive115: return "115"
        case .quarkDrive: return "QRK"
        case .mega: return "MGA"
        case .localFolder: return "LCL"
        case .removedOfficialCloudDrive: return "ALI"
        }
    }
}
