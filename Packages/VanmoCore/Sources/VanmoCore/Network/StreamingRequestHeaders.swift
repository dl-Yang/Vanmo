import Foundation

/// Shared header provider for Google Drive Bearer and Baidu Netdisk User-Agent.
public enum StreamingRequestHeaders {
    public static func provider(
        for type: ConnectionType,
        connectionId: UUID
    ) -> (() async -> [String: String])? {
        guard type.requiresStreamingHeaderProvider else { return nil }
        switch type {
        case .googleDrive:
            return {
                guard let token = try? await OAuthCoordinator.shared.validAccessToken(
                    for: .googleDrive,
                    connectionId: connectionId
                ) else {
                    return [:]
                }
                return ["Authorization": "Bearer \(token)"]
            }
        case .baiduNetdisk:
            return {
                ["User-Agent": BaiduNetdiskService.requiredUserAgent]
            }
        default:
            return nil
        }
    }
}
