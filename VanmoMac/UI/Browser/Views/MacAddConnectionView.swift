import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VanmoCore

struct MacAddConnectionView: View {
    @ObservedObject var viewModel: MacConnectionsViewModel
    @EnvironmentObject private var appState: MacAppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macTheme) private var theme

    let editingConnection: SavedConnection?

    @State private var name = ""
    @State private var selectedType: ConnectionType = .emby
    @State private var host = ""
    @State private var port = ""
    @State private var useHTTPS = true
    @State private var username = ""
    @State private var password = ""
    @State private var path = ""
    @State private var showsAllProtocols = false

    @State private var folderURL: URL?
    @State private var folderBookmark: Data?
    @State private var folderPickerError: String?

    @State private var isAuthenticatingOAuth = false
    @State private var oauthErrorMessage: String?

    @State private var isPlexSignInPresented = false
    @State private var plexSignInCompleted = false
    @State private var isRenamingPlex = false

    init(viewModel: MacConnectionsViewModel, editingConnection: SavedConnection? = nil) {
        self.viewModel = viewModel
        self.editingConnection = editingConnection

        let type = editingConnection?.type ?? .emby
        let localFolderURL = editingConnection.flatMap { connection -> URL? in
            guard connection.type.isLocal else { return nil }
            let folderPath = connection.path ?? connection.host
            return folderPath.isEmpty ? nil : URL(fileURLWithPath: folderPath)
        }

        _name = State(initialValue: editingConnection?.name ?? "")
        _selectedType = State(initialValue: type)
        _host = State(initialValue: editingConnection?.host ?? "")
        _port = State(initialValue: editingConnection.map { "\($0.port)" } ?? "")
        _useHTTPS = State(initialValue: editingConnection.map { connection in
            connection.host.lowercased().hasPrefix("https://") || connection.port == 443
        } ?? true)
        _username = State(initialValue: editingConnection?.username ?? "")
        _password = State(initialValue: "")
        _path = State(initialValue: editingConnection?.path ?? "")
        _folderURL = State(initialValue: localFolderURL)
        _folderBookmark = State(initialValue: editingConnection?.bookmarkData)
        _showsAllProtocols = State(initialValue: editingConnection != nil && !Self.featuredTypes.contains(type))
    }

    private static let featuredTypes: [ConnectionType] = [
        .emby, .jellyfin, .plex, .smb,
        .ftp, .googleDrive, .baiduNetdisk,
    ]

    private static let remainingTypes: [ConnectionType] = [
        .sftp, .webdav, .alist, .fnos,
        .localFolder, .oneDrive, .box, .pCloudDrive,
        .yandexDisk, .iptv, .nfs, .dlna,
        .drive115, .quarkDrive, .mega,
    ]

    private var displayedProtocolTiles: [ProtocolTileItem] {
        if isEditing {
            return [.connection(selectedType)]
        }
        var items = Self.featuredTypes.map { ProtocolTileItem.connection($0) }
        items.append(.directURL)
        if showsAllProtocols {
            items.append(contentsOf: Self.remainingTypes.map { ProtocolTileItem.connection($0) })
        }
        return items
    }

    var body: some View {
        ZStack {
            modalBody
                .padding(.top, 38)
        }
        .onAppear {
            guard !isEditing else { return }
            useHTTPS = inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: selectedType))
            port = "\(defaultPort(for: selectedType, useHTTPS: useHTTPS))"
            applyDefaults(for: selectedType)
        }
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .alert(L10n.tr("错误"), isPresented: $viewModel.showError) {
            Button(L10n.tr("确定")) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $isPlexSignInPresented, onDismiss: handlePlexSignInDismiss) {
            MacPlexSignInView(
                viewModel: viewModel,
                editingConnection: editingConnection,
                suggestedName: trimmedName.isEmpty ? nil : trimmedName
            ) {
                plexSignInCompleted = true
            }
            .macTheme(theme)
        }
    }

    private var modalBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        modalHeader
                        protocolGridSection
                        formFieldsSection
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                }

                modalFooter
                    .padding(.horizontal, 26)
                    .padding(.bottom, 22)
                    .padding(.top, 8)
            }
            .frame(width: MacDesignTokens.Layout.addConnectionWidth, height: MacDesignTokens.Layout.addConnectionHeight)
            .background(theme.surfacePanel, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.modalDialog, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.modalDialog, style: .continuous)
                    .strokeBorder(theme.strokeGlass, lineWidth: 1)
            }
            .overlay {
                if viewModel.isLoading {
                    loadingOverlay
                }
            }
            .shadow(color: Color.black.opacity(theme.isDark ? 0.72 : 0.22), radius: 24, y: 12)

            Image("MacModalPeekingCat")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 46)
                .offset(x: -56, y: -39)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Header

    private var modalHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditing ? L10n.tr("编辑 %@", selectedType.displayName) : L10n.tr("添加连接"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(theme.primaryText)

                Text(selectedType.macAddConnectionDescription ?? L10n.tr("连接媒体服务器、NAS 共享、网盘或直链 URL"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(theme.surfacePill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("关闭"))
        }
    }

    // MARK: - Protocol Tiles

    private var protocolGridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("协议与来源").uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .tracking(0.5)

                Spacer()

                if !isEditing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsAllProtocols.toggle()
                        }
                    } label: {
                        Text(showsAllProtocols ? L10n.tr("收起部分协议 ▴") : L10n.tr("全部协议 (22) ▾"))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(theme.accentAmber)
                    }
                    .buttonStyle(.plain)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(displayedProtocolTiles) { tile in
                    protocolTile(tile)
                }
            }
        }
    }

    private func protocolTile(_ tile: ProtocolTileItem) -> some View {
        let isSelected: Bool = {
            if case .connection(let type) = tile {
                return selectedType == type
            }
            return false
        }()

        return Button {
            switch tile {
            case .connection(let type):
                selectType(type)
            case .directURL:
                dismiss()
                appState.openDirectLinks()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(tile.badge)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(isSelected ? theme.accentAmber : theme.tertiaryText)
                    Spacer()
                    if isSelected {
                        MacPawDotIndicator(size: 10)
                    }
                }

                Spacer(minLength: 4)

                Text(tile.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(height: 62)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? theme.amberTintFill : theme.surfaceGlass,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? theme.strokeAmber : theme.strokeGlass, lineWidth: isSelected ? 1.15 : 0.85)
            }
        }
        .buttonStyle(.plain)
        .disabled(isEditing && !isSelected)
    }

    // MARK: - Form Fields

    @ViewBuilder
    private var formFieldsSection: some View {
        if selectedType.isLocal {
            localFolderForm
        } else if selectedType.supportsOAuthLogin {
            oauthForm
        } else if selectedType == .plex {
            plexForm
        } else if selectedType.isOfficialCloudDrive {
            officialCloudDriveForm
        } else {
            remoteServerForm
        }
    }

    private var localFolderForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldBox(label: L10n.tr("显示名称")) {
                catTextField(L10n.tr("我的文件夹"), text: $name)
            }

            Button(action: pickLocalFolder) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(theme.accentAmber)
                    Text(folderURL == nil ? L10n.tr("选择文件夹...") : L10n.tr("更换文件夹"))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                }
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                        .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                }
            }
            .buttonStyle(.plain)

            if let folderURL {
                Text(folderURL.path)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let folderPickerError {
                Text(folderPickerError)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.dangerRed)
            }
        }
    }

    private var remoteServerForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                fieldBox(label: L10n.tr("主机 / 服务器地址").uppercased()) {
                    HStack(spacing: 8) {
                        catTextField(hostPlaceholder, text: $host)
                            .onChange(of: host) { _, _ in
                                applyHostSchemeDefaults()
                            }

                        if supportsHTTPS(for: selectedType) {
                            Button {
                                useHTTPS.toggle()
                                applyHTTPSPortDefault(useHTTPS)
                            } label: {
                                Text("HTTPS")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(useHTTPS ? theme.accentAmber : theme.tertiaryText)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(useHTTPS ? theme.amberTintFill : theme.surfacePill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                            .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                    }
                }

                fieldBox(label: L10n.tr("端口").uppercased()) {
                    catTextField("\(selectedType.defaultPort)", text: $port)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                        }
                }
                .frame(width: 104)
            }

            if selectedType.requiresAuth {
                HStack(alignment: .top, spacing: 12) {
                    fieldBox(label: L10n.tr("用户名").uppercased()) {
                        catTextField("", text: $username)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                    .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                            }
                    }

                    fieldBox(label: L10n.tr("密码 / 令牌").uppercased()) {
                        SecureField("", text: $password)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                    .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                            }
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                fieldBox(label: L10n.tr("显示名称").uppercased()) {
                    catTextField(selectedType.displayName, text: $name)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                        }
                }

                fieldBox(label: L10n.tr("可选路径").uppercased()) {
                    catTextField(pathPlaceholder, text: $path)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                        }
                }
            }

            if isEditing {
                Text(editingPasswordHint)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }

            if let formValidationMessage {
                Text(formValidationMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.dangerRed)
            }
        }
    }

    private var oauthForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                fieldBox(label: L10n.tr("显示名称").uppercased()) {
                    catTextField(selectedType.displayName, text: $name)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                        }
                }
            }

            if !OAuthProviderConfiguration.isConfigured(for: selectedType) {
                Text(OAuthProviderConfiguration.missingCredentialHint(for: selectedType))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.dangerRed)
            }

            Button {
                Task { await beginOAuthLogin() }
            } label: {
                HStack {
                    Text(isEditing ? L10n.tr("重新登录 %@", selectedType.displayName) : L10n.tr("使用 %@ 账号登录", selectedType.displayName))
                    Spacer()
                    if isAuthenticatingOAuth || viewModel.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .buttonStyle(MacCatAmberGlassButtonStyle(height: 40, horizontalPadding: 16))
            .disabled(!OAuthProviderConfiguration.isConfigured(for: selectedType) || isAuthenticatingOAuth || viewModel.isLoading)

            if let oauthErrorMessage {
                Text(oauthErrorMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.dangerRed)
            }
        }
    }

    private var plexForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let editingConnection {
                fieldBox(label: L10n.tr("显示名称").uppercased()) {
                    catTextField(L10n.tr("Plex 服务器"), text: $name)
                        .padding(.horizontal, 12)
                        .frame(height: 38)
                        .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                                .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                        }
                }

                plexConnectionSummary(editingConnection)

                if viewModel.plexConnectionNeedsReauthentication(editingConnection) {
                    Text(L10n.tr("Plex 登录状态已失效，请重新登录。"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                }

                plexSignInButton(title: L10n.tr("重新登录 Plex"))
            } else {
                plexSignInButton(title: L10n.tr("使用 Plex 账号登录"))
            }
        }
    }

    private func plexConnectionSummary(_ connection: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.tr("Plex 服务器"))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.secondaryText)

            Text(displayedPlexServer)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            if let account = connection.username,
               !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L10n.tr("已登录 Plex 账号：%@", account))
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macCatGlassCard(theme: theme, cornerRadius: 11)
        .accessibilityElement(children: .combine)
    }

    private func plexSignInButton(title: String) -> some View {
        Button {
            isPlexSignInPresented = true
        } label: {
            HStack {
                Text(title)
                Spacer()
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(MacCatAmberGlassButtonStyle(height: 40, horizontalPadding: 16))
        .disabled(viewModel.isLoading)
        .accessibilityIdentifier(editingConnection == nil ? "mac.plex.signIn" : "mac.plex.relogin")
    }

    private var officialCloudDriveForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldBox(label: L10n.tr("显示名称").uppercased()) {
                catTextField(selectedType.displayName, text: $name)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(theme.surfaceGlass, in: RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: MacDesignTokens.Radius.inputField, style: .continuous)
                            .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
                    }
            }

            Text(selectedType.macAddConnectionDescription ?? "")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Footer

    private var modalFooter: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image("MacCatEyeStatus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 7)
                    .shadow(color: MacDesignTokens.glowAmber.opacity(0.75), radius: 2)

                Text(selectedType == .plex && !isEditing
                     ? L10n.tr("通过 Plex 账号登录后自动创建连接")
                     : L10n.tr("安全保存在 macOS 钥匙串中"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button(L10n.tr("取消")) { dismiss() }
                .buttonStyle(MacCatGlassButtonStyle(height: 38, horizontalPadding: 18))

            Button(isEditing ? L10n.tr("保存") : L10n.tr("测试并连接")) { save() }
                .buttonStyle(MacCatAmberButtonStyle(height: 38, horizontalPadding: 20))
                .disabled(!isValid || viewModel.isLoading || isRenamingPlex)
                .opacity((!isValid || viewModel.isLoading || isRenamingPlex) ? 0.45 : 1)
        }
    }

    // MARK: - Helpers

    private func fieldBox<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .tracking(0.4)

            content()
        }
    }

    private func catTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(theme.primaryText)
    }

    private var loadingOverlay: some View {
        let trimmed = viewModel.loadingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = trimmed.isEmpty ? L10n.tr("处理中...") : trimmed

        return ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 14) {
                ProgressView().controlSize(.regular)
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .macCatGlassCard(theme: theme, cornerRadius: 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.modalDialog, style: .continuous))
    }

    // MARK: - Actions

    private func selectType(_ type: ConnectionType) {
        selectedType = type
        useHTTPS = supportsHTTPS(for: type)
            ? inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: type))
            : false
        port = "\(defaultPort(for: type, useHTTPS: useHTTPS))"
        applyDefaults(for: type)
        applyHostSchemeDefaults()
        if !type.isLocal {
            folderURL = nil
            folderBookmark = nil
        }
    }

    private func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("选择")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard url.startAccessingSecurityScopedResource() else {
            folderPickerError = L10n.tr("无法获取该文件夹的访问权限")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            folderURL = url
            folderBookmark = bookmark
            folderPickerError = nil
            if name.isEmpty {
                name = url.lastPathComponent
            }
        } catch {
            folderPickerError = "保存文件夹书签失败: \(error.localizedDescription)"
        }
    }

    private func save() {
        if selectedType == .plex {
            savePlexRename()
            return
        }

        Task {
            let resolvedName = trimmedName.isEmpty ? selectedType.displayName : trimmedName
            let didConnect: Bool
            if selectedType.isLocal {
                guard let folderURL, let folderBookmark else { return }
                if let editingConnection {
                    didConnect = await viewModel.updateConnection(
                        editingConnection,
                        name: resolvedName,
                        host: folderURL.path,
                        port: 0,
                        username: nil,
                        password: nil,
                        path: folderURL.path,
                        bookmarkData: folderBookmark
                    )
                } else {
                    didConnect = await viewModel.saveConnection(
                        name: resolvedName,
                        type: selectedType,
                        host: folderURL.path,
                        port: 0,
                        username: nil,
                        password: nil,
                        path: folderURL.path,
                        bookmarkData: folderBookmark
                    )
                }
            } else {
                let input = normalizedRemoteInput
                let credentialPayload = password.isEmpty ? nil : password
                if let editingConnection {
                    didConnect = await viewModel.updateConnection(
                        editingConnection,
                        name: resolvedName,
                        host: input.host,
                        port: input.port,
                        username: username.isEmpty ? nil : username,
                        password: credentialPayload,
                        path: input.path,
                        bookmarkData: nil
                    )
                } else {
                    didConnect = await viewModel.saveConnection(
                        name: resolvedName,
                        type: selectedType,
                        host: input.host,
                        port: input.port,
                        username: username.isEmpty ? nil : username,
                        password: credentialPayload,
                        path: input.path,
                        bookmarkData: nil
                    )
                }
            }
            if didConnect {
                dismiss()
            }
        }
    }

    private func savePlexRename() {
        guard let editingConnection, !trimmedName.isEmpty else { return }
        isRenamingPlex = true
        let newName = trimmedName
        Task {
            let renamed = await viewModel.renameConnection(editingConnection, name: newName)
            isRenamingPlex = false
            if Task.isCancelled { return }
            if renamed {
                dismiss()
            }
        }
    }

    private func beginOAuthLogin() async {
        isAuthenticatingOAuth = true
        oauthErrorMessage = nil

        let success: Bool
        if let editingConnection {
            success = await viewModel.reauthenticateOAuthConnection(editingConnection)
        } else {
            success = await viewModel.beginOAuthConnection(type: selectedType, name: name.isEmpty ? nil : name)
        }

        isAuthenticatingOAuth = false
        if success {
            dismiss()
        } else {
            oauthErrorMessage = viewModel.errorMessage.isEmpty ? L10n.tr("登录失败，请重试") : viewModel.errorMessage
        }
    }

    // MARK: - Validation Helpers

    private var isEditing: Bool { editingConnection != nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedPlexServer: String {
        guard let editingConnection else { return "" }
        guard let url = URL(string: editingConnection.host), let host = url.host else {
            return editingConnection.host
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return host + port
    }

    private func handlePlexSignInDismiss() {
        guard plexSignInCompleted else { return }
        plexSignInCompleted = false
        if let editingConnection,
           !trimmedName.isEmpty,
           trimmedName != editingConnection.name {
            let newName = trimmedName
            Task { _ = await viewModel.renameConnection(editingConnection, name: newName) }
        }
        dismiss()
    }

    private var editingPasswordHint: String {
        if let editingConnection, CloudSyncedConnectionActivation.needsLocalCredential(editingConnection) {
            return L10n.tr("此设备还没有密码，iCloud 不同步凭据。")
        }
        return L10n.tr("留空则保留现有密码。")
    }

    private var hostPlaceholder: String {
        if selectedType.isMediaServer {
            return "https://emby.studio.local"
        }
        if selectedType == .iptv {
            return L10n.tr("播放列表 URL 或主机地址")
        }
        return "https://example.com"
    }

    private var pathPlaceholder: String {
        if selectedType == .iptv {
            return L10n.tr("播放列表路径或 URL")
        }
        if selectedType == .smb {
            return L10n.tr("共享名，如 /Movies")
        }
        return L10n.tr("可选")
    }

    private var isValid: Bool {
        if selectedType == .plex {
            return isEditing && !trimmedName.isEmpty
        }
        if selectedType.isLocal {
            return folderBookmark != nil && !name.isEmpty
        }
        if selectedType.supportsOAuthLogin {
            return isEditing
        }
        guard !host.isEmpty else { return false }
        if selectedType.isOfficialCloudDrive {
            return false
        }
        guard isPortValid, isRemotePathValid else { return false }
        if selectedType.requiresAuth {
            return !username.isEmpty
        }
        return true
    }

    private var isPortValid: Bool {
        let trimmed = port.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedType == .iptv, trimmed.isEmpty { return true }
        guard let value = Int(trimmed) else { return false }
        if selectedType == .iptv {
            return (0...65535).contains(value)
        }
        return (1...65535).contains(value)
    }

    private var isRemotePathValid: Bool {
        guard selectedType == .webdav || selectedType == .alist || selectedType == .fnos else {
            return true
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.hasPrefix("/")
    }

    private var formValidationMessage: String? {
        if !isPortValid {
            return selectedType == .iptv ? "端口需为 0-65535，或留空使用播放列表 URL。" : L10n.tr("端口需为 1-65535。")
        }
        if !isRemotePathValid {
            return "WebDAV 路径需以 / 开头；不确定时可留空。"
        }
        return nil
    }

    private var resolvedPort: Int {
        Int(port) ?? selectedType.defaultPort
    }

    private var normalizedRemoteInput: (host: String, port: Int, path: String?) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        guard supportsHTTPS(for: selectedType) else {
            return (trimmedHost, resolvedPort, trimmedPath.isEmpty ? nil : trimmedPath)
        }

        let components = urlComponents(from: trimmedHost)
        let portValue = resolvedPort
        let normalizedHost: String

        if let urlHost = components?.host, !urlHost.isEmpty {
            var normalizedComponents = URLComponents()
            normalizedComponents.scheme = useHTTPS ? "https" : "http"
            normalizedComponents.host = urlHost
            if portValue > 0 {
                normalizedComponents.port = portValue
            }
            if selectedType == .iptv {
                normalizedComponents.path = components?.path ?? ""
            }
            normalizedHost = normalizedComponents.string ?? "\(useHTTPS ? "https" : "http")://\(urlHost)"
        } else if trimmedHost.hasPrefix("http://") || trimmedHost.hasPrefix("https://") {
            normalizedHost = trimmedHost
        } else {
            let scheme = useHTTPS ? "https" : "http"
            let portSuffix = portValue > 0 ? ":\(portValue)" : ""
            normalizedHost = "\(scheme)://\(trimmedHost)\(portSuffix)"
        }

        let urlPath = components?.path.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedPath = trimmedPath.isEmpty && selectedType != .iptv && !urlPath.isEmpty ? urlPath : trimmedPath

        return (normalizedHost, portValue, normalizedRemotePath(resolvedPath))
    }

    private func normalizedRemotePath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if (selectedType == .alist || selectedType == .fnos), !trimmed.hasPrefix("/") {
            return "/" + trimmed
        }
        return trimmed
    }

    private func supportsHTTPS(for type: ConnectionType) -> Bool {
        switch type {
        case .webdav, .alist, .iptv, .fnos, .plex, .emby, .jellyfin:
            return true
        default:
            return false
        }
    }

    private func applyHostSchemeDefaults() {
        guard supportsHTTPS(for: selectedType) else { return }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = urlComponents(from: trimmed) else { return }
        let hasExplicitScheme = trimmed.lowercased().hasPrefix("http://")
            || trimmed.lowercased().hasPrefix("https://")
        if components.scheme?.lowercased() == "https" {
            useHTTPS = true
        } else if components.scheme?.lowercased() == "http" {
            useHTTPS = false
        }
        if let componentPort = components.port {
            port = "\(componentPort)"
        } else if hasExplicitScheme {
            port = components.scheme?.lowercased() == "http" ? "80" : "443"
        }
    }

    private func inferredHTTPSFromHost(defaultValue: Bool) -> Bool {
        guard supportsHTTPS(for: selectedType) else { return false }
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = urlComponents(from: trimmed)?.scheme?.lowercased() {
            return scheme == "https"
        }
        if Int(port) == 443 {
            return true
        }
        return defaultValue
    }

    private func urlComponents(from value: String) -> URLComponents? {
        guard !value.isEmpty else { return nil }
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return URLComponents(string: value)
        }
        return URLComponents(string: "https://\(value)")
    }

    private func defaultHTTPS(for type: ConnectionType) -> Bool {
        switch type {
        case .fnos: return false
        default: return true
        }
    }

    private func defaultPort(for type: ConnectionType, useHTTPS: Bool) -> Int {
        switch type {
        case .fnos: return useHTTPS ? 5006 : 5005
        case .webdav: return useHTTPS ? 443 : 80
        default: return type.defaultPort
        }
    }

    private func applyHTTPSPortDefault(_ useHTTPS: Bool) {
        guard selectedType == .fnos else { return }
        let currentPort = Int(port)
        if currentPort == nil || currentPort == 5005 || currentPort == 5006 {
            port = "\(defaultPort(for: selectedType, useHTTPS: useHTTPS))"
        }
    }

    private func applyDefaults(for type: ConnectionType) {
        switch type {
        case .alist:
            if path.isEmpty { path = "/dav" }
        case .fnos:
            if path == "/dav" { path = "" }
        default:
            break
        }
    }
}

private enum ProtocolTileItem: Identifiable {
    case connection(ConnectionType)
    case directURL

    var id: String {
        switch self {
        case .connection(let type): return "conn-\(type.rawValue)"
        case .directURL: return "direct-url"
        }
    }

    var badge: String {
        switch self {
        case .connection(let type): return type.macShortBadge
        case .directURL: return "URL"
        }
    }

    var label: String {
        switch self {
        case .connection(let type): return type.macSidebarLabel
        case .directURL: return L10n.tr("直链 URL")
        }
    }
}

// MARK: - Legacy Compatibility Button Styles (used by MacPlexSignInView)

struct MacPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(MacDesignTokens.catSilhouette)
            .padding(.horizontal, 20)
            .frame(height: 36)
            .background(MacDesignTokens.glowAmber.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
    }
}

struct MacSecondaryActionButtonStyle: ButtonStyle {
    let theme: MacThemeColors

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .background(theme.surfaceGlass.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(theme.strokeGlass, lineWidth: 0.9)
            }
    }
}

#Preview("Add Connection Dark") {
    MacAddConnectionView(viewModel: MacConnectionsViewModel())
        .environmentObject(MacAppState())
        .macTheme(.dark)
        .padding(40)
        .background(Color.black.opacity(0.6))
}

#Preview("Add Connection Light") {
    MacAddConnectionView(viewModel: MacConnectionsViewModel())
        .environmentObject(MacAppState())
        .macTheme(.light)
        .padding(40)
        .background(Color.gray.opacity(0.3))
}
