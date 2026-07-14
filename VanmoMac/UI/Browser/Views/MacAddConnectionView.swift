import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VanmoCore

struct MacAddConnectionView: View {
    @ObservedObject var viewModel: MacConnectionsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.macTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let editingConnection: SavedConnection?

    @State private var name = ""
    @State private var selectedType: ConnectionType = .webdav
    @State private var host = ""
    @State private var port = ""
    @State private var useHTTPS = true
    @State private var username = ""
    @State private var password = ""
    @State private var path = ""

    @State private var folderURL: URL?
    @State private var folderBookmark: Data?
    @State private var folderPickerError: String?

    @State private var isAuthenticatingOAuth = false
    @State private var oauthErrorMessage: String?

    init(viewModel: MacConnectionsViewModel, editingConnection: SavedConnection? = nil) {
        self.viewModel = viewModel
        self.editingConnection = editingConnection

        let type = editingConnection?.type ?? .webdav
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
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            rightPanel
        }
        .frame(width: MacDesignTokens.Layout.addConnectionWidth, height: MacDesignTokens.Layout.addConnectionHeight)
        .background(modalBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Layout.addConnectionRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MacDesignTokens.Layout.addConnectionRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .overlay {
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .shadow(color: shadowColor, radius: colorScheme == .dark ? 30 : 20, y: colorScheme == .dark ? 15 : 10)
        .onAppear {
            guard !isEditing else { return }
            useHTTPS = inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: selectedType))
            port = "\(defaultPort(for: selectedType, useHTTPS: useHTTPS))"
            applyDefaults(for: selectedType)
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定") {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MacConnectionTypeGroup.allCases) { group in
                    groupSection(group)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
        }
        .frame(width: MacDesignTokens.Layout.addConnectionSidebarWidth)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(dividerColor)
                .frame(width: 1)
        }
    }

    private func groupSection(_ group: MacConnectionTypeGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if group != MacConnectionTypeGroup.allCases.first {
                Spacer().frame(height: 20)
            }

            Text(group.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.61)
                .foregroundStyle(theme.sectionHeader)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)

            ForEach(group.types, id: \.self) { type in
                protocolRow(type)
            }
        }
    }

    private func protocolRow(_ type: ConnectionType) -> some View {
        let isSelected = selectedType == type

        return Button {
            selectType(type)
        } label: {
            HStack(spacing: 10) {
                MacConnectionProviderIcon(type: type, size: 18)
                Text(type.macSidebarLabel)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(-0.08)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? .white : sidebarItemText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? MacDesignTokens.accentBlue : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: isSelected ? Color.black.opacity(0.1) : .clear,
                radius: 1.5,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .disabled(isEditing)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    formContent
                }
                .padding(40)
            }

            footer
        }
        .frame(width: MacDesignTokens.Layout.addConnectionContentWidth)
        .background(contentBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                MacConnectionProviderIcon(type: selectedType, size: 40)
                Text(isEditing ? "编辑 \(selectedType.displayName)" : selectedType.macAddConnectionTitle)
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.53)
                    .foregroundStyle(theme.primaryText)
            }

            if let description = selectedType.macAddConnectionDescription {
                Text(description)
                    .font(.system(size: 13))
                    .tracking(-0.08)
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.top, 16)
            }
        }
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private var formContent: some View {
        if selectedType.isLocal {
            localFolderForm
        } else if selectedType.supportsOAuthLogin {
            oauthForm
        } else if selectedType.isOfficialCloudDrive {
            officialCloudDriveForm
        } else {
            remoteServerForm
            if selectedType.requiresAuth {
                authForm
            }
        }
    }

    private var localFolderForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            formRow(label: "名称") {
                macTextField("我的文件夹", text: $name)
            }

            Button(action: pickLocalFolder) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(folderURL == nil ? "选择文件夹..." : "更换文件夹")
                    Spacer()
                }
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 11)
                .frame(height: 33.5)
                .background(inputBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(inputBorder, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            if let folderURL {
                Text(folderURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let folderPickerError {
                Text(folderPickerError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private var remoteServerForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            formRow(label: "名称") {
                macTextField("我的服务器", text: $name)
            }

            formRow(label: "主机") {
                macTextField(hostPlaceholder, text: $host)
                    .onChange(of: host) { _, _ in
                        applyHostSchemeDefaults()
                    }
            }

            if supportsHTTPS(for: selectedType) {
                formRow(label: "连接") {
                    HStack(spacing: 12) {
                        Text("HTTPS")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)

                        Toggle("", isOn: $useHTTPS)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: useHTTPS) { _, newValue in
                                applyHTTPSPortDefault(newValue)
                            }

                        Text("端口")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                            .padding(.leading, 8)

                        macTextField("443", text: $port)
                            .frame(width: 64)
                    }
                }
            } else {
                formRow(label: "端口") {
                    macTextField("\(selectedType.defaultPort)", text: $port)
                        .frame(width: 120)
                }
            }

            formRow(label: "路径") {
                macTextField(pathPlaceholder, text: $path)
            }

            if let formValidationMessage {
                Text(formValidationMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private var authForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .padding(.leading, 72)
                .padding(.top, 8)

            formRow(label: "用户名") {
                macTextField("", text: $username)
            }

            formRow(label: "密码") {
                SecureField("", text: $password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 11)
                    .frame(height: 33.5)
                    .background(inputBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(inputBorder, lineWidth: 1)
                    }
            }

            if isEditing {
                Text("留空则保留现有密码。")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.leading, 72)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(.top, 8)
    }

    private var oauthForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isEditing {
                formRow(label: "名称") {
                    macTextField(selectedType.displayName, text: $name)
                }
            }

            if !OAuthProviderConfiguration.isConfigured(for: selectedType) {
                Text(OAuthProviderConfiguration.missingCredentialHint(for: selectedType))
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            Button {
                Task { await beginOAuthLogin() }
            } label: {
                HStack {
                    Text(isEditing ? "重新登录 \(selectedType.displayName)" : "使用 \(selectedType.displayName) 账号登录")
                    Spacer()
                    if isAuthenticatingOAuth || viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(MacDesignTokens.accentBlue)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .disabled(!OAuthProviderConfiguration.isConfigured(for: selectedType) || isAuthenticatingOAuth || viewModel.isLoading)

            if let oauthErrorMessage {
                Text(oauthErrorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private var officialCloudDriveForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            formRow(label: "名称") {
                macTextField(selectedType.displayName, text: $name)
            }

            Text(selectedType.macAddConnectionDescription ?? "")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("取消") { dismiss() }
                .buttonStyle(MacSecondaryActionButtonStyle(theme: theme))

            Button("保存") { save() }
                .buttonStyle(MacPrimaryActionButtonStyle())
                .disabled(!isValid || viewModel.isLoading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 17)
        .padding(.bottom, 16)
        .background(contentBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
        }
    }

    // MARK: - Form Components

    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.08)
                .foregroundStyle(theme.secondaryText)
                .frame(width: 56, alignment: .trailing)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func macTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 11)
            .frame(height: 33.5)
            .background(inputBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(inputBorder, lineWidth: 1)
            }
    }

    // MARK: - Loading Overlay

    private var loadingMessageText: String {
        let trimmed = viewModel.loadingMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "处理中..." : trimmed
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.35)

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.regular)

                Text(loadingMessageText)
                    .font(.system(size: 13))
                    .tracking(-0.08)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(contentBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(dividerColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: 8, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Layout.addConnectionRadius, style: .continuous))
    }

    // MARK: - Theme Colors

    private var modalBackground: Color {
        colorScheme == .dark ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255) : Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    }

    private var sidebarBackground: Color {
        colorScheme == .dark
            ? Color(red: 40 / 255, green: 40 / 255, blue: 43 / 255).opacity(0.8)
            : Color(red: 232 / 255, green: 232 / 255, blue: 237 / 255).opacity(0.8)
    }

    private var contentBackground: Color {
        colorScheme == .dark ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255) : Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    }

    private var sidebarItemText: Color {
        colorScheme == .dark ? Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255) : Color(red: 54 / 255, green: 65 / 255, blue: 83 / 255)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.1)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.6) : Color.black.opacity(0.2)
    }

    private var inputBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.2) : .white
    }

    private var inputBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255)
    }

    // MARK: - Actions

    private func selectType(_ type: ConnectionType) {
        selectedType = type
        useHTTPS = supportsHTTPS(for: type)
            ? inferredHTTPSFromHost(defaultValue: defaultHTTPS(for: type))
            : false
        port = "\(defaultPort(for: type, useHTTPS: useHTTPS))"
        applyDefaults(for: type)
        // 若 host 已是带 scheme 无端口的完整 URL，重置默认端口后需重新套用标准端口，
        // 避免「先粘贴 https://host、后选择 Emby」时端口又被改回 8096。
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
        panel.prompt = "选择"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard url.startAccessingSecurityScopedResource() else {
            folderPickerError = "无法获取该文件夹的访问权限"
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

    // MARK: - Validation Helpers

    private var isEditing: Bool { editingConnection != nil }

    private var hostPlaceholder: String {
        if selectedType.isMediaServer {
            return "https://example.com"
        }
        if selectedType == .iptv {
            return "播放列表 URL 或主机地址"
        }
        return "https://example.com"
    }

    private var pathPlaceholder: String {
        if selectedType == .iptv {
            return "播放列表路径或 URL"
        }
        return "可选"
    }

    private var isValid: Bool {
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
            return selectedType == .iptv ? "端口需为 0-65535，或留空使用播放列表 URL。" : "端口需为 1-65535。"
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

// MARK: - Button Styles

private struct MacPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.08)
            .foregroundStyle(.white)
            .padding(.horizontal, 25)
            .padding(.vertical, 7)
            .background(MacDesignTokens.accentBlue.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: Color.black.opacity(0.1), radius: 1.5, y: 1)
    }
}

private struct MacSecondaryActionButtonStyle: ButtonStyle {
    let theme: MacThemeColors

    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .tracking(-0.08)
            .foregroundStyle(colorScheme == .dark ? .white : theme.secondaryText)
            .padding(.horizontal, 25)
            .padding(.vertical, 7)
            .background(
                colorScheme == .dark
                    ? Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255).opacity(configuration.isPressed ? 0.85 : 1)
                    : Color.white.opacity(configuration.isPressed ? 0.85 : 1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(colorScheme == .dark ? Color.clear : Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: Color.black.opacity(0.1), radius: 1.5, y: 1)
    }
}

#Preview("Add Connection Light") {
    MacAddConnectionView(viewModel: MacConnectionsViewModel())
        .macTheme(.light)
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Add Connection Dark") {
    MacAddConnectionView(viewModel: MacConnectionsViewModel())
        .macTheme(.dark)
        .padding()
        .background(Color.black)
}
