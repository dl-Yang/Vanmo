import Foundation

/// 通用 OAuth 2.0 凭据（Authorization Code 授权码流程产出），按 connectionId 存入 Keychain。
public struct OAuthCredential: Codable, Sendable {
    public let provider: ConnectionType
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var tokenType: String
    public var scope: String?
    /// 部分网盘（如 pCloud）登录后需要固定到特定数据中心 host，登录时一并记录。
    public var apiHost: String?

    public var isExpired: Bool {
        Date().addingTimeInterval(60) >= expiresAt
    }

    public var authorizationHeaderValue: String {
        "\(tokenType) \(accessToken)"
    }
}

public enum OAuthCredentialStore {
    public static func save(_ credential: OAuthCredential, connectionId: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        try KeychainManager.shared.save(data, for: key(for: connectionId))
    }

    public static func load(connectionId: UUID) throws -> OAuthCredential? {
        guard let data = try KeychainManager.shared.load(for: key(for: connectionId)) else {
            return nil
        }
        return try JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    public static func delete(connectionId: UUID) throws {
        try KeychainManager.shared.delete(for: key(for: connectionId))
    }

    private static func key(for connectionId: UUID) -> String {
        "conn_\(connectionId)_oauth"
    }
}
