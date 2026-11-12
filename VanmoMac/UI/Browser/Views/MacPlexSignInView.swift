import AppKit
import SwiftUI
import VanmoCore

/// Plex PIN 登录 sheet。
///
/// 流程：获取四位授权码 → 浏览器授权 → 选择服务器 → 建立连接。
/// 新建连接与「重新登录 Plex」共用本 sheet；具体保存动作由注入的闭包执行，
/// 因此本视图不直接持有 SwiftData 或 Keychain 逻辑。
struct MacPlexSignInView: View {
    @ObservedObject var viewModel: MacConnectionsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.macTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// nil 表示新建连接；非 nil 表示重新登录已有连接。
    let editingConnection: SavedConnection?
    let suggestedName: String?
    let onFinished: () -> Void

    @StateObject private var model: MacPlexSignInModel
    @State private var copiedCode = false
    @State private var copyResetTask: Task<Void, Never>?
    @FocusState private var focusedAction: PlexPrimaryAction?

    private enum PlexPrimaryAction: Hashable {
        case openBrowser
        case copyCode
        case retry
        case cancel
    }

    init(
        viewModel: MacConnectionsViewModel,
        editingConnection: SavedConnection? = nil,
        suggestedName: String? = nil,
        onFinished: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.editingConnection = editingConnection
        self.suggestedName = suggestedName
        self.onFinished = onFinished

        let targetConnection = editingConnection
        let targetName = suggestedName
        _model = StateObject(wrappedValue: MacPlexSignInModel(
            save: { token, server, endpoint, account in
                let succeeded: Bool
                if let targetConnection {
                    succeeded = await viewModel.reloginPlexConnection(
                        targetConnection,
                        token: token,
                        server: server,
                        endpoint: endpoint,
                        account: account
                    )
                } else {
                    succeeded = await viewModel.savePlexConnection(
                        name: targetName,
                        token: token,
                        server: server,
                        endpoint: endpoint,
                        account: account
                    )
                }
                guard !succeeded else { return nil }
                let message = viewModel.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                return message.isEmpty ? L10n.tr("Plex 授权失败") : message
            }
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, PlexSheetMetrics.horizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .frame(minHeight: PlexSheetMetrics.contentMinHeight, alignment: .topLeading)

            Divider()

            footer
        }
        .frame(width: MacDesignTokens.Layout.addConnectionContentWidth)
        .background(panelBackground)
        .task {
            model.start()
        }
        .onChange(of: model.didFinish) { _, didFinish in
            guard didFinish else { return }
            finish()
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .waiting:
                focusedAction = .openBrowser
            case .failed:
                focusedAction = .retry
            default:
                break
            }
        }
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
            model.cancel()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            MacConnectionProviderIcon(type: .plex, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("登录 Plex"))
                    .font(.system(size: 19, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.primaryText)

                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PlexSheetMetrics.horizontalPadding)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var headerSubtitle: String {
        if let editingConnection {
            let name = editingConnection.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? editingConnection.type.displayName : name
        }
        return L10n.tr("Plex 服务器")
    }

    // MARK: - Phase Content

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .starting:
            startingContent
        case .waiting(let pin):
            waitingContent(pin)
        case .choosingServer(let servers):
            serverSelectionContent(servers)
        case .connecting(let serverName):
            connectingContent(serverName)
        case .failed(let message):
            failedContent(message)
        }
    }

    private var startingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text(L10n.tr("正在获取 Plex 授权代码…"))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 40)
    }

    private func waitingContent(_ pin: PlexPin) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("在浏览器中打开 plex.tv/link，输入下面的代码完成授权。"))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Text(pin.code)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .tracking(8)
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(inputBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(inputBorder, lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityIdentifier("mac.plexSignIn.code")

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button {
                    openAuthPage(pin)
                } label: {
                    Text(L10n.tr("打开 plex.tv/link"))
                }
                .buttonStyle(MacPrimaryActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .focused($focusedAction, equals: .openBrowser)
                .accessibilityIdentifier("mac.plexSignIn.openBrowser")
                .help(L10n.tr("打开 plex.tv/link"))

                Button {
                    copyCode(pin.code)
                } label: {
                    Text(copiedCode ? L10n.tr("已复制") : L10n.tr("复制代码"))
                }
                .buttonStyle(MacSecondaryActionButtonStyle(theme: theme))
                .focused($focusedAction, equals: .copyCode)
                .accessibilityIdentifier("mac.plexSignIn.copyCode")
                .accessibilityLabel(Text(copiedCode ? L10n.tr("已复制") : L10n.tr("复制代码")))
            }

            if model.isCodeExpired {
                Label {
                    Text(L10n.tr("授权代码已过期，请重新获取代码。"))
                        .font(.system(size: 12))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)

                    Text(L10n.tr("等待浏览器授权…"))
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            Button {
                copiedCode = false
                model.retryAuthorization()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.tr("重新获取代码"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(MacDesignTokens.accentBlue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mac.plexSignIn.getNewCode")
        }
    }

    private func serverSelectionContent(_ servers: [PlexServerResource]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.tr("选择 Plex 服务器"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                if let account = model.account {
                    Text(L10n.tr("已登录 Plex 账号：%@", account.username))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }
            }

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(servers) { server in
                        MacPlexServerRow(
                            server: server,
                            isDisabled: model.isSaving,
                            action: {
                                Task { await model.selectServer(server) }
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: PlexSheetMetrics.serverListMaxHeight)
        }
    }

    private func connectingContent(_ serverName: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            Text(L10n.tr("正在连接 %@…", serverName))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }

    private func failedContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.orange)

                Text(L10n.tr("Plex 授权失败"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    copiedCode = false
                    model.retryAuthorization()
                } label: {
                    Text(L10n.tr("重新获取代码"))
                }
                .buttonStyle(MacPrimaryActionButtonStyle())
                .keyboardShortcut(.defaultAction)
                .focused($focusedAction, equals: .retry)
                .accessibilityIdentifier("mac.plexSignIn.retry")

                if model.canReturnToServerSelection {
                    Button {
                        model.backToServerSelection()
                    } label: {
                        Text(L10n.tr("选择 Plex 服务器"))
                    }
                    .buttonStyle(MacSecondaryActionButtonStyle(theme: theme))
                    .accessibilityIdentifier("mac.plexSignIn.backToServers")
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)

            Button(L10n.tr("取消")) {
                cancel()
            }
            .buttonStyle(MacSecondaryActionButtonStyle(theme: theme))
            .keyboardShortcut(.cancelAction)
            // 选定服务器后保存与首次扫描已经开始，中途取消会留下半保存的连接。
            .disabled(model.isSaving)
            .focused($focusedAction, equals: .cancel)
            .accessibilityIdentifier("mac.plexSignIn.cancel")
        }
        .padding(.horizontal, PlexSheetMetrics.horizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: - Actions

    private func openAuthPage(_ pin: PlexPin) {
        openURL(pin.authURL)
    }

    private func copyCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copiedCode = true

        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            copiedCode = false
        }
    }

    private func cancel() {
        copyResetTask?.cancel()
        copyResetTask = nil
        model.cancel()
        dismiss()
    }

    private func finish() {
        copyResetTask?.cancel()
        copyResetTask = nil
        dismiss()
        onFinished()
    }

    // MARK: - Theme Colors

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
            : Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
    }

    private var inputBackground: Color {
        colorScheme == .dark ? Color.black.opacity(0.2) : .white
    }

    private var inputBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255)
    }
}

// MARK: - Sheet Metrics

private enum PlexSheetMetrics {
    static let horizontalPadding: CGFloat = 24
    static let contentMinHeight: CGFloat = 196
    static let serverListMaxHeight: CGFloat = 232
}

// MARK: - Server Row

private struct MacPlexServerRow: View {
    @Environment(\.macTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    let server: PlexServerResource
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(theme.secondaryText)

                VStack(alignment: .leading, spacing: 4) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let version = server.productVersion, !version.isEmpty {
                            Text(version)
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                        }

                        ForEach(connectionBadges, id: \.self) { badge in
                            MacPlexConnectionBadge(title: badge)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? MacDesignTokens.accentBlue.opacity(0.5) : inputBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1)
        .onHover { hovering in
            isHovered = hovering && !isDisabled
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(server.name))
        .accessibilityIdentifier("mac.plexSignIn.server.\(server.clientIdentifier)")
    }

    private var rowBackground: Color {
        if isHovered {
            return MacDesignTokens.accentBlue.opacity(colorScheme == .dark ? 0.18 : 0.08)
        }
        return colorScheme == .dark ? Color.black.opacity(0.2) : .white
    }

    private var inputBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color(red: 209 / 255, green: 213 / 255, blue: 220 / 255)
    }

    /// 一台服务器可能同时暴露局域网、远程与中继端点；按连接能力给出徽标。
    private var connectionBadges: [String] {
        var badges: [String] = []
        if server.connections.contains(where: \.isLocal) {
            badges.append(L10n.tr("本地"))
        }
        if server.connections.contains(where: { !$0.isLocal && !$0.isRelay }) {
            badges.append(L10n.tr("远程"))
        }
        if server.connections.contains(where: \.isRelay) {
            badges.append(L10n.tr("中继"))
        }
        return badges
    }
}

// MARK: - Connection Badge

private struct MacPlexConnectionBadge: View {
    @Environment(\.macTheme) private var theme

    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.chipText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(theme.chipBackground)
            .overlay {
                RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip)
                    .stroke(theme.chipBorder, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: MacDesignTokens.Radius.chip))
    }
}

// MARK: - Sign-In Model

/// PIN 登录状态机。所有阶段都在主线程发布，网络与探测由 `PlexAuthAPI` 承担。
@MainActor
final class MacPlexSignInModel: ObservableObject {
    /// 保存闭包：成功返回 nil，失败返回需要展示给用户的消息。
    typealias SaveHandler = @MainActor (
        _ token: String,
        _ server: PlexServerResource,
        _ endpoint: PlexServerConnection,
        _ account: PlexAccount?
    ) async -> String?

    enum Phase: Equatable {
        case starting
        case waiting(PlexPin)
        case choosingServer([PlexServerResource])
        case connecting(String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var account: PlexAccount?
    @Published private(set) var isCodeExpired = false
    @Published private(set) var isSaving = false
    @Published private(set) var didFinish = false

    private let api: PlexAuthAPI
    private let save: SaveHandler
    private var accountToken: String?
    private var servers: [PlexServerResource] = []
    private var sessionTask: Task<Void, Never>?
    /// 每次重新获取授权码都递增；旧会话收尾时不得清掉新会话的 task 引用。
    private var sessionGeneration = 0

    var canReturnToServerSelection: Bool {
        !servers.isEmpty
    }

    init(api: PlexAuthAPI = PlexAuthAPI(), save: @escaping SaveHandler) {
        self.api = api
        self.save = save
    }

    // MARK: Session

    func start() {
        guard sessionTask == nil else { return }
        sessionGeneration += 1
        let generation = sessionGeneration
        isCodeExpired = false
        phase = .starting
        sessionTask = Task { [weak self] in
            await self?.runAuthorization(generation: generation)
        }
    }

    /// PIN 过期或授权失败后重新获取四位授权码。
    func retryAuthorization() {
        sessionGeneration += 1
        sessionTask?.cancel()
        sessionTask = nil
        accountToken = nil
        account = nil
        servers = []
        isCodeExpired = false
        isSaving = false
        phase = .starting
        start()
    }

    /// 端点探测失败时回到服务器列表，避免整个授权流程重来。
    func backToServerSelection() {
        guard !servers.isEmpty else {
            retryAuthorization()
            return
        }
        phase = .choosingServer(servers)
    }

    func cancel() {
        sessionGeneration += 1
        sessionTask?.cancel()
        sessionTask = nil
        accountToken = nil
        isSaving = false
    }

    private func runAuthorization(generation: Int) async {
        defer {
            if generation == sessionGeneration {
                sessionTask = nil
            }
        }

        do {
            let pin = try await api.createPin()
            try Task.checkCancellation()
            phase = .waiting(pin)

            let authorizedToken = try await api.awaitAuthorization(
                pinId: pin.id,
                timeout: max(5, pin.expiresAt.timeIntervalSinceNow),
                pollInterval: 2
            )
            try Task.checkCancellation()
            accountToken = authorizedToken

            account = try? await api.fetchAccount(token: authorizedToken)

            let discovered = try await api.fetchServers(token: authorizedToken)
            try Task.checkCancellation()
            guard !discovered.isEmpty else {
                throw PlexAuthError.noServer
            }

            let resources = discovered.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            servers = resources
            VanmoLogger.network.info("[MacPlex] Authorization complete, servers=\(resources.count, privacy: .public)")
            phase = .choosingServer(resources)
        } catch let error as PlexAuthError {
            guard !Task.isCancelled else { return }
            switch error {
            case .authorizationCancelled:
                return
            case .pinExpired, .authorizationTimedOut:
                isCodeExpired = true
            default:
                phase = .failed(failureMessage(for: error))
            }
        } catch is CancellationError {
            // 用户取消：无需再更新界面。
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(failureMessage(for: error))
        }
    }

    // MARK: Server Selection

    func selectServer(_ server: PlexServerResource) async {
        guard !isSaving, let accountToken else { return }
        isSaving = true
        phase = .connecting(server.name)

        // 共享服务器的 accessToken 优先；自有服务器沿用账号 token。
        let token = server.effectiveToken(accountToken: accountToken)

        do {
            let endpoint = try await api.resolveEndpoint(for: server, token: token)
            try Task.checkCancellation()
            if let failure = await save(token, server, endpoint, account) {
                phase = .failed(failure)
            } else {
                VanmoLogger.network.info("[MacPlex] Connection saved and selected")
                didFinish = true
            }
        } catch is CancellationError {
            // 用户取消或关闭 sheet：保持静默。
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(failureMessage(for: error))
        }

        isSaving = false
    }

    // MARK: Messages

    private func failureMessage(for error: Error) -> String {
        if let authError = error as? PlexAuthError, authError == .noServer {
            return L10n.tr("未找到可用的 Plex 服务器。请确认该 Plex 账号至少有一台可访问的媒体服务器。")
        }
        // error.localizedDescription 由 PlexAuthError 提供，保持原样，不做翻译。
        return "\(L10n.tr("Plex 授权失败"))\n\(error.localizedDescription)"
    }
}