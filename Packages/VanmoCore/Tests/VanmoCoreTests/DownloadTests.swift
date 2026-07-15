import XCTest
@testable import VanmoCore

final class DownloadTests: XCTestCase {
    func testEligibilityExcludesStreamsAndBDMVButAllowsISO() {
        let iso = remoteFile(name: "Movie.iso", path: "/Movies/Movie.iso")
        let playlist = remoteFile(name: "Movie.m3u8", path: "/Movies/Movie.m3u8")
        let bdmv = remoteFile(name: "00001.m2ts", path: "/Movie/BDMV/STREAM/00001.m2ts")

        XCTAssertTrue(DownloadEligibility.isEligible(file: iso, connectionType: .smb))
        XCTAssertFalse(DownloadEligibility.isEligible(file: playlist, connectionType: .webdav))
        XCTAssertFalse(DownloadEligibility.isEligible(file: bdmv, connectionType: .smb))
        XCTAssertFalse(DownloadEligibility.isEligible(file: iso, connectionType: .iptv))
    }

    func testDownloadSnapshotRoundTripsThroughManifest() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VanmoDownloadTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadTaskStore(rootDirectory: root)
        let request = DownloadRequest(
            sourceConnectionId: UUID(),
            connectionType: .webdav,
            remotePath: "/Movies/Movie.mkv",
            fileName: "Movie.mkv",
            displayTitle: "Movie",
            mediaType: .movie,
            totalBytes: 1_024
        )
        let snapshot = DownloadTaskSnapshot(
            request: request,
            destination: DownloadDestination(rootPath: "/tmp"),
            status: .downloading,
            receivedBytes: 512
        )

        try await store.save([snapshot])
        let restored = try await store.load()

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, snapshot.id)
        XCTAssertEqual(restored.first?.request, snapshot.request)
        XCTAssertEqual(restored.first?.receivedBytes, 512)
        XCTAssertEqual(restored.first?.status, .downloading)
    }

    func testRequestSanitizesFileNameAndHasStableSourceKey() {
        let connectionID = UUID()
        let request = DownloadRequest(
            sourceConnectionId: connectionID,
            connectionType: .smb,
            remotePath: "/share/a.mkv",
            fileName: "A/B:mkv",
            displayTitle: "A",
            mediaType: .movie
        )

        XCTAssertEqual(request.fileName, "A_B_mkv")
        XCTAssertEqual(request.sourceKey, "\(connectionID.uuidString):/share/a.mkv")
    }

    @MainActor
    func testPlexMediaRequestKeepsStablePartPathWithoutToken() throws {
        let item = MediaItem(
            title: "Movie",
            fileURL: URL(string: "https://plex.local/library/parts/42/file.mkv?X-Plex-Token=secret")!,
            mediaType: .movie
        )
        item.sourceConnectionId = UUID()
        item.serverId = "rating-key"
        item.originalFileName = "Movie.mkv"

        let request = try DownloadRequestFactory.make(from: item, connectionType: .plex)

        XCTAssertEqual(request.remotePath, "/library/parts/42/file.mkv")
        XCTAssertNil(request.sourceFileURL)
    }

    private func remoteFile(name: String, path: String) -> RemoteFile {
        RemoteFile(
            name: name,
            path: path,
            size: 1_024,
            isDirectory: false,
            modifiedDate: nil,
            type: .video
        )
    }
}
