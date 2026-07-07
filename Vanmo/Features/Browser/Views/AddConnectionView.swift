import SwiftUI
import UniformTypeIdentifiers
import VanmoCore

struct AddConnectionView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    let editingConnection: SavedConnection?

    @State private var name = ""
    @State private var selectedType: ConnectionType = .localFolder
    @State private var host = ""
    @State private var port = ""
    @State private var useHTTPS = true
    @State private var username = ""
    @State private var password = ""
    @State private var path = ""

    @State private var folderURL: URL?
    @State private var folderBookmark: Data?
    @State private var showFolderPicker = false
    @State private var folderPickerError: String?

    @State private var isAuthenticatingOAuth = false
    @State private var oauthErrorMessage: String?

    init(viewModel: BrowserViewModel, editingConnection: SavedConnection? = nil) {
        self.viewModel = viewModel
        self.editingConnection = editingConnection

        let type = editingConnection?.type ?? .localFolder
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
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection

                if selectedType.isLocal {
                    localFolderSection
                } else if selectedType.supportsOAuthLogin {
                    oauthCloudDriveSection
                } else {
                    remoteServerSection

                    if selectedType.requiresAuth {
                        authSection
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vanmoBackground)
            .navigationTitle(isEditing ? "编辑连接" : "添加连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                }
            }
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
        }
    }

    // MARK: - Sections

    private var typeSection: some View {
        Section("连接类型") {
            if isEditing {
                LabeledContent("协议") {
                    Text(selectedType.displayName)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("协议", selection: $selectedType) {
                    ForEach(ConnectionType.availableConnectionTypes) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedType) { _, newValue in
                    useHTTPS = supportsHTTPS(for: newValue)
                        ? inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: newValue))
                        : false
                    port = "\(defaultPort(for: newValue, useHTTPS: useHTTPS))"
                    applyDefaults(for: newValue)
                    // 若 host 已是带 scheme 无端口的完整 URL，重置默认端口后需重新套用标准端口，
                    // 避免「先粘贴 https://host、后选择 Emby」时端口又被改回 8096。
                    applyHostSchemeDefaults()
                    if !newValue.isLocal {
                        folderURL = nil
                        folderBookmark = nil
                    }
                }
            }
        }
    }

    private var localFolderSection: some View {
        Section("本地文件夹") {
            TextField("名称", text: $name)
                .textContentType(.name)

            Button {
                showFolderPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(folderURL == nil ? "选择文件夹..." : "更换文件夹")
                    Spacer()
                }
            }

            if let folderURL {
                LabeledContent("已选目录") {
                    Text(folderURL.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                Text(folderURL.path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let folderPickerError {
                Text(folderPickerError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var remoteServerSection: some View {
        Section("服务器信息") {
            TextField("名称", text: $name)
                .textContentType(.name)

            TextField(
                hostPlaceholder,
                text: $host
            )
            .textContentType(.URL)
            .autocapitalization(.none)
            .keyboardType(.URL)
            .onChange(of: host) { _, _ in
                applyHostSchemeDefaults()
            }

            if supportsHTTPS(for: selectedType) {
                Toggle("HTTPS", isOn: $useHTTPS)
                    .onChange(of: useHTTPS) { _, newValue in
                        applyHTTPSPortDefault(newValue)
                    }
            }

            TextField("端口", text: $port)
                .keyboardType(.numberPad)

            TextField(pathPlaceholder, text: $path)
                .autocapitalization(.none)

            if let formValidationMessage {
                Text(formValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let fnOSPortHint {
                Text(fnOSPortHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let caption = connectionTypeCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authSection: some View {
        Section("认证") {
            TextField("用户名", text: $username)
                .textContentType(.username)
                .autocapitalization(.none)

            SecureField("密码", text: $password)
                .textContentType(.password)

            if isEditing {
                Text("留空则保留现有密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var officialCloudDriveSection: some View {
        Section("官方接入") {
            TextField("名称", text: $name)
                .textContentType(.name)

            TextField(hostPlaceholder, text: $host)
                .textContentType(.URL)
                .autocapitalization(.none)
                .keyboardType(.URL)

            TextField(pathPlaceholder, text: $path)
                .autocapitalization(.none)

            if let caption = connectionTypeCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var oauthCloudDriveSection: some View {
        Section("账号登录") {
            if isEditing {
                TextField("名称", text: $name)
                    .textContentType(.name)
            }

            if let caption = connectionTypeCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !OAuthProviderConfiguration.isConfigured(for: selectedType) {
                Text(OAuthProviderConfiguration.missingCredentialHint(for: selectedType))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await beginOAuthLogin() }
            } label: {
                HStack {
                    Text(isEditing ? "重新登录 \(selectedType.displayName)" : "使用 \(selectedType.displayName) 账号登录")
                    Spacer()
                    if isAuthenticatingOAuth {
                        ProgressView()
                    }
                }
            }
            .disabled(!OAuthProviderConfiguration.isConfigured(for: selectedType) || isAuthenticatingOAuth)

            if let oauthErrorMessage {
                Text(oauthErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private var isEditing: Bool {
        editingConnection != nil
    }

    private var hostPlaceholder: String {
        if selectedType.isMediaServer {
            return "服务器地址（如 https://emby.example.com）"
        }
        if selectedType == .iptv {
            return "播放列表 URL 或主机地址"
        }
        if selectedType.isOfficialCloudDrive {
            return "开放平台域名或应用参数"
        }
        return "主机地址"
    }

    private var pathPlaceholder: String {
        if selectedType == .iptv {
            return "播放列表路径或 URL"
        }
        if selectedType.isOfficialCloudDrive {
            return "起始目录 (可选，留空为根目录)"
        }
        return "路径 (可选)"
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }
        if selectedType.isLocal {
            return folderBookmark != nil
        }
        if selectedType.supportsOAuthLogin {
            // 新建走登录按钮直接创建连接；编辑时允许通过"保存"改名。
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
            return selectedType == .iptv ? "端口需为 0-65535，或留空使用播放列表 URL。" : "端口需为 1-65535。"
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
            return "SMB 适用于 fnOS、NAS 或局域网共享，默认端口 445；保存后可从共享根目录继续进入具体文件夹。"
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
        return Int(port) ?? selectedType.defaultPort
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

    /// AList / fnOS 的 WebDAV 路径需以 `/` 开头，纠正用户漏填前导斜杠的情况（如 `dav` → `/dav`）。
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
            // 用户粘贴了带 scheme 但不带端口的完整 URL（如 https://emby.example.com）：
            // 应使用该 scheme 的标准端口（https→443 / http→80），而不是媒体服务器的
            // 默认端口（如 Emby 8096），否则会拼出 https://host:8096 这类错误地址。
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
        case .fnos:
            return false
        default:
            return true
        }
    }

    private func defaultPort(for type: ConnectionType, useHTTPS: Bool) -> Int {
        switch type {
        case .fnos:
            return useHTTPS ? 5006 : 5005
        case .webdav:
            return useHTTPS ? 443 : 80
        default:
            return type.defaultPort
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
            if path.isEmpty {
                path = "/dav"
            }
        case .fnos:
            if path == "/dav" {
                path = ""
            }
        default:
            break
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                folderPickerError = "无法获取该文件夹的访问权限"
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
                if name.isEmpty {
                    name = url.lastPathComponent
                }
            } catch {
                folderPickerError = "保存文件夹书签失败: \(error.localizedDescription)"
            }

        case .failure(let error):
            folderPickerError = "选择文件夹失败: \(error.localizedDescription)"
        }
    }

    private func save() {
        Task {
            let didConnect: Bool
            if selectedType.isLocal {
                guard let folderURL, let folderBookmark else { return }
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
            if didConnect {
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
            oauthErrorMessage = viewModel.errorMessage.isEmpty ? "登录失败，请重试" : viewModel.errorMessage
        }
    }
}

#Preview {
    AddConnectionView(viewModel: BrowserViewModel())
}
