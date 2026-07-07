import SwiftData
import SwiftUI
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

            TextField("Search", text: $text)
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
                Image(systemName: connection.type.macSidebarIcon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 16, height: 16)
                Text(connection.name)
                    .font(MacDesignTokens.Typography.sidebarItem)
                    .lineLimit(1)
                Spacer(minLength: 0)
                statusIndicator
            }
            .foregroundStyle(isSelected ? theme.sidebarSelectedText : theme.sidebarItemText)
            .padding(.horizontal, MacDesignTokens.Layout.sidebarItemPadding)
            .frame(height: MacDesignTokens.Layout.sidebarRowHeight)
            .background(isSelected ? theme.sidebarSelectedBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Layout.sidebarRowRadius))
        }
        .buttonStyle(.plain)
        .opacity(status == .failed ? 0.5 : 1)
        .help(failureHelpText)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .failed:
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
        default:
            EmptyView()
        }
    }

    private var failureHelpText: String {
        guard status == .failed else { return "" }
        return connectionsViewModel.connectionErrorMessage(for: connection) ?? "连接失败"
    }
}

struct MacSidebarView: View {
    @EnvironmentObject private var appState: MacAppState
    @EnvironmentObject private var connectionsViewModel: MacConnectionsViewModel
    @EnvironmentObject private var libraryViewModel: MacLibraryViewModel
    @EnvironmentObject private var searchViewModel: MacSearchViewModel
    @Environment(\.macTheme) private var theme
    @Query(
        filter: #Predicate<SavedConnection> { $0.deletedAt == nil },
        sort: \SavedConnection.name
    ) private var connections: [SavedConnection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacSearchField(text: $searchViewModel.searchText) {
                appState.selectSearch()
                searchViewModel.search()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 16)
            .onChange(of: searchViewModel.searchText) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !appState.isSearchActive {
                        appState.selectSearch()
                    }
                    searchViewModel.search()
                }
            }

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
                        Text("CONNECTIONS")
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
                        .help("添加连接")
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
                                Label("编辑", systemImage: "pencil")
                            }
                            Button {
                                syncConnection(connection)
                            } label: {
                                Label("同步到媒体库", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Button {
                                fullRescanConnection(connection)
                            } label: {
                                Label("全量重扫", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                deleteConnection(connection)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, MacDesignTokens.Layout.sidebarHorizontalPadding)
                .padding(.bottom, 16)
            }

            settingsFooter
        }
        .frame(width: MacDesignTokens.Layout.sidebarWidth)
        .background(theme.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.sidebarBorder)
                .frame(width: 1)
        }
    }

    private var settingsFooter: some View {
        MacSidebarRow(
            title: "Settings",
            systemImage: "gearshape",
            isSelected: appState.isSettingsActive && appState.selectedMediaItem == nil
        ) {
            appState.selectSettings()
        }
        .padding(.horizontal, MacDesignTokens.Layout.sidebarHorizontalPadding)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.sidebarBorder)
                .frame(height: 1)
        }
    }

    private func syncConnection(_ connection: SavedConnection) {
        Task {
            _ = await connectionsViewModel.connectAndScan(connection)
            await libraryViewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
            libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
        }
    }

    private func fullRescanConnection(_ connection: SavedConnection) {
        Task {
            _ = await connectionsViewModel.connectAndScan(connection, forceFullScan: true)
            await libraryViewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
            libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
        }
    }

    private func deleteConnection(_ connection: SavedConnection) {
        if appState.selectedMediaItem?.sourceConnectionId == connection.id {
            appState.closeDetail()
        }
        appState.clearActiveConnectionIfDeleted(connection.id)
        connectionsViewModel.deleteConnection(connection)
        Task {
            await libraryViewModel.refreshAfterLibrarySync(connections: connectionsViewModel.savedConnections)
            libraryViewModel.reload(filter: appState.selectedFilter, section: appState.selectedSection)
        }
    }
    private func isLibrarySectionSelected(_ section: MacSidebarSection) -> Bool {
        guard appState.selectedMediaItem == nil else { return false }
        switch appState.contentRoute {
        case .library:
            return appState.selectedSection == section
        case .libraryFavorites:
            return section == .favorites
        default:
            return false
        }
    }
}

private extension ConnectionType {
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
