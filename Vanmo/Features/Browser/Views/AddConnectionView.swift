import SwiftUI

struct AddConnectionView: View {
    @ObservedObject var viewModel: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedType: ConnectionType = .smb
    @State private var host = ""
    @State private var port = ""
    @State private var username = ""
    @State private var password = ""
    @State private var path = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("连接类型") {
                    Picker("协议", selection: $selectedType) {
                        ForEach(ConnectionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) { _, newValue in
                        port = "\(newValue.defaultPort)"
                    }
                }

                Section("服务器信息") {
                    TextField("名称", text: $name)
                        .textContentType(.name)

                    TextField("主机地址", text: $host)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)

                    TextField("路径 (可选)", text: $path)
                        .autocapitalization(.none)
                }

                if selectedType.requiresAuth {
                    Section("认证") {
                        TextField("用户名", text: $username)
                            .textContentType(.username)
                            .autocapitalization(.none)

                        SecureField("密码", text: $password)
                            .textContentType(.password)
                    }
                }
            }
            .navigationTitle("添加连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                port = "\(selectedType.defaultPort)"
            }
        }
    }

    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty
    }

    private func save() {
        Task {
            await viewModel.saveConnection(
                name: name,
                type: selectedType,
                host: host,
                port: Int(port) ?? selectedType.defaultPort,
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password,
                path: path.isEmpty ? nil : path
            )
            dismiss()
        }
    }
}

#Preview {
    AddConnectionView(viewModel: BrowserViewModel())
}
