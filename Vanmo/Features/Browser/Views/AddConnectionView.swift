import SwiftUI
import UniformTypeIdentifiers

struct AddConnectionView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedType: ConnectionType = .localFolder
    @State private var host = ""
    @State private var port = ""
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
                port = "\(selectedType.defaultPort)"
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
                port = "\(newValue.defaultPort)"
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
                selectedType.isMediaServer
                    ? "服务器地址（如 https://emby.example.com）"
                    : "主机地址",
                text: $host
            )
            .textContentType(.URL)
            .autocapitalization(.none)
            .keyboardType(.URL)

            if !hostContainsScheme {
                TextField("端口", text: $port)
                    .keyboardType(.numberPad)
            }

            TextField("路径 (可选)", text: $path)
                .autocapitalization(.none)
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

    private var hostContainsScheme: Bool {
        let trimmed = host.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }
        if selectedType.isLocal {
            return folderBookmark != nil
        }
        guard !host.isEmpty else { return false }
        if selectedType.requiresAuth {
            return !username.isEmpty
        }
        return true
    }

    private var resolvedPort: Int {
        if hostContainsScheme {
            return selectedType.defaultPort
        }
        return Int(port) ?? selectedType.defaultPort
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
            if selectedType.isLocal {
                guard let folderURL, let folderBookmark else { return }
                await viewModel.saveConnection(
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
                await viewModel.saveConnection(
                    name: name,
                    type: selectedType,
                    host: host,
                    port: resolvedPort,
                    username: username.isEmpty ? nil : username,
                    password: password.isEmpty ? nil : password,
                    path: path.isEmpty ? nil : path,
                    bookmarkData: nil
                )
            }
            dismiss()
        }
    }
}

#Preview {
    AddConnectionView(viewModel: BrowserViewModel())
}
