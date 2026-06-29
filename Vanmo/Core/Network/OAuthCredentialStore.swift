import Foundation

struct OAuthCredential: Codable, Sendable {
    let provider: ConnectionType
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var tokenType: String
    var scope: String?
    var userID: String?
    var defaultDriveID: String?
    var domainID: String?

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

    static func encodedString(_ credential: OAuthCredential) throws -> String {
        let data = try JSONEncoder().encode(credential)
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return value
    }

    static func decodedCredential(from value: String) throws -> OAuthCredential {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return try JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    private static func key(for connectionId: UUID) -> String {
        "conn_\(connectionId)_oauth"
    }
}

enum OAuthProviderConfiguration {
    static func clientID(for type: ConnectionType) -> String {
        switch type {
        case .aliyunDrive:
            return ""
        case .baiduNetdisk:
            return ""
        case .drive115:
            return ""
        case .quarkDrive:
            return ""
        default:
            return ""
        }
    }

    static func clientSecret(for type: ConnectionType) -> String? {
        switch type {
        case .aliyunDrive:
            return nil
        case .baiduNetdisk:
            return nil
        case .drive115:
            return nil
        case .quarkDrive:
            return nil
        default:
            return nil
        }
    }

    static func scope(for type: ConnectionType) -> String {
        switch type {
        case .aliyunDrive:
            return "user:base,file:all:read"
        case .baiduNetdisk:
            return "basic,netdisk"
        case .drive115, .quarkDrive:
            return ""
        default:
            return ""
        }
    }

    static let redirectScheme = "vanmo"
    static let redirectHost = "oauth"

    static func redirectURI(for type: ConnectionType) -> String {
        "\(redirectScheme)://\(redirectHost)/\(type.rawValue)"
    }

    static func isConfigured(for type: ConnectionType) -> Bool {
        !clientID(for: type).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
