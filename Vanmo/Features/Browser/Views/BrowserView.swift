import SwiftUI
import SwiftData

struct ConnectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = ConnectionsViewModel()

    var body: some View {
        List {
            if !viewModel.savedConnections.isEmpty {
                savedConnectionsSection
            }

            protocolsSection
        }
        .overlay {
            if viewModel.savedConnections.isEmpty && !viewModel.isLoading {
                EmptyStateView(
                    icon: "externaldrive.connected.to.line.below",
                    title: "尚无连接",
                    message: "添加网络共享以扫描并管理你的媒体"
                ) {
                    viewModel.showAddConnection = true
                }
            }

            if viewModel.isLoading {
                LoadingView(viewModel.loadingMessage)
            }
        }
        .navigationTitle("连接")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showAddConnection = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task {
            viewModel.setModelContext(modelContext)
            await viewModel.loadSavedConnections()
        }
        .alert("错误", isPresented: $viewModel.showError) {
            Button("确定") {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $viewModel.showAddConnection) {
            AddConnectionView(viewModel: viewModel)
        }
    }

    // MARK: - Saved Connections

    private var savedConnectionsSection: some View {
        Section("已保存的连接") {
            ForEach(viewModel.savedConnections) { connection in
                Button {
                    Task {
                        let success = await viewModel.connectAndScan(connection)
                        if success {
                            appState.selectedTab = .library
                        }
                    }
                } label: {
                    ConnectionStatusRow(
                        connection: connection,
                        status: viewModel.connectionStatus(for: connection)
                    )
                }
                .tint(.primary)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.deleteConnection(connection)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Protocols

    private var protocolsSection: some View {
        Section {
            ForEach(ConnectionType.allCases) { type in
                Button {
                    viewModel.showAddConnection = true
                } label: {
                    Label(type.displayName, systemImage: type.icon)
                }
            }
        } header: {
            Text("添加新连接")
        }
    }
}

// MARK: - Connection Status Row

struct ConnectionStatusRow: View {
    let connection: SavedConnection
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.type.icon)
                .font(.title2)
                .foregroundStyle(Color.vanmoPrimary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(connection.type.displayName) · \(connection.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusIndicator
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Circle()
                .fill(.gray.opacity(0.5))
                .frame(width: 8, height: 8)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .failed:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Typealias for backward compatibility

typealias BrowserView = ConnectionsView

#Preview {
    NavigationStack {
        ConnectionsView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
