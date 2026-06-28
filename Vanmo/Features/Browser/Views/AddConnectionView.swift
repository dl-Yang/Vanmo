import SwiftUI
import UniformTypeIdentifiers

struct AddConnectionView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        NavigationStack {
            Form {
                typeSection

                if selectedType.isLocal {
                    localFolderSection
                } else {
                    remoteServerSection

                    if selectedType.requiresAuth {
                        authSection
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.vanmoBackground)
            .navigationTitle("添加连接")
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
            Picker("协议", selection: $selectedType) {
                ForEach(ConnectionType.allCases) { type in
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
                if !newValue.isLocal {
                    folderURL = nil
                    folderBookmark = nil
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
        }
    }

    // MARK: - Helpers

    private var hostPlaceholder: String {
        if selectedType.isMediaServer {
            return "服务器地址（如 https://emby.example.com）"
        }
        if selectedType == .iptv {
            return "播放列表 URL 或主机地址"
        }
        return "主机地址"
    }

    private var pathPlaceholder: String {
        selectedType == .iptv ? "播放列表路径或 URL" : "路径 (可选)"
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }
        if selectedType.isLocal {
            return folderBookmark != nil
        }
        guard !host.isEmpty else { return false }
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
            return "AList 默认端口 5244、WebDAV 路径为 /dav，是否启用 HTTPS 取决于实例配置。用户名/密码为 AList 账户，可聚合阿里云盘、百度网盘、115、夸克等来源；部分网盘的直链取流可能受限或限速。"
        case .webdav:
            return "通用 WebDAV 连接。主机可填写域名或 IP，路径用于指定服务器上的根目录；不确定路径时可留空。"
        case .smb:
            return "SMB 适用于 fnOS、NAS 或局域网共享，默认端口 445；保存后可从共享根目录继续进入具体文件夹。"
        case .iptv:
            return "可在主机地址或路径中填写完整 M3U/M3U8 播放列表 URL。"
        case .fnos:
            return "fnOS 按 WebDAV 兼容方式连接：局域网 HTTP 通常为 5005，HTTPS 通常为 5006，路径一般留空；如使用 SMB，请选择 SMB 协议。"
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
        guard let components = urlComponents(from: host.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        if components.scheme?.lowercased() == "https" {
            useHTTPS = true
        } else if components.scheme?.lowercased() == "http" {
            useHTTPS = false
        }
        if let componentPort = components.port {
            port = "\(componentPort)"
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
            } else {
                let input = normalizedRemoteInput
                didConnect = await viewModel.saveConnection(
                    name: name,
                    type: selectedType,
                    host: input.host,
                    port: input.port,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password,
                    path: input.path,
                    bookmarkData: nil
                )
            }
            if didConnect {
                dismiss()
            }
        }
    }
}

#Preview {
    AddConnectionView(viewModel: BrowserViewModel())
}
