import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// 通用 OAuth 2.0 授权码流程协调器，服务于走标准 OAuth2 + REST 的国际网盘
/// （Google Drive / OneDrive / Box / pCloud / Yandex.Disk）。
///
/// 公共客户端（Google / OneDrive）使用 PKCE，不在 App 内嵌 Client Secret；
/// 其余网盘按其开放平台要求使用 Client Secret 换取 token。
@MainActor
final class OAuthCoordinator: NSObject {
    static let shared = OAuthCoordinator()

    private var session: ASWebAuthenticationSession?

    private override init() {}

    func authenticate(type: ConnectionType) async throws -> OAuthCredential {
        guard type.isOAuthCloudDrive else {
            throw NetworkError.unsupportedProtocol
        }
        guard OAuthProviderConfiguration.isConfigured(for: type) else {
            throw NetworkError.connectionFailed(
                "\(type.displayName) 尚未配置开发者凭据：\(OAuthProviderConfiguration.missingCredentialHint(for: type))"
            )
        }

        let state = UUID().uuidString
        let pkce = OAuthProviderConfiguration.usesPKCE(for: type) ? PKCEPair.generate() : nil

        let authorizationURL = try makeAuthorizationURL(type: type, state: state, pkce: pkce)
        let callbackURL = try await startAuthenticationSession(url: authorizationURL, type: type)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              OAuthProviderConfiguration.matchesCallback(components, type: type) else {
            throw NetworkError.authenticationFailed
        }

        if let errorParam = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw NetworkError.connectionFailed("\(type.displayName) 授权失败: \(errorParam)")
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw NetworkError.authenticationFailed
        }
        guard components.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw NetworkError.authenticationFailed
        }

        return try await exchangeCodeForToken(code: code, type: type, codeVerifier: pkce?.verifier)
    }

    /// 返回可用的 access token；若已过期则先用 refresh_token 换新并写回 Keychain。
    ///
    /// - Parameter forceRefresh: 服务端已经用一个"本地看起来还没过期"的 token 返回 401 时
    ///   （token 被撤销、服务端提前失效、本地过期时间估算不准等），调用方应该传 `true`
    ///   强制换新，而不是原样返回同一个必然还会 401 的 token。
    func validAccessToken(for type: ConnectionType, connectionId: UUID, forceRefresh: Bool = false) async throws -> String {
        guard let credential = try OAuthCredentialStore.load(connectionId: connectionId) else {
            throw NetworkError.authenticationFailed
        }
        guard forceRefresh || credential.isExpired else {
            return credential.accessToken
        }
        let refreshed = try await refresh(credential, type: type, connectionId: connectionId)
        return refreshed.accessToken
    }

    func refresh(_ credential: OAuthCredential, type: ConnectionType, connectionId: UUID) async throws -> OAuthCredential {
        guard !credential.refreshToken.isEmpty else {
            throw NetworkError.authenticationFailed
        }
        guard let tokenURL = OAuthProviderConfiguration.tokenEndpoint(for: type) else {
            throw NetworkError.unsupportedProtocol
        }

        var items = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credential.refreshToken),
            URLQueryItem(name: "client_id", value: OAuthProviderConfiguration.clientID(for: type)),
        ]
        if let secret = OAuthProviderConfiguration.clientSecret(for: type), !secret.isEmpty {
            items.append(URLQueryItem(name: "client_secret", value: secret))
        }

        let response = try await requestToken(url: tokenURL, formItems: items)
        let refreshedCredential = response.makeCredential(
            provider: type,
            fallbackRefreshToken: credential.refreshToken,
            apiHost: credential.apiHost
        )
        try OAuthCredentialStore.save(refreshedCredential, connectionId: connectionId)
        return refreshedCredential
    }

    // MARK: - Authorization URL

    private func makeAuthorizationURL(type: ConnectionType, state: String, pkce: PKCEPair?) throws -> URL {
        guard let endpoint = OAuthProviderConfiguration.authorizationEndpoint(for: type) else {
            throw NetworkError.unsupportedProtocol
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "client_id", value: OAuthProviderConfiguration.clientID(for: type)),
            URLQueryItem(name: "redirect_uri", value: OAuthProviderConfiguration.redirectURI(for: type)),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
        ]
        let scope = OAuthProviderConfiguration.scope(for: type)
        if !scope.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scope))
        }
        if type == .googleDrive {
            items.append(URLQueryItem(name: "access_type", value: "offline"))
            items.append(URLQueryItem(name: "include_granted_scopes", value: "true"))
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        } else if type == .oneDrive {
            // 使用离线访问以拿到 refresh_token。
            items.append(URLQueryItem(name: "prompt", value: "select_account"))
        }
        if let pkce {
            items.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        } else if type != .googleDrive && type != .oneDrive {
            items.append(URLQueryItem(name: "access_type", value: "offline"))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw NetworkError.invalidURL }
        return url
    }

    // MARK: - Token exchange

    private func exchangeCodeForToken(code: String, type: ConnectionType, codeVerifier: String?) async throws -> OAuthCredential {
        guard let tokenURL = OAuthProviderConfiguration.tokenEndpoint(for: type) else {
            throw NetworkError.unsupportedProtocol
        }

        var items = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: OAuthProviderConfiguration.clientID(for: type)),
            URLQueryItem(name: "redirect_uri", value: OAuthProviderConfiguration.redirectURI(for: type)),
        ]
        if let codeVerifier {
            items.append(URLQueryItem(name: "code_verifier", value: codeVerifier))
        }
        if let secret = OAuthProviderConfiguration.clientSecret(for: type), !secret.isEmpty {
            items.append(URLQueryItem(name: "client_secret", value: secret))
        }

        let response = try await requestToken(url: tokenURL, formItems: items)
        return response.makeCredential(provider: type, fallbackRefreshToken: "", apiHost: nil)
    }

    private func requestToken(url: URL, formItems: [URLQueryItem]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formItems.formURLEncodedData
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NetworkError.connectionFailed(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.connectionFailed("Invalid response type")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw NetworkError.connectionFailed("OAuth token 请求失败 (\(httpResponse.statusCode)): \(body)")
        }

        do {
            return try JSONDecoder.oauth.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw NetworkError.transferFailed("OAuth token 响应解析失败: \(error.localizedDescription)")
        }
    }

    // MARK: - ASWebAuthenticationSession

    private func startAuthenticationSession(url: URL, type: ConnectionType) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: OAuthProviderConfiguration.callbackURLScheme(for: type)
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: NetworkError.connectionFailed("已取消授权"))
                    } else {
                        continuation.resume(throwing: NetworkError.connectionFailed(error.localizedDescription))
                    }
                } else {
                    continuation.resume(throwing: NetworkError.authenticationFailed)
                }
            }

            authSession.presentationContextProvider = self
            authSession.prefersEphemeralWebBrowserSession = true
            session = authSession

            if !authSession.start() {
                continuation.resume(throwing: NetworkError.connectionFailed("无法启动 OAuth 授权会话"))
            }
        }
    }
}

extension OAuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - PKCE

private struct PKCEPair {
    let verifier: String
    let challenge: String

    static func generate() -> PKCEPair {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URLEncodedString()

        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()

        return PKCEPair(verifier: verifier, challenge: challenge)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token response

private struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let tokenType: String?
    let scope: String?
    /// pCloud 专用：登录返回的数据中心 host（`api.pcloud.com` 或 `eapi.pcloud.com`），
    /// 其余网盘响应里没有这个字段，解码时会被忽略。
    let hostname: String?

    func makeCredential(provider: ConnectionType, fallbackRefreshToken: String, apiHost: String?) -> OAuthCredential {
        // 部分网盘（如 pCloud）默认不返回 expires_in，视为长期有效（100 年）。
        let expiresIn = expiresIn ?? (100 * 365 * 24 * 3600)
        return OAuthCredential(
            provider: provider,
            accessToken: accessToken,
            refreshToken: refreshToken ?? fallbackRefreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            tokenType: tokenType ?? "Bearer",
            scope: scope,
            apiHost: hostname ?? apiHost
        )
    }
}

private extension JSONDecoder {
    static var oauth: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

private extension Array where Element == URLQueryItem {
    var formURLEncodedData: Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
