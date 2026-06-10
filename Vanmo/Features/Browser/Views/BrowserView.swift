import SwiftUI
import SwiftData

struct ConnectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var viewModel: ConnectionsViewModel

    var body: some View {
        content
            .background(Color.vanmoBackground)
            .overlay {
                if viewModel.isLoading {
                    LoadingView(viewModel.loadingMessage)
                }
            }
        .navigationTitle("文件")
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
            await viewModel.loadSelectedConnectionRootIfNeeded()
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

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.savedConnections.isEmpty && !viewModel.isBrowsingFiles {
            EmptyStateView(
                icon: "folder.badge.plus",
                title: "暂无文件来源",
                message: "使用右上角按钮添加本地文件夹或服务器连接"
            ) {
                viewModel.showAddConnection = true
            }
        } else {
            List {
                connectionsSection

                if viewModel.selectedConnection != nil {
                    pathSection
                    filesSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .refreshable {
                await viewModel.refreshCurrentDirectory()
            }
        }
    }

    private var connectionsSection: some View {
        Section("已连接协议") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.savedConnections) { connection in
                        ConnectionChip(
                            connection: connection,
                            status: viewModel.connectionStatus(for: connection),
                            isSelected: viewModel.selectedConnectionID == connection.id
                        ) {
                            Task { await viewModel.selectConnection(connection) }
                        }
                        .contextMenu {
                            Button {
                                Task { await viewModel.connectAndScan(connection) }
                            } label: {
                                Label("同步到媒体库", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Button {
                                Task { await viewModel.connectAndScan(connection, forceFullScan: true) }
                            } label: {
                                Label("全量重扫", systemImage: "arrow.clockwise")
                            }

                            Button(role: .destructive) {
                                viewModel.deleteConnection(connection)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private var pathSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.goBackDirectory() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                }
                .disabled(viewModel.pathStack.isEmpty)

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.selectedConnection?.name ?? "文件")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(viewModel.currentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Menu {
                    Button {
                        Task { await viewModel.refreshCurrentDirectory() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        Task { await viewModel.scanCurrentDirectory() }
                    } label: {
                        Label("同步当前目录", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        Section("文件") {
            if viewModel.isBrowsingFiles {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载目录...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if let message = viewModel.fileBrowserErrorMessage {
                FileBrowserMessageRow(
                    icon: "exclamationmark.triangle",
                    title: "无法加载目录",
                    message: message
                )
            } else if viewModel.files.isEmpty {
                FileBrowserMessageRow(
                    icon: "folder",
                    title: "文件夹为空",
                    message: "此目录下没有可显示的文件"
                )
            } else {
                ForEach(viewModel.files) { file in
                    Button {
                        Task { await handleFileTap(file) }
                    } label: {
                        FileBrowserRow(file: file)
                    }
                    .tint(.primary)
                    .contextMenu {
                        if file.isDirectory {
                            Button {
                                Task { await viewModel.openDirectory(file) }
                            } label: {
                                Label("打开", systemImage: "folder")
                            }
                        }

                        if file.isVideo {
                            Button {
                                Task { await play(file) }
                            } label: {
                                Label("播放", systemImage: "play.fill")
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleFileTap(_ file: RemoteFile) async {
        if file.isDirectory {
            await viewModel.openDirectory(file)
        } else if file.isVideo {
            await play(file)
        }
    }

    private func play(_ file: RemoteFile) async {
        do {
            let url = try await viewModel.streamURL(for: file)
            let parsed = FileNameParser.parse(file.name)
            let item = MediaItem(
                title: parsed.title,
                fileURL: url,
                mediaType: parsed.isTV ? .tvEpisode : .movie,
                fileSize: file.size
            )
            item.year = parsed.year
            item.seasonNumber = parsed.season
            item.episodeNumber = parsed.episode
            item.showTitle = parsed.isTV ? parsed.title : nil
            item.serverId = file.path
            item.sourceConnectionId = viewModel.selectedConnection?.id
            item.originalFileName = file.name
            let ext = (file.name as NSString).pathExtension
            item.container = ext.isEmpty ? nil : ext.lowercased()
            appState.play(item)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            viewModel.showError = true
        }
    }
}

// MARK: - Connection Chip

private struct ConnectionChip: View {
    let connection: SavedConnection
    let status: ConnectionStatus
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: connection.type.icon)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(connection.type.displayName)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                }

                statusIndicator
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? Color.vanmoPrimary : Color.vanmoSurface,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Circle()
                .fill(isSelected ? .white.opacity(0.55) : .gray.opacity(0.5))
                .frame(width: 7, height: 7)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .connected:
            Circle()
                .fill(.green)
                .frame(width: 7, height: 7)
        case .failed:
            Circle()
                .fill(.red)
                .frame(width: 7, height: 7)
        }
    }
}

// MARK: - File Browser Row

private struct FileBrowserRow: View {
    let file: RemoteFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.type.icon)
                .font(.title2)
                .foregroundStyle(Color.vanmoPrimary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if file.isDirectory {
            return "文件夹"
        }
        if file.size > 0 {
            return "\(file.type.displayName) · \(file.size.formattedFileSize)"
        }
        return file.type.displayName
    }
}

private struct FileBrowserMessageRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

private extension RemoteFileType {
    var displayName: String {
        switch self {
        case .video: return "视频"
        case .subtitle: return "字幕"
        case .audio: return "音频"
        case .image: return "图片"
        case .directory: return "文件夹"
        case .other: return "文件"
        }
    }

    var icon: String {
        switch self {
        case .video: return "film"
        case .subtitle: return "captions.bubble"
        case .audio: return "music.note"
        case .image: return "photo"
        case .directory: return "folder"
        case .other: return "doc"
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
    .environmentObject(ConnectionsViewModel())
    .preferredColorScheme(.dark)
}
