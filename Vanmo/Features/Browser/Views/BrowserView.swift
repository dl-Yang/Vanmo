import SwiftUI
import SwiftData

struct BrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = BrowserViewModel()

    var body: some View {
        Group {
            if viewModel.isConnected {
                fileListView
            } else {
                connectionListView
            }
        }
        .navigationTitle(viewModel.isConnected ? viewModel.currentPath : "浏览")
        .toolbar { toolbarContent }
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

    // MARK: - Connection List

    private var connectionListView: some View {
        List {
            if !viewModel.savedConnections.isEmpty {
                Section("已保存的连接") {
                    ForEach(viewModel.savedConnections) { connection in
                        Button {
                            Task { await viewModel.connect(to: connection) }
                        } label: {
                            ConnectionRow(connection: connection)
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
        .overlay {
            if viewModel.isLoading {
                LoadingView("连接中...")
            }
        }
    }

    // MARK: - File List

    private var fileListView: some View {
        List {
            if viewModel.currentFiles.isEmpty && !viewModel.isLoading {
                ContentUnavailableView("文件夹为空", systemImage: "folder")
            } else {
                ForEach(viewModel.currentFiles) { file in
                    Button {
                        handleFileTap(file)
                    } label: {
                        RemoteFileRow(file: file)
                    }
                    .tint(.primary)
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                LoadingView()
            }
        }
        .refreshable {
            await viewModel.loadDirectory(viewModel.currentPath)
        }
    }

    private func handleFileTap(_ file: RemoteFile) {
        if file.isDirectory {
            Task { await viewModel.navigateTo(file) }
        } else if file.isVideo {
            Task {
                do {
                    let url = try await viewModel.streamURL(for: file)
                    let mediaItem = MediaItem(
                        title: file.name,
                        fileURL: url,
                        fileSize: file.size
                    )
                    appState.play(mediaItem)
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                    viewModel.showError = true
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isConnected {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task { await viewModel.navigateBack() }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await viewModel.disconnect() }
                } label: {
                    Text("断开")
                        .foregroundStyle(.red)
                }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showAddConnection = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Connection Row

struct ConnectionRow: View {
    let connection: SavedConnection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: connection.type.icon)
                .font(.title2)
                .foregroundStyle(.vanmoPrimary)
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

            if connection.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Remote File Row

struct RemoteFileRow: View {
    let file: RemoteFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !file.isDirectory {
                        Text(file.size.formattedFileSize)
                    }
                    if let date = file.modifiedDate {
                        Text(date, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch file.type {
        case .directory: return "folder.fill"
        case .video: return "film"
        case .subtitle: return "captions.bubble"
        case .audio: return "music.note"
        case .image: return "photo"
        case .other: return "doc"
        }
    }

    private var iconColor: Color {
        switch file.type {
        case .directory: return .vanmoPrimary
        case .video: return .blue
        case .subtitle: return .green
        case .audio: return .purple
        case .image: return .pink
        case .other: return .secondary
        }
    }
}

#Preview {
    NavigationStack {
        BrowserView()
    }
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
