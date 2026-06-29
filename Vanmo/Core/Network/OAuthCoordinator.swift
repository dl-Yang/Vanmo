import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class OAuthCoordinator {
    static let shared = OAuthCoordinator()

    private let callbackProvider = OAuthPresentationContextProvider()
    private var session: ASWebAuthenticationSession?

    private init() {}

    func authenticate(type: ConnectionType, host: String) async throws -> OAuthCredential {
        guard type.isOfficialCloudDrive else {
            throw NetworkError.unsupportedProtocol
        }
        guard type == .aliyunDrive else {
            throw NetworkError.unsupportedProtocol
        }
        guard OAuthProviderConfiguration.isConfigured(for: type) else {
            throw NetworkError.connectionFailed("\(type.displayName) OAuth 尚未配置 client id，请先在 OAuthProviderConfiguration 中填写开放平台参数。")
        }
        let state = UUID().uuidString
        let authorizationURL = try authorizationURL(type: type, host: host, state: state)

        let callbackURL = try await startAuthenticationSession(url: authorizationURL)
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              isExpectedCallback(components, type: type),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw NetworkError.authenticationFailed
        }
        guard components.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw NetworkError.authenticationFailed
        }

        return try await exchangeCodeForToken(code, type: type, host: host)
    }

    private func startAuthenticationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: OAuthProviderConfiguration.redirectScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    continuation.resume(throwing: NetworkError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: NetworkError.authenticationFailed)
                }
            }

            authSession.presentationContextProvider = callbackProvider
            authSession.prefersEphemeralWebBrowserSession = true
            session = authSession

            if !authSession.start() {
                continuation.resume(throwing: NetworkError.connectionFailed("无法启动 OAuth 授权会话"))
            }
        }
    }

    private func authorizationURL(type: ConnectionType, host: String, state: String) throws -> URL {
        switch type {
        case .aliyunDrive:
            let url = try AliyunDriveEndpoint.apiURL(from: host, path: "/v2/oauth/authorize")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [
                URLQueryItem(name: "client_id", value: OAuthProviderConfiguration.clientID(for: type)),
                URLQueryItem(name: "redirect_uri", value: OAuthProviderConfiguration.redirectURI(for: type)),
                URLQueryItem(name: "scope", value: OAuthProviderConfiguration.scope(for: type)),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "state", value: state),
            ]
            guard let url = components?.url else { throw NetworkError.invalidURL }
            return url
        default:
            throw NetworkError.unsupportedProtocol
        }
    }

    private func exchangeCodeForToken(_ code: String, type: ConnectionType, host: String) async throws -> OAuthCredential {
        switch type {
        case .aliyunDrive:
            let clientID = OAuthProviderConfiguration.clientID(for: type)
            var items = [
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: OAuthProviderConfiguration.redirectURI(for: type)),
            ]
            if let secret = OAuthProviderConfiguration.clientSecret(for: type), !secret.isEmpty {
                items.append(URLQueryItem(name: "client_secret", value: secret))
            }

            let token = try await AliyunDriveTokenClient.requestToken(host: host, formItems: items)
            return token.makeCredential(provider: type)
        default:
            throw NetworkError.unsupportedProtocol
        }
    }

    private func isExpectedCallback(_ components: URLComponents, type: ConnectionType) -> Bool {
        components.scheme == OAuthProviderConfiguration.redirectScheme &&
            components.host == OAuthProviderConfiguration.redirectHost &&
            components.path == "/\(type.rawValue)"
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
