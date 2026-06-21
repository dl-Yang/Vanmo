import Foundation

struct CastMemberInfo: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let role: String?
    let profileRemoteURL: URL?

    var names: String { name }

    func makeCachedMember() -> CachedCastMember {
        CachedCastMember(
            id: id,
            name: name,
            role: role,
            profileLocalPath: nil,
            profileRemoteURL: profileRemoteURL
        )
    }
}

struct CachedCastMember: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String?
    let profileLocalPath: String?
    let profileRemoteURL: URL?

    func resolvedProfileURL(rootDirectory: URL) -> URL? {
        if let path = profileLocalPath {
            return rootDirectory.appendingPathComponent(path)
        }
        return profileRemoteURL
    }
}

struct CastMemberDisplay: Identifiable, Hashable {
    let id: String
    let name: String
    let role: String?
    let profileURL: URL?
}
