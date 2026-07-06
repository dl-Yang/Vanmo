import Foundation

public struct CastMemberInfo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let role: String?
    public let profileRemoteURL: URL?

    public var names: String { name }

    public func makeCachedMember() -> CachedCastMember {
        CachedCastMember(
            id: id,
            name: name,
            role: role,
            profileLocalPath: nil,
            profileRemoteURL: profileRemoteURL
        )
    }
}

public struct CachedCastMember: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let role: String?
    public let profileLocalPath: String?
    public let profileRemoteURL: URL?

    public func resolvedProfileURL(rootDirectory: URL) -> URL? {
        if let path = profileLocalPath {
            return rootDirectory.appendingPathComponent(path)
        }
        return profileRemoteURL
    }
}

public struct CastMemberDisplay: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let role: String?
    public let profileURL: URL?

    public init(id: String, name: String, role: String?, profileURL: URL?) {
        self.id = id; self.name = name; self.role = role; self.profileURL = profileURL
    }
}
