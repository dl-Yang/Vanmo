import SwiftUI
import UniformTypeIdentifiers
import VanmoCore

struct AddConnectionView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    let editingConnection: SavedConnection?

    @State private var name = ""
    @State private var selectedType: ConnectionType = .emby
    @State private var host = ""
    @State private var port = ""
    @State private var useHTTPS = true
    @State private var username = ""
    @State private var password = ""
    @State private var path = ""
    @State private var showAllProtocols = false

    @State private var folderURL: URL?
    @State private var folderBookmark: Data?
    @State private var showFolderPicker = false
    @State private var folderPickerError: String?

    @State private var isAuthenticatingOAuth = false
    @State private var oauthErrorMessage: String?
    @State private var isSaving = false
    @State private var saveErrorMessage: String?
    @State private var workTask: Task<Void, Never>?

    @State private var showPlexSignIn = false
    @State private var plexFlowCompleted = false
    @State private var isRenamingPlex = false

    private static let featuredProtocols: [ConnectionType] = [
        .emby, .jellyfin, .plex, .smb,
        .ftp, .googleDrive, .baiduNetdisk, .localFolder
    ]

    init(viewModel: BrowserViewModel, editingConnection: SavedConnection? = nil) {
        self.viewModel = viewModel
        self.editingConnection = editingConnection

        let type = editingConnection?.type ?? .emby
        let localFolderURL = editingConnection.flatMap { connection -> URL? in
            guard connection.type.isLocal else { return nil }
            let path = connection.path ?? connection.host
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
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
        _showAllProtocols = State(initialValue: !Self.featuredProtocols.contains(type))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CatDesign.surfaceSheet.ignoresSafeArea()

            VStack(spacing: 0) {
                sheetHeader
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        protocolSelectorSection
                        dynamicFormSection
                    }
                    .padding(.horizontal, CatDesign.horizontalMargin)
                    .padding(.bottom, 96)
                }
            }

            bottomConnectButton
        }
        .presentationDragIndicator(.hidden)
        .presentationBackground(CatDesign.surfaceSheet)
        .onAppear {
            guard !isEditing else { return }
            useHTTPS = inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: selectedType))
            port = "\(defaultPort(for: selectedType, useHTTPS: useHTTPS))"
            applyDefaults(for: selectedType)
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        .sheet(isPresented: $showPlexSignIn, onDismiss: handlePlexSheetDismiss) {
            PlexSignInView(
                viewModel: viewModel,
                editingConnection: editingConnection,
                suggestedName: trimmedName.isEmpty ? nil : trimmedName
            ) {
                plexFlowCompleted = true
            }
        }
        .overlay {
            statusOverlay
        }
        .onDisappear {
            workTask?.cancel()
        }
    }

    // MARK: - Header (`09 · Sheet — Add Storage Connection`)

    private var sheetHeader: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Capsule()
                    .fill(CatDesign.grabberFill)
                    .frame(width: 44, height: 4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)

                Image("CatSheetGrabberPeeking")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 38)
                    .padding(.trailing, 46)
                    .allowsHitTesting(false)
            }

            HStack {
                Text(isEditing ? L10n.tr("编辑连接") : L10n.tr("添加连接"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)

                Spacer()

                Button { cancelAndClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CatDesign.textMuted)
                        .frame(width: 28, height: 28)
                        .background(CatDesign.surfacePill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("关闭"))
            }
            .padding(.horizontal, CatDesign.horizontalMargin)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isBlocking {
            ConnectionStatusDialog(
                kind: .connecting(
                    title: isSaving ? L10n.tr("正在连接...") : L10n.tr("正在登录..."),
                    message: isSaving
                        ? L10n.tr("正在与服务器协商安全连接。")
                        : L10n.tr("完成登录后才会保存此连接")
                ),
                onCancel: cancelAndClose,
                onRetry: nil
            )
        } else if let message = saveErrorMessage ?? oauthErrorMessage {
            ConnectionStatusDialog(
                kind: .failed(message: message),
                onCancel: dismissConnectionError,
                onRetry: retryAfterError
            )
        }
    }

    private func cancelAndClose() {
        workTask?.cancel()
        workTask = nil
        isSaving = false
        isAuthenticatingOAuth = false
        dismiss()
    }

    private func dismissConnectionError() {
        saveErrorMessage = nil
        oauthErrorMessage = nil
    }

    private func retryAfterError() {
        if oauthErrorMessage != nil {
            oauthErrorMessage = nil
            startOAuthLogin()
        } else {
            saveErrorMessage = nil
            save()
        }
    }

    private var isBlocking: Bool {
        isSaving || isAuthenticatingOAuth
    }

    // MARK: - Protocol Selector

    private var displayedProtocols: [ConnectionType] {
        if isEditing {
            return [selectedType]
        }
        if showAllProtocols {
            let remaining = ConnectionType.availableConnectionTypes.filter { !Self.featuredProtocols.contains($0) }
            return Self.featuredProtocols + remaining
        }
        return Self.featuredProtocols
    }

    private let protocolColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    private var protocolSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("协议与来源类型"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CatDesign.textMuted)

                Spacer()

                if !isEditing {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAllProtocols.toggle()
                        }
                    } label: {
                        Text(showAllProtocols ? L10n.tr("收起协议") : L10n.tr("全部协议 (%d)", ConnectionType.availableConnectionTypes.count))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(CatDesign.accentAmber)
                    }
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: protocolColumns, spacing: 8) {
                ForEach(displayedProtocols) { type in
                    CatProtocolTile(
                        type: type,
                        isSelected: selectedType == type
                    ) {
                        guard !isEditing else { return }
                        selectProtocol(type)
                    }
                }
            }
        }
    }

    private func selectProtocol(_ newValue: ConnectionType) {
        selectedType = newValue
        useHTTPS = supportsHTTPS(for: newValue)
            ? inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: newValue))
            : false
        port = "\(defaultPort(for: newValue, useHTTPS: useHTTPS))"
        applyDefaults(for: newValue)
        applyHostSchemeDefaults()
        if !newValue.isLocal {
            folderURL = nil
            folderBookmark = nil
        }
    }

    // MARK: - Dynamic Form

    @ViewBuilder
    private var dynamicFormSection: some View {
        if selectedType.isLocal {
            localFolderSection
        } else if selectedType.supportsOAuthLogin {
            oauthCloudDriveSection
        } else if selectedType == .plex {
            plexSignInSection
        } else if selectedType.isOfficialCloudDrive {
            officialCloudDriveSection
        } else {
            remoteServerSection
        }
    }

    private var localFolderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CatGlassInputField(label: L10n.tr("名称"), placeholder: L10n.tr("例如：本地电影"), text: $name)

            Button {
                showFolderPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image("CatFolderTileAmber")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 18)

                    Text(folderURL == nil ? L10n.tr("选择文件夹...") : L10n.tr("更换文件夹"))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CatDesign.textMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .catGlassCard(cornerRadius: 14, amberStroke: folderURL == nil)
            }
            .buttonStyle(.plain)

            if let folderURL {
                VStack(alignment: .leading, spacing: 3) {
                    Text(folderURL.lastPathComponent)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Text(folderURL.path)
                        .font(.system(size: 11))
                        .foregroundStyle(CatDesign.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .catGlassCard(cornerRadius: 14)
            }

            if let folderPickerError {
                Text(folderPickerError)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.dangerRed)
            }
        }
    }

    private var remoteServerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CatGlassInputField(label: L10n.tr("连接名称"), placeholder: selectedType.displayName, text: $name)

            HStack(spacing: 10) {
                CatGlassInputField(
                    label: L10n.tr("主机 / 服务器地址"),
                    placeholder: hostPlaceholder,
                    text: $host,
                    keyboardType: .URL,
                    autocapitalization: .never
                )
                .onChange(of: host) { _, _ in
                    applyHostSchemeDefaults()
                }

                CatGlassInputField(
                    label: L10n.tr("端口"),
                    placeholder: "\(selectedType.defaultPort)",
                    text: $port,
                    keyboardType: .numberPad,
                    autocapitalization: .never
                )
                .frame(width: 88)
            }

            if supportsHTTPS(for: selectedType) {
                HStack {
                    Text("HTTPS")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Toggle("HTTPS", isOn: $useHTTPS)
                        .labelsHidden()
                        .tint(CatDesign.accentAmber)
                        .onChange(of: useHTTPS) { _, newValue in
                            applyHTTPSPortDefault(newValue)
                        }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .catGlassCard(cornerRadius: 14)
            }

            CatGlassInputField(
                label: L10n.tr("路径"),
                placeholder: pathPlaceholder,
                text: $path,
                autocapitalization: .never
            )

            if selectedType.requiresAuth {
                CatGlassInputField(
                    label: L10n.tr("用户名"),
                    placeholder: L10n.tr("用户名"),
                    text: $username,
                    autocapitalization: .never
                )

                CatGlassInputField(
                    label: L10n.tr("密码"),
                    placeholder: isEditing ? editingPasswordHint : "••••••••",
                    text: $password,
                    isSecure: true,
                    autocapitalization: .never
                )
            }

            if let formValidationMessage {
                Text(formValidationMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.dangerRed)
            } else if let fnOSPortHint {
                Text(fnOSPortHint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.textMuted)
            }

            if let caption = connectionTypeCaption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineSpacing(2)
            }
        }
    }

    private var officialCloudDriveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CatGlassInputField(label: L10n.tr("名称"), placeholder: selectedType.displayName, text: $name)
            CatGlassInputField(label: L10n.tr("主机地址"), placeholder: hostPlaceholder, text: $host, autocapitalization: .never)
            CatGlassInputField(label: L10n.tr("路径"), placeholder: pathPlaceholder, text: $path, autocapitalization: .never)

            if let caption = connectionTypeCaption {
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineSpacing(2)
            }
        }
    }

    private var oauthCloudDriveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                CatGlassInputField(label: L10n.tr("名称"), placeholder: selectedType.displayName, text: $name)
            }

            if let caption = connectionTypeCaption {
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.textMuted)
                    .lineSpacing(2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .catGlassCard(cornerRadius: 14)
            }

            if !OAuthProviderConfiguration.isConfigured(for: selectedType) {
                Text(OAuthProviderConfiguration.missingCredentialHint(for: selectedType))
                    .font(.system(size: 11.5))
                    .foregroundStyle(CatDesign.dangerRed)
            }

            Button {
                startOAuthLogin()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CatDesign.accentAmber)
                    Text(isEditing ? "重新登录 \(selectedType.displayName)" : "使用 \(selectedType.displayName) 账号登录")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CatDesign.textMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .catGlassCard(cornerRadius: 14, amberStroke: OAuthProviderConfiguration.isConfigured(for: selectedType))
            }
            .buttonStyle(.plain)
            .disabled(!OAuthProviderConfiguration.isConfigured(for: selectedType) || isAuthenticatingOAuth)
        }
    }

    private var plexSignInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let editingConnection {
                CatGlassInputField(label: L10n.tr("名称"), placeholder: "Plex", text: $name)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Plex 服务器"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CatDesign.textMuted)
                    Text(displayedPlexServer)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CatDesign.textIvory)
                    if let account = editingConnection.username, !account.isEmpty {
                        Text(L10n.tr("已登录 Plex 账号：%@", account))
                            .font(.system(size: 11))
                            .foregroundStyle(CatDesign.textMuted)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .catGlassCard(cornerRadius: 14)

                if viewModel.plexConnectionNeedsReauthentication(editingConnection) {
                    Text(L10n.tr("Plex 登录状态已失效，请重新登录。"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(CatDesign.dangerRed)
                }

                Button {
                    showPlexSignIn = true
                } label: {
                    HStack {
                        Text(L10n.tr("重新登录 Plex"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.accentAmber)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(CatDesign.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .catGlassCard(cornerRadius: 14, amberStroke: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("connection.plex.relogin")
            } else {
                CatGlassInputField(label: L10n.tr("可选名称"), placeholder: "Plex", text: $name)

                Button {
                    showPlexSignIn = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(CatDesign.accentAmber)
                        Text(L10n.tr("使用 Plex 账号登录"))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(CatDesign.textIvory)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(CatDesign.textMuted)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .catGlassCard(cornerRadius: 14, amberStroke: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("connection.plex.signIn")

                Text(L10n.tr("通过 Plex 账号登录后自动创建连接"))
                    .font(.system(size: 11))
                    .foregroundStyle(CatDesign.textMuted)
            }
        }
    }

    // MARK: - Bottom CTA (`Connect Glass Pill`)

    private var primaryButtonTitle: String {
        if isEditing { return L10n.tr("保存连接") }
        if selectedType.supportsOAuthLogin || selectedType == .plex {
            return L10n.tr("继续登录")
        }
        return L10n.tr("连接服务器")
    }

    private var canTapPrimaryButton: Bool {
        if isBlocking || isRenamingPlex { return false }
        if !isEditing && selectedType.supportsOAuthLogin {
            return OAuthProviderConfiguration.isConfigured(for: selectedType)
        }
        if !isEditing && selectedType == .plex {
            return true
        }
        return isValid
    }

    private var bottomConnectButton: some View {
        VStack(spacing: 0) {
            Button {
                handlePrimaryTap()
            } label: {
                HStack(spacing: 8) {
                    Image("CatEyeStatus")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 8)

                    Text(primaryButtonTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CatDesign.accentAmber)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(Capsule().fill(CatDesign.amberTintStrong))
                }
                .overlay(Capsule().strokeBorder(CatDesign.strokeAmber, lineWidth: 1.2))
                .shadow(color: CatDesign.amberGlowShadow, radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!canTapPrimaryButton)
            .opacity(canTapPrimaryButton ? 1 : 0.45)
        }
        .padding(.horizontal, CatDesign.horizontalMargin)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [CatDesign.surfaceSheet.opacity(0), CatDesign.surfaceSheet],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func handlePrimaryTap() {
        if !isEditing && selectedType.supportsOAuthLogin {
            startOAuthLogin()
        } else if !isEditing && selectedType == .plex {
            showPlexSignIn = true
        } else {
            save()
        }
    }

    // MARK: - Helpers (原有业务与校验逻辑完整保留)

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayedPlexServer: String {
        guard let editingConnection else { return "" }
        if let url = URL(string: editingConnection.host),
           let host = url.host {
            let port = url.port.map { ":\($0)" } ?? ""
            return host + port
        }
        return editingConnection.host
    }

    private func handlePlexSheetDismiss() {
        guard plexFlowCompleted else { return }
        plexFlowCompleted = false
        if let editingConnection, !trimmedName.isEmpty, trimmedName != editingConnection.name {
            Task { _ = await viewModel.renameConnection(editingConnection, name: trimmedName) }
        }
        workTask?.cancel()
        workTask = nil
        dismiss()
    }

    private var isEditing: Bool {
        editingConnection != nil
    }

    private var editingPasswordHint: String {
        if let editingConnection, CloudSyncedConnectionActivation.needsLocalCredential(editingConnection) {
            return L10n.tr("此设备还没有密码，iCloud 不同步凭据。")
        }
        return L10n.tr("留空则保留现有密码。")
    }

    private var hostPlaceholder: String {
        if selectedType.isMediaServer {
            return "https://emby.example.com"
        }
        if selectedType == .iptv {
            return L10n.tr("播放列表 URL 或主机地址")
        }
        if selectedType.isOfficialCloudDrive {
            return "开放平台域名或应用参数"
        }
        return "192.168.1.10"
    }

    private var pathPlaceholder: String {
        if selectedType == .iptv {
            return L10n.tr("播放列表路径或 URL")
        }
        if selectedType.isOfficialCloudDrive {
            return "起始目录 (可选，留空为根目录)"
        }
        if selectedType == .smb {
            return L10n.tr("共享名，如 /Movies")
        }
        return L10n.tr("路径 (可选)")
    }

    private var isValid: Bool {
        if selectedType == .plex {
            return isEditing && !trimmedName.isEmpty
        }
        guard !name.isEmpty else { return false }
        if selectedType.isLocal {
            return folderBookmark != nil
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
        if selectedType == .iptv, trimmed.isEmpty {
            return true
        }
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

    private var fnOSPortHint: String? {
        guard selectedType == .fnos, useHTTPS, Int(port) == 5005 else { return nil }
        return "fnOS HTTPS 通常使用 5006；FN Connect 外网域名通常使用 443，路径留空。"
    }

    private var connectionTypeCaption: String? {
        switch selectedType {
        case .alist:
            return "AList 默认端口 5244、WebDAV 路径为 /dav，是否启用 HTTPS 取决于实例配置。用户名/密码为 AList 账户，可聚合多种网盘来源；部分网盘的直链取流可能受限或限速。"
        case .webdav:
            return "通用 WebDAV 连接。主机可填写域名或 IP，路径用于指定服务器上的根目录；不确定路径时可留空。"
        case .smb:
            return "SMB 适用于 fnOS、NAS 或 Mac「文件共享」。默认端口 445。Mac 需在共享选项中打开 SMB，并为该用户勾选 Windows 文件共享；路径填写共享名（如 /yinguSMB）。"
        case .iptv:
            return "可在主机地址或路径中填写完整 M3U/M3U8 播放列表 URL。"
        case .fnos:
            return "fnOS 按 WebDAV 兼容方式连接：局域网 HTTP 通常为 5005，HTTPS 通常为 5006，路径一般留空；如使用 SMB，请选择 SMB 协议。"
        case .baiduNetdisk:
            return "通过百度网盘开放平台 OAuth 简化模式登录，仅请求 basic,netdisk 权限。Access Token 过期后需重新登录，不支持后台自动续期。"
        case .drive115:
            return "115 网盘需通过开放平台入驻和应用审核；本入口仅保留合规接入提示，当前不使用非官方接口。"
        case .quarkDrive:
            return "夸克网盘官方开放能力仍需调研确认；本入口仅保留合规接入提示，当前不使用非官方接口。"
        case .mega:
            return "MEGA 官方无标准 REST + OAuth 接口，完整支持需要官方 MEGA SDK（C++，端到端加密，每个文件需客户端侧解密）深度集成；当前仅保留入口，完整接入待后续单独评估工作量。"
        case .removedOfficialCloudDrive:
            return "该历史连接类型已移除，不再提供授权、浏览或取流能力；可删除此连接后改用 AList/WebDAV。"
        case .googleDrive:
            return "通过 Google 官方 OAuth 2.0 登录，仅请求只读权限；登录后可浏览、播放、下载你的 Google Drive 文件。"
        case .oneDrive:
            return "通过 Microsoft 官方 OAuth 2.0 登录（支持个人版与工作/学校账号），登录后可浏览、播放、下载 OneDrive 文件。"
        case .box:
            return "通过 Box 官方 OAuth 2.0 登录，登录后可浏览、播放、下载 Box 文件。"
        case .pCloudDrive:
            return "通过 pCloud 官方 OAuth 2.0 登录（自动识别 US/EU 数据中心），登录后可浏览、播放、下载 pCloud 文件。"
        case .yandexDisk:
            return "通过 Yandex 官方 OAuth 2.0 登录，登录后可浏览、播放、下载 Yandex.Disk 文件。"
        default:
            return nil
        }
    }

    private var resolvedPort: Int {
        Int(port) ?? selectedType.defaultPort
    }

    private var normalizedRemoteInput: (host: String, port: Int, path: String?) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)

        if selectedType.isOfficialCloudDrive {
            return (
                host: trimmedHost,
                port: selectedType.defaultPort,
                path: trimmedPath.isEmpty ? nil : trimmedPath
            )
        }

        guard supportsHTTPS(for: selectedType) else {
            return (
                host: trimmedHost,
                port: resolvedPort,
                path: trimmedPath.isEmpty ? nil : trimmedPath
            )
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

        return (
            host: normalizedHost,
            port: portValue,
            path: normalizedRemotePath(resolvedPath)
        )
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

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                folderPickerError = L10n.tr("无法获取该文件夹的访问权限")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let bookmark = try url.bookmarkData(
                    options: [.minimalBookmark],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                folderURL = url
                folderBookmark = bookmark
                folderPickerError = nil
                if name.isEmpty { name = url.lastPathComponent }
            } catch {
                folderPickerError = "保存文件夹书签失败: \(error.localizedDescription)"
            }
        case .failure(let error):
            folderPickerError = "选择文件夹失败: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard !isBlocking, !isRenamingPlex else { return }
        if selectedType == .plex {
            savePlexRename()
            return
        }
        isSaving = true
        saveErrorMessage = nil
        workTask = Task {
            defer {
                if !Task.isCancelled { isSaving = false }
            }
            let didConnect: Bool
            if selectedType.isLocal {
                guard let folderURL, let folderBookmark else {
                    saveErrorMessage = L10n.tr("请先选择本地文件夹")
                    return
                }
                if let editingConnection {
                    didConnect = await viewModel.updateConnection(
                        editingConnection,
                        name: name,
                        host: folderURL.path,
                        port: 0,
                        username: nil,
                        password: nil,
                        path: folderURL.path,
                        bookmarkData: folderBookmark
                    )
                } else {
                    didConnect = await viewModel.saveConnection(
                        name: name,
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
                        name: name,
                        host: input.host,
                        port: input.port,
                        username: username.isEmpty ? nil : username,
                        password: credentialPayload,
                        path: input.path,
                        bookmarkData: nil
                    )
                } else {
                    didConnect = await viewModel.saveConnection(
                        name: name,
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
            if Task.isCancelled { return }
            if didConnect {
                dismiss()
            } else {
                saveErrorMessage = viewModel.errorMessage.isEmpty
                    ? L10n.tr("服务器无响应或地址不正确。")
                    : viewModel.errorMessage
            }
        }
    }

    private func savePlexRename() {
        guard let editingConnection, !trimmedName.isEmpty else { return }
        isRenamingPlex = true
        saveErrorMessage = nil
        workTask = Task {
            let renamed = await viewModel.renameConnection(editingConnection, name: trimmedName)
            isRenamingPlex = false
            if Task.isCancelled { return }
            if renamed {
                dismiss()
            } else {
                saveErrorMessage = viewModel.errorMessage.isEmpty
                    ? L10n.tr("服务器无响应或地址不正确。")
                    : viewModel.errorMessage
            }
        }
    }

    private func startOAuthLogin() {
        guard !isBlocking else { return }
        isAuthenticatingOAuth = true
        oauthErrorMessage = nil
        workTask = Task {
            await beginOAuthLogin()
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
        if Task.isCancelled { return }
        if success {
            dismiss()
        } else {
            oauthErrorMessage = viewModel.errorMessage.isEmpty ? L10n.tr("登录失败，请重试") : viewModel.errorMessage
        }
    }
}

// MARK: - Cat Protocol Tile & Glass Input Field

private struct CatProtocolTile: View {
    let type: ConnectionType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? CatDesign.amberTintStrong : CatDesign.surfacePill)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? CatDesign.strokeAmber : CatDesign.strokeGlass, lineWidth: 0.75)

                    Text(type.catShortCode)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isSelected ? CatDesign.accentAmber : CatDesign.textMuted)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(type.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CatDesign.textIvory)
                        .lineLimit(1)

                    Text(type.catShortHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(isSelected ? CatDesign.accentAmber : CatDesign.textDim)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isSelected ? CatDesign.amberTintFill : CatDesign.surfaceGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        isSelected ? CatDesign.strokeAmber : CatDesign.strokeGlass,
                        lineWidth: isSelected ? 1.1 : 0.9
                    )
            )
            .shadow(color: isSelected ? CatDesign.amberGlowShadow : .clear, radius: 7, y: 4)
        }
        .buttonStyle(.plain)
    }
}

private struct CatGlassInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CatDesign.textMuted)

            Group {
                if isSecure {
                    SecureField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundStyle(CatDesign.textDim)
                    )
                } else {
                    TextField(
                        "",
                        text: $text,
                        prompt: Text(placeholder).foregroundStyle(CatDesign.textDim)
                    )
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(CatDesign.textIvory)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .catGlassCard(cornerRadius: 14)
        }
    }
}

private struct ConnectionStatusDialog: View {
    enum Kind {
        case connecting(title: String, message: String)
        case failed(message: String)
    }

    let kind: Kind
    let onCancel: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .allowsHitTesting(true)

            VStack(spacing: 0) {
                mainContent
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .frame(minHeight: 140)

                Rectangle()
                    .fill(CatDesign.hairSeparator)
                    .frame(height: 0.75)

                footer
                    .frame(height: 50)
            }
            .frame(width: 280)
            .catGlassCard(cornerRadius: 20, elevated: true, amberStroke: isConnecting)
            .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }

    private var isConnecting: Bool {
        if case .connecting = kind { return true }
        return false
    }

    @ViewBuilder
    private var mainContent: some View {
        switch kind {
        case .connecting(let title, let message):
            VStack(spacing: 0) {
                ProgressView()
                    .controlSize(.large)
                    .tint(CatDesign.accentAmber)
                    .frame(width: 40, height: 40)
                    .padding(.bottom, 14)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(CatDesign.textMuted)
                    .multilineTextAlignment(.center)
            }
        case .failed(let message):
            VStack(spacing: 0) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(CatDesign.dangerRed)
                    .frame(width: 40, height: 40)
                    .padding(.bottom, 14)
                Text(L10n.tr("连接失败"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CatDesign.textIvory)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
                Text(message.isEmpty ? L10n.tr("服务器无响应或地址不正确。") : message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(CatDesign.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 0) {
            dialogButton(L10n.tr("取消"), weight: .regular, tint: CatDesign.textMuted, action: onCancel)
            if let onRetry {
                Rectangle()
                    .fill(CatDesign.hairSeparator)
                    .frame(width: 0.75)
                dialogButton(L10n.tr("重试"), weight: .semibold, tint: CatDesign.accentAmber, action: onRetry)
            }
        }
    }

    private func dialogButton(_ title: String, weight: Font.Weight, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: weight))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var accessibilityTitle: String {
        switch kind {
        case .connecting(let title, _): return title
        case .failed: return L10n.tr("连接失败")
        }
    }
}

#Preview {
    AddConnectionView(viewModel: BrowserViewModel())
        .preferredColorScheme(.dark)
}
