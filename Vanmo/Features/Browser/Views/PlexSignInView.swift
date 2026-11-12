import SwiftUI
import UIKit
import VanmoCore

/// Plex PIN 授权 + 服务器选择 sheet。
///
/// 没有对应的 Figma 稿件（Plex 登录流程此前只有密码表单）：
/// 复用 Add Connection 的 Form、系统按钮、`Color+Vanmo` 色板与 spacing 节奏，
/// 不引入新的设计语言。
///
/// 状态机（五态）：
/// `starting`（加载）→ `waiting`（PIN 代码 + 浏览器授权）→ `choosingServer`（成功，服务器列表）
/// → `connecting`（加载）→ `failed`（错误 + 重试）。PIN 过期留在 `waiting` 并提示重新获取代码。
struct PlexSignInView: View {
    @ObservedObject var viewModel: ConnectionsViewModel

    let editingConnection: SavedConnection?
    let suggestedName: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let api: PlexAuthAPI
    private let startsAutomatically: Bool
    private let onCompleted: () -> Void

    @State private var phase: Phase = .starting
    @State private var pin: PlexPin?
    @State private var isPinExpired = false
    @State private var didCopyCode = false
    @State private var authToken: String?
    @State private var account: PlexAccount?
    @State private var servers: [PlexServerResource] = []
    @State private var isLoadingServers = false
    @State private var selectedServer: PlexServerResource?
    @State private var failureContext: FailureContext = .authorization
    @State private var failureMessage = ""
    @State private var flowTask: Task<Void, Never>?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var hasStarted = false

    init(
        viewModel: ConnectionsViewModel,
        editingConnection: SavedConnection? = nil,
        suggestedName: String? = nil,
        api: PlexAuthAPI = PlexAuthAPI(),
        startsAutomatically: Bool = true,
        onCompleted: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.editingConnection = editingConnection
        self.suggestedName = suggestedName
        self.api = api
        self.startsAutomatically = startsAutomatically
        self.onCompleted = onCompleted
    }

    private enum Phase: Equatable {
        case starting
        case waiting
        case choosingServer
        case connecting
        case failed
    }

    /// 失败后「重试」要回到哪一步：重新授权 / 只重取服务器 / 只重连服务器。
    private enum FailureContext {
        case authorization
        case discovery
        case connection
    }

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .scrollContentBackground(.hidden)
            .background(Color.vanmoBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("取消")) { cancel() }
                        // 选定服务器后保存与首次扫描已经开始，中途取消会留下半保存的连接。
                        .disabled(phase == .connecting)
                        .accessibilityIdentifier("plex.cancel")
                }
            }
            .interactiveDismissDisabled(phase == .connecting)
        }
        .onAppear {
            guard startsAutomatically, !hasStarted else { return }
            hasStarted = true
            startSignIn()
        }
        .onDisappear {
            flowTask?.cancel()
            copyFeedbackTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .starting:
            startingSection
        case .waiting:
            waitingSections
        case .choosingServer:
            serverSections
        case .connecting:
            connectingSection
        case .failed:
            failedSections
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .choosingServer:
            return L10n.tr("选择 Plex 服务器")
        default:
            return L10n.tr("登录 Plex")
        }
    }

    // MARK: - Starting（加载）

    private var startingSection: some View {
        Section {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(L10n.tr("正在获取 Plex 授权代码…"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plex.starting")
        }
    }

    // MARK: - Waiting（四位代码 + 浏览器授权）

    @ViewBuilder
    private var waitingSections: some View {
        Section {
            VStack(spacing: 12) {
                Text(L10n.tr("在浏览器中打开 plex.tv/link，输入下面的代码完成授权。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(pin?.code ?? "----")
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .tracking(6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("plex.signIn.code")
            }
            .padding(.vertical, 8)
        }

        Section {
            Button {
                if let url = pin?.authURL {
                    openURL(url)
                }
            } label: {
                Label(L10n.tr("打开 plex.tv/link"), systemImage: "safari")
            }
            .disabled(pin == nil)
            .accessibilityIdentifier("plex.signIn.openLink")

            Button {
                copyCode()
            } label: {
                Label(
                    didCopyCode ? L10n.tr("已复制") : L10n.tr("复制代码"),
                    systemImage: didCopyCode ? "checkmark" : "doc.on.doc"
                )
            }
            .disabled(pin == nil)
            .accessibilityIdentifier("plex.signIn.copyCode")
        }

        Section {
            if isPinExpired {
                Label {
                    Text(L10n.tr("授权代码已过期，请重新获取代码。"))
                } icon: {
                    Image(systemName: "clock.badge.exclamationmark")
                }
                .font(.callout)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("plex.signIn.expired")
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.tr("等待浏览器授权…"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("plex.signIn.waiting")
            }

            Button(L10n.tr("重新获取代码")) { startSignIn() }
                .accessibilityIdentifier("plex.signIn.refreshCode")
        }
    }

    // MARK: - Choosing server（成功）

    @ViewBuilder
    private var serverSections: some View {
        Section {
            if let account, !account.username.isEmpty {
                Text(L10n.tr("已登录 Plex 账号：%@", account.username))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("plex.signIn.account")
            }

            if isLoadingServers {
                HStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.tr("选择 Plex 服务器"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("plex.signIn.loadingServers")
            } else if servers.isEmpty {
                Text(L10n.tr("未找到可用的 Plex 服务器。请确认该 Plex 账号至少有一台可访问的媒体服务器。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("plex.signIn.noServer")
            } else {
                ForEach(servers) { server in
                    Button {
                        choose(server)
                    } label: {
                        serverRow(server)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(serverAccessibilityLabel(server)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("plex.server.\(server.clientIdentifier)")
                }
            }
        } header: {
            Text(L10n.tr("选择 Plex 服务器"))
        }
    }

    private func serverRow(_ server: PlexServerResource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.body)
                .foregroundStyle(Color.vanmoAccent)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        versionText(for: server)
                        badgeRow(for: server)
                    }
                } else {
                    HStack(spacing: 6) {
                        versionText(for: server)
                        badgeRow(for: server)
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func versionText(for server: PlexServerResource) -> some View {
        if let version = server.productVersion, !version.isEmpty {
            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func badgeRow(for server: PlexServerResource) -> some View {
        HStack(spacing: 6) {
            ForEach(badges(for: server), id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.vanmoAccent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.vanmoAccent)
            }
        }
    }

    // MARK: - Connecting（加载）

    private var connectingSection: some View {
        Section {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(L10n.tr("正在连接 %@…", connectingServerName))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plex.signIn.connecting")
        }
    }

    private var connectingServerName: String {
        selectedServer?.name ?? L10n.tr("Plex 服务器")
    }

    // MARK: - Failed（错误 + 重试）

    @ViewBuilder
    private var failedSections: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                Text(L10n.tr("Plex 授权失败"))
                    .font(.headline)

                Text(failureMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plex.signIn.failed")
        }

        Section {
            Button(L10n.tr("重试")) { retry() }
                .accessibilityIdentifier("plex.signIn.retry")
        }
    }

    // MARK: - Flow

    private func startSignIn() {
        flowTask?.cancel()
        copyFeedbackTask?.cancel()
        phase = .starting
        pin = nil
        isPinExpired = false
        didCopyCode = false
        authToken = nil
        account = nil
        servers = []
        isLoadingServers = false
        selectedServer = nil
        failureMessage = ""
        logEvent("phase=starting")
        flowTask = Task { await runSignInFlow() }
    }

    private func runSignInFlow() async {
        do {
            let createdPin = try await api.createPin()
            guard !Task.isCancelled else { return }
            pin = createdPin
            phase = .waiting
            logEvent("phase=waiting")

            let remaining = createdPin.expiresAt.timeIntervalSinceNow
            let token = try await api.awaitAuthorization(
                pinId: createdPin.id,
                timeout: max(remaining, 1),
                pollInterval: 2
            )
            guard !Task.isCancelled else { return }
            authToken = token
            await completeAuthorization(accountToken: token)
        } catch is CancellationError {
            // sheet 关闭或已重新获取代码：保持当前界面，不做额外提示。
        } catch let error as PlexAuthError {
            guard !Task.isCancelled else { return }
            handleAuthorizationFailure(error)
        } catch {
            guard !Task.isCancelled else { return }
            fail(
                message: message(for: error, fallback: L10n.tr("Plex 授权失败")),
                context: .authorization
            )
        }
    }

    /// 拿到 authToken 后取账号与服务器列表（账号信息缺失不阻塞登录）。
    private func completeAuthorization(accountToken: String) async {
        phase = .choosingServer
        isLoadingServers = true
        defer { isLoadingServers = false }

        do {
            account = try? await api.fetchAccount(token: accountToken)
            guard !Task.isCancelled else { return }

            let resources = try await api.fetchServers(token: accountToken)
            guard !Task.isCancelled else { return }

            guard !resources.isEmpty else {
                fail(
                    message: L10n.tr("未找到可用的 Plex 服务器。请确认该 Plex 账号至少有一台可访问的媒体服务器。"),
                    context: .discovery
                )
                return
            }
            servers = resources
            logEvent("phase=serverChoice count=\(resources.count)")
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            fail(
                message: message(for: error, fallback: L10n.tr("服务器不可达，请检查网络后重试。")),
                context: .discovery
            )
        }
    }

    private func choose(_ server: PlexServerResource) {
        guard let accountToken = authToken else { return }
        startConnecting(server: server, accountToken: accountToken)
    }

    private func startConnecting(server: PlexServerResource, accountToken: String) {
        selectedServer = server
        phase = .connecting
        logEvent("phase=connecting")
        flowTask?.cancel()
        flowTask = Task { await connect(server: server, accountToken: accountToken) }
    }

    private func connect(server: PlexServerResource, accountToken: String) async {
        do {
            // 共享服务器（非本人所有）在 resources 里带自己的 accessToken；探测与连接都必须用它。
            let serverToken = server.effectiveToken(accountToken: accountToken)
            let endpoint = try await api.resolveEndpoint(for: server, token: serverToken)
            guard !Task.isCancelled else { return }

            let succeeded: Bool
            if let editingConnection {
                succeeded = await viewModel.reloginPlexConnection(
                    editingConnection,
                    token: serverToken,
                    server: server,
                    endpoint: endpoint,
                    account: account
                )
            } else {
                succeeded = await viewModel.savePlexConnection(
                    name: suggestedName,
                    token: serverToken,
                    server: server,
                    endpoint: endpoint,
                    account: account
                )
            }
            guard !Task.isCancelled else { return }

            if succeeded {
                logEvent("phase=completed")
                onCompleted()
                dismiss()
            } else {
                fail(
                    message: viewModel.errorMessage.isEmpty
                        ? L10n.tr("连接失败")
                        : viewModel.errorMessage,
                    context: .connection
                )
            }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            fail(
                message: message(for: error, fallback: L10n.tr("服务器不可达，请检查网络后重试。")),
                context: .connection
            )
        }
    }

    private func retry() {
        switch failureContext {
        case .authorization:
            startSignIn()
        case .discovery:
            if let token = authToken {
                flowTask?.cancel()
                flowTask = Task { await completeAuthorization(accountToken: token) }
            } else {
                startSignIn()
            }
        case .connection:
            if let server = selectedServer, let accountToken = authToken {
                startConnecting(server: server, accountToken: accountToken)
            } else {
                startSignIn()
            }
        }
    }

    private func handleAuthorizationFailure(_ error: PlexAuthError) {
        switch error {
        case .authorizationCancelled:
            break
        case .pinExpired, .authorizationTimedOut:
            isPinExpired = true
            phase = .waiting
        case .noServer:
            fail(
                message: L10n.tr("未找到可用的 Plex 服务器。请确认该 Plex 账号至少有一台可访问的媒体服务器。"),
                context: .discovery
            )
        case .serverUnreachable:
            fail(
                message: L10n.tr("服务器不可达，请检查网络后重试。"),
                context: .discovery
            )
        case .requestFailed(let serverMessage):
            fail(
                message: serverMessage.isEmpty ? L10n.tr("Plex 授权失败") : serverMessage,
                context: .authorization
            )
        }
    }

    private func fail(message: String, context: FailureContext) {
        failureMessage = message
        failureContext = context
        phase = .failed
        switch context {
        case .authorization:
            logEvent("failed stage=authorization")
        case .discovery:
            logEvent("failed stage=discovery")
        case .connection:
            logEvent("failed stage=connection")
        }
    }

    /// 仅记录阶段与计数，不记录 PIN 代码、token、地址或服务器名。
    private func logEvent(_ event: String) {
        #if DEBUG
        VanmoLogger.network.info("[Debug][Plex] ios ui \(event, privacy: .public)")
        #endif
    }

    private func message(for error: Error, fallback: String) -> String {
        guard let plexError = error as? PlexAuthError else {
            let description = error.localizedDescription
            return description.isEmpty ? fallback : description
        }
        switch plexError {
        case .requestFailed(let serverMessage):
            return serverMessage.isEmpty ? fallback : serverMessage
        case .pinExpired, .authorizationTimedOut:
            return L10n.tr("授权代码已过期，请重新获取代码。")
        case .authorizationCancelled:
            return fallback
        case .noServer:
            return L10n.tr("未找到可用的 Plex 服务器。请确认该 Plex 账号至少有一台可访问的媒体服务器。")
        case .serverUnreachable:
            return L10n.tr("服务器不可达，请检查网络后重试。")
        }
    }

    private func cancel() {
        flowTask?.cancel()
        flowTask = nil
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        dismiss()
    }

    private func copyCode() {
        guard let code = pin?.code else { return }
        UIPasteboard.general.string = code
        didCopyCode = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            didCopyCode = false
        }
    }

    // MARK: - Presentation helpers

    private func badges(for server: PlexServerResource) -> [String] {
        var badges: [String] = []
        let connections = server.connections
        if connections.contains(where: { $0.isLocal }) {
            badges.append(L10n.tr("本地"))
        }
        if connections.contains(where: { !$0.isLocal && !$0.isRelay }) {
            badges.append(L10n.tr("远程"))
        }
        if connections.contains(where: { $0.isRelay }) {
            badges.append(L10n.tr("中继"))
        }
        return badges
    }

    private func serverAccessibilityLabel(_ server: PlexServerResource) -> String {
        var parts = [server.name]
        if let version = server.productVersion, !version.isEmpty {
            parts.append(version)
        }
        parts.append(contentsOf: badges(for: server))
        return parts.joined(separator: ", ")
    }
}

#Preview {
    PlexSignInView(
        viewModel: ConnectionsViewModel(),
        startsAutomatically: false
    ) {}
}