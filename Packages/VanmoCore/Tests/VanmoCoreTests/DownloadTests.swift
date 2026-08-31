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
        XCTAssertTrue(DownloadEligibility.isSupported(connectionType: .ftp))
        XCTAssertFalse(DownloadEligibility.isSupported(connectionType: .sftp))
        XCTAssertTrue(DownloadEligibility.isEligible(file: iso, connectionType: .ftp))
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

    func testLegacyRequestDecodesWithoutSourceIdentityFields() throws {
        let request = DownloadRequest(
            sourceConnectionId: UUID(),
            connectionType: .webdav,
            remotePath: "/Movies/Movie.mkv",
            fileName: "Movie.mkv",
            displayTitle: "Movie",
            mediaType: .movie
        )
        let encoder = JSONEncoder()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        )
        object.removeValue(forKey: "sourceMediaItemID")
        object.removeValue(forKey: "sourceServerID")
        object.removeValue(forKey: "seriesServerID")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(DownloadRequest.self, from: legacyData)

        XCTAssertNil(decoded.sourceMediaItemID)
        XCTAssertNil(decoded.sourceServerID)
        XCTAssertNil(decoded.seriesServerID)
    }

    @MainActor
    func testEpisodeRequestPreservesSeriesIdentity() throws {
        let connectionID = UUID()
        let show = MediaItem(
            title: "Example Show",
            fileURL: URL(fileURLWithPath: "/shows/example"),
            mediaType: .tvShow
        )
        show.sourceConnectionId = connectionID
        show.serverId = "series-42"
        show.posterURL = URL(string: "https://example.com/poster.jpg")
        let episode = EpisodeInfo(
            id: "episode-7",
            title: "Pilot",
            seasonNumber: 1,
            episodeNumber: 7,
            duration: 2_400,
            overview: nil,
            streamURL: URL(string: "https://example.com/episode-7.mkv")!,
            backdropURL: nil
        )

        let request = try DownloadRequestFactory.make(
            from: episode,
            show: show,
            connectionType: .emby
        )

        XCTAssertEqual(request.sourceMediaItemID, show.id)
        XCTAssertEqual(request.sourceServerID, episode.id)
        XCTAssertEqual(request.seriesServerID, show.serverId)
        XCTAssertEqual(request.postUrl, show.posterURL)
    }

    @MainActor
    func testBatchEnqueueDeduplicatesAndSupportsPauseResume() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VanmoDownloadManagerTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = DownloadManager(storeRootDirectory: root)
        await manager.suspend()

        let first = downloadRequest(path: "/share/episode-1.mkv")
        let second = downloadRequest(path: "/share/episode-2.mkv")
        let duplicate = downloadRequest(path: first.remotePath)
        let ids = try await manager.enqueue([first, second, duplicate])

        XCTAssertEqual(manager.tasks.count, 2)
        XCTAssertEqual(ids[0], ids[2])
        XCTAssertEqual(
            manager.tasks.min(by: { $0.createdAt < $1.createdAt })?.request.remotePath,
            first.remotePath
        )
        XCTAssertTrue(manager.hasPausableTasks)

        await manager.pauseAll()
        XCTAssertTrue(manager.tasks.allSatisfy { $0.status == .paused })
        XCTAssertTrue(manager.hasResumableTasks)
        let storedPausedTasks = try await DownloadTaskStore(rootDirectory: root).load()
        XCTAssertTrue(storedPausedTasks.allSatisfy { $0.status == .paused })

        await manager.resumeAll()
        XCTAssertTrue(manager.tasks.allSatisfy { $0.status == .queued })
        await manager.pause(ids[0])
        XCTAssertEqual(manager.tasks.first(where: { $0.id == ids[0] })?.status, .paused)
        await manager.resume(ids[0])
        XCTAssertEqual(manager.tasks.first(where: { $0.id == ids[0] })?.status, .queued)
    }

    func testStaleSimulatorContainerDownloadPathRelocatesToCurrentDefault() {
        let current = URL(fileURLWithPath: "/tmp/current-container/Documents/Downloads", isDirectory: true)
        let stale = "/Users/test/Library/Developer/CoreSimulator/Devices/AAAA/data/Containers/Data/Application/OLD/Documents/Downloads"
        let remapped = DownloadDirectoryResolver.relocatedSandboxDirectory(
            for: stale,
            currentDefault: current
        )
        XCTAssertEqual(remapped, current)

        let custom = DownloadDirectoryResolver.relocatedSandboxDirectory(
            for: "/Users/test/Movies",
            currentDefault: current
        )
        XCTAssertEqual(custom.path, "/Users/test/Movies")
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

    private func downloadRequest(path: String) -> DownloadRequest {
        DownloadRequest(
            sourceConnectionId: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
            connectionType: .smb,
            remotePath: path,
            fileName: URL(fileURLWithPath: path).lastPathComponent,
            displayTitle: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            mediaType: .tvEpisode
        )
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
