import AuthenticationServices
import UIKit
import VanmoCore
import YandexLoginSDK

/// 通过 YandexLoginSDK 登录 Yandex.Disk：装有 Yandex App 时跳转 App 授权，否则走 SDK 内置网页授权。
///
/// SDK 只返回 access token（无 refresh token、无过期时间），服务端 401 后由现有流程提示重新登录。
@MainActor
final class YandexLoginAuthenticator: OAuthExternalAuthenticator {
    static let shared = YandexLoginAuthenticator()

    /// SDK token 不带过期时间，与通用 OAuth 流程缺省 `expires_in` 时的长期默认值保持一致。
    private static let assumedTokenLifetime: TimeInterval = 100 * 365 * 24 * 3600

    private var pending: (attemptID: UUID, continuation: CheckedContinuation<LoginResult, Error>)?

    private init() {}

    private static var cancelledError: NetworkError {
        .connectionFailed("已取消授权")
    }

    /// 激活失败（如 Info.plist 缺少 SDK scheme）时不注册，Yandex.Disk 回落到通用 PKCE 网页授权。
    func activate() {
        let clientID = OAuthProviderConfiguration.clientID(for: .yandexDisk)
        guard !clientID.isEmpty else { return }
        do {
            try YandexLoginSDK.shared.activate(with: clientID, authorizationStrategy: .default)
        } catch {
            let reason = Self.describe(error)
            VanmoLogger.network.error("[YandexLogin] activate failed: \(reason, privacy: .public)")
            return
        }
        // SDK 在内部串行队列上同步遍历 observer，回调里增删 observer 会死锁，所以只在启动时注册一次。
        YandexLoginSDK.shared.add(observer: self)
        OAuthCoordinator.shared.externalAuthenticators[.yandexDisk] = self
    }

    // SDK 的 try* 包装在回调带 error、state 校验失败时只返回 false 而不通知 observer，
    // 所以这里改用会抛错的版本，失败时主动结束等待中的授权。
    func handleOpenURL(_ url: URL) -> Bool {
        guard YandexLoginSDK.shared.isURLRelatedToSDK(url: url) else { return false }
        do {
            try YandexLoginSDK.shared.handleOpenURL(url)
        } catch {
            finishPending(with: .failure(error))
        }
        return true
    }

    func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
        let clientID = OAuthProviderConfiguration.clientID(for: .yandexDisk)
        guard userActivity.webpageURL?.host?.hasPrefix("yx\(clientID).") == true else { return false }
        do {
            try YandexLoginSDK.shared.handleUserActivity(userActivity)
        } catch {
            finishPending(with: .failure(error))
        }
        return true
    }

    func authenticate(type: ConnectionType) async throws -> OAuthCredential {
        guard let presenter = Self.topViewController() else {
            throw NetworkError.connectionFailed("无法展示 Yandex 授权界面")
        }
        // 跳转 Yandex App 后用户可能不回来，上一次未完成的授权在这里结束掉，避免 continuation 泄漏。
        finishPending(with: .failure(Self.cancelledError))
        // SDK 会缓存上次的登录结果并直接返回；先清掉，保证新建连接/重新授权都真正走授权页。
        try YandexLoginSDK.shared.logout()

        let attemptID = UUID()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending = (attemptID, continuation)
                do {
                    try YandexLoginSDK.shared.authorize(with: presenter, authorizationStrategy: .default)
                } catch {
                    finishPending(with: .failure(error))
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.finishPending(attemptID: attemptID, with: .failure(Self.cancelledError))
            }
        }
        // token 只保留在 OAuthCredentialStore，不在 SDK 自己的 Keychain 里多留一份。
        try? YandexLoginSDK.shared.logout()

        return OAuthCredential(
            provider: type,
            accessToken: result.token,
            refreshToken: "",
            expiresAt: Date().addingTimeInterval(Self.assumedTokenLifetime),
            tokenType: "OAuth",
            scope: nil,
            apiHost: nil
        )
    }

    /// `attemptID` 非空时只结束对应那一次授权，避免旧任务迟到的取消误伤新一次登录。
    private func finishPending(attemptID: UUID? = nil, with result: Result<LoginResult, Error>) {
        guard let current = pending, attemptID == nil || current.attemptID == attemptID else { return }
        pending = nil
#if DEBUG
        let outcome = Self.debugOutcome(result)
        VanmoLogger.network.info("[Debug][YandexLogin] finish outcome=\(outcome, privacy: .public)")
#endif
        let continuation = current.continuation
        switch result {
        case .success(let loginResult):
            continuation.resume(returning: loginResult)
        case .failure(let error):
            continuation.resume(throwing: Self.mapError(error))
        }
    }

    private static func mapError(_ error: Error) -> Error {
        if error is NetworkError {
            return error
        }
        let nsError = error as NSError
        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
            return NetworkError.connectionFailed("已取消授权")
        }
        let reason = describe(error)
        VanmoLogger.network.error("[YandexLogin] authorize failed: \(reason, privacy: .public)")
        return NetworkError.connectionFailed("Yandex.Disk 授权失败: \(reason)")
    }

    /// SDK 的 `message` 可能原样带出响应 JSON 或请求参数（含 token / code），只暴露错误类型与 code。
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(String(describing: type(of: error))) \(nsError.domain)#\(nsError.code)"
    }

#if DEBUG
    private static func debugOutcome(_ result: Result<LoginResult, Error>) -> String {
        switch result {
        case .success:
            return "success"
        case .failure(let error):
            return "failure \(describe(error))"
        }
    }
#endif

    private static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var controller = keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

extension YandexLoginAuthenticator: YandexLoginSDKObserver {
    nonisolated func didFinishLogin(with result: Result<LoginResult, any Error>) {
        Task { @MainActor in
            self.finishPending(with: result)
        }
    }
}
