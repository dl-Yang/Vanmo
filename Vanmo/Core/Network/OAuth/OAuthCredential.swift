import Foundation

/// 通用 OAuth 2.0 凭据（Authorization Code 授权码流程产出），按 connectionId 存入 Keychain。
struct OAuthCredential: Codable, Sendable {
    let provider: ConnectionType
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var tokenType: String
    var scope: String?
    /// 部分网盘（如 pCloud）登录后需要固定到特定数据中心 host，登录时一并记录。
    var apiHost: String?

    var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }

    var authorizationHeaderValue: String {
        "\(tokenType) \(accessToken)"
    }
}

enum OAuthCredentialStore {
    static func save(_ credential: OAuthCredential, connectionId: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        try KeychainManager.shared.save(data, for: key(for: connectionId))
    }

    static func load(connectionId: UUID) throws -> OAuthCredential? {
        guard let data = try KeychainManager.shared.load(for: key(for: connectionId)) else {
            return nil
        }
        return try JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    static func delete(connectionId: UUID) throws {
        try KeychainManager.shared.delete(for: key(for: connectionId))
    }

    private static func key(for connectionId: UUID) -> String {
        "conn_\(connectionId)_oauth"
    }
}
