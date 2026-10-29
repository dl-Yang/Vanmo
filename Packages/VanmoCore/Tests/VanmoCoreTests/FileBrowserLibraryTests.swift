import SwiftData
import XCTest
@testable import VanmoCore

final class FileBrowserLibraryTests: XCTestCase {
    private let poster = URL(string: "https://img.example/poster.jpg")!
    private let backdrop = URL(string: "https://img.example/backdrop.jpg")!
    private let remotePoster = URL(string: "https://emby.example/Items/1/Images/Primary")!
    private let remoteBackdrop = URL(string: "https://emby.example/Items/1/Images/Backdrop/0")!

    // MARK: - Cover order

    func testArtworkOrderIsPosterThenBackdrop() {
        let file = makeFile(posterURL: remotePoster, backdropURL: remoteBackdrop)
        let library = FileLibraryState(posterURL: poster, backdropURL: backdrop)
        XCTAssertEqual(
            FileCoverResolver.artworkCandidates(for: file, library: library),
            [poster, remotePoster, backdrop, remoteBackdrop]
        )
    }

    func testArtworkFallsBackToRemoteBackdropAndDeduplicates() {
        let file = makeFile(backdropURL: remoteBackdrop)
        let library = FileLibraryState(backdropURL: remoteBackdrop)
        XCTAssertEqual(FileCoverResolver.artworkCandidates(for: file, library: library), [remoteBackdrop])
    }

    func testNoArtworkLeavesExtractionToTheCaller() {
        XCTAssertTrue(FileCoverResolver.artworkCandidates(for: makeFile(), library: nil).isEmpty)
    }

    // MARK: - Progress

    func testLocalProgressWinsOverServerProgress() {
        let file = makeFile(playbackPosition: 10, runtime: 100)
        let library = FileLibraryState(playbackPosition: 50, duration: 100)
        XCTAssertEqual(
            FileCoverResolver.progress(for: file, library: library),
            FileWatchProgress(fraction: 0.5, isWatched: false)
        )
    }

    func testLocalPositionUsesServerRuntimeWhenLocalDurationIsMissing() {
        let file = makeFile(runtime: 200)
        XCTAssertEqual(
            FileCoverResolver.progress(for: file, library: FileLibraryState(playbackPosition: 50)),
            FileWatchProgress(fraction: 0.25, isWatched: false)
        )
    }

    func testServerProgressIsUsedWithoutLocalProgress() {
        let file = makeFile(playbackPosition: 25, runtime: 100)
        XCTAssertEqual(
            FileCoverResolver.progress(for: file, library: FileLibraryState()),
            FileWatchProgress(fraction: 0.25, isWatched: false)
        )
    }

    func testWatchedAndUnknownDuration() {
        XCTAssertEqual(
            FileCoverResolver.progress(for: makeFile(isPlayed: true), library: nil),
            FileWatchProgress(fraction: 1, isWatched: true)
        )
        XCTAssertNil(FileCoverResolver.progress(for: makeFile(playbackPosition: 30), library: nil))
        XCTAssertNil(FileCoverResolver.progress(for: makeFile(), library: nil))
    }

    // MARK: - Library matching

    @MainActor
    func testStatesMatchByConnectionAndPath() throws {
        let context = try makeContext()
        let connectionId = UUID()
        let item = makeItem(path: "/Movies/a.mkv", connectionId: connectionId)
        item.lastPlaybackPosition = 30
        item.duration = 120
        item.posterURL = poster
        context.insert(item)
        context.insert(makeItem(path: "/Movies/a.mkv", connectionId: UUID()))
        try context.save()

        let states = FileBrowserLibrary.states(
            connectionId: connectionId,
            paths: ["/Movies/a.mkv", "/Movies/b.mkv"],
            in: context
        )
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states["/Movies/a.mkv"], FileLibraryState(posterURL: poster, playbackPosition: 30, duration: 120))
    }

    @MainActor
    func testPersistentItemReusesExistingItemAndKeepsCatalogPlaceholder() throws {
        let context = try makeContext()
        let connectionId = UUID()
        let placeholder = ConnectionType.smb.catalogPlaybackURL(serverPath: "/Movies/a.mkv")
        let existing = makeItem(path: "/Movies/a.mkv", connectionId: connectionId)
        existing.fileURL = placeholder
        existing.lastPlaybackPosition = 42
        context.insert(existing)
        try context.save()

        let candidate = MediaItem(title: "a", fileURL: URL(string: "smb://user:secret@nas.local/Movies/a.mkv")!)
        let resolved = FileBrowserLibrary.persistentItem(
            for: makeFile(path: "/Movies/a.mkv"),
            candidate: candidate,
            connectionId: connectionId,
            connectionType: .smb,
            in: context
        )

        XCTAssertEqual(resolved.id, existing.id)
        XCTAssertEqual(resolved.fileURL, placeholder)
        XCTAssertEqual(resolved.lastPlaybackPosition, 42)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 1)
    }

    @MainActor
    func testFileConnectionInsertPersistsOnlyCatalogPlaceholder() throws {
        let context = try makeContext()
        let connectionId = UUID()
        let candidate = makeItem(path: "/Movies/new.mkv", connectionId: connectionId)
        candidate.fileURL = URL(string: "https://user:secret@dav.example/Movies/new.mkv")!

        let resolved = FileBrowserLibrary.persistentItem(
            for: makeFile(path: "/Movies/new.mkv"),
            candidate: candidate,
            connectionId: connectionId,
            connectionType: .webdav,
            in: context
        )

        XCTAssertEqual(resolved.id, candidate.id)
        XCTAssertNotNil(resolved.modelContext)
        XCTAssertTrue(PlaybackURLResolver.isPlaceholder(resolved.fileURL))
        XCTAssertFalse(resolved.fileURL.absoluteString.contains("secret"))
        XCTAssertTrue(resolved.isProgressCloudSynced)
        XCTAssertEqual(
            FileBrowserLibrary.existingItem(connectionId: connectionId, path: "/Movies/new.mkv", in: context)?.id,
            candidate.id
        )
    }

    @MainActor
    func testMediaServerInsertKeepsStreamURLAndOptsOutOfCloudSync() throws {
        let context = try makeContext()
        let connectionId = UUID()
        let streamURL = URL(string: "https://emby.example/emby/Videos/ep1/stream?static=true")!
        let candidate = MediaItem(title: "Episode", fileURL: streamURL)

        let resolved = FileBrowserLibrary.persistentItem(
            for: makeFile(path: "ep1"),
            candidate: candidate,
            connectionId: connectionId,
            connectionType: .emby,
            in: context
        )

        XCTAssertEqual(resolved.fileURL, streamURL)
        XCTAssertFalse(resolved.isProgressCloudSynced)
        XCTAssertFalse(resolved.isFavoriteCloudSynced)
    }

    // MARK: - Emby listing artwork

    func testEmbyEpisodeFallsBackToSeriesPosterAndParentBackdrop() throws {
        let json = """
        {"Items":[{"Id":"ep1","Name":"Episode 1","Type":"Episode","IsFolder":false,
          "SeriesId":"series9","SeriesPrimaryImageTag":"s-tag",
          "ParentBackdropItemId":"series9","ParentBackdropImageTags":["b-tag"],
          "RunTimeTicks":36000000000,
          "UserData":{"PlaybackPositionTicks":9000000000,"Played":false}}],
         "TotalRecordCount":1}
        """
        let files = try EmbyService.remoteFiles(
            fromListing: Data(json.utf8),
            baseURL: URL(string: "https://emby.example/")!,
            apiPrefix: "emby/",
            token: "TOKEN"
        )
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(file.type, .video)
        XCTAssertEqual(file.posterURL?.path, "/emby/Items/series9/Images/Primary")
        XCTAssertEqual(file.backdropURL?.path, "/emby/Items/series9/Images/Backdrop/0")
        XCTAssertEqual(file.playbackPosition, 900)
        XCTAssertEqual(file.runtime, 3600)
        XCTAssertEqual(FileCoverResolver.progress(for: file, library: nil), FileWatchProgress(fraction: 0.25, isWatched: false))
    }

    func testEmbyItemPrefersOwnPrimaryAndBackdrop() throws {
        let json = """
        {"Items":[{"Id":"m1","Name":"Movie","Type":"Movie","IsFolder":false,
          "ImageTags":{"Primary":"p"},"BackdropImageTags":["b"],
          "SeriesId":"x","SeriesPrimaryImageTag":"s","UserData":{"Played":true}}],
         "TotalRecordCount":1}
        """
        let file = try XCTUnwrap(EmbyService.remoteFiles(
            fromListing: Data(json.utf8),
            baseURL: URL(string: "http://jelly.example:8096")!,
            apiPrefix: "",
            token: "TOKEN"
        ).first)
        XCTAssertEqual(file.posterURL?.path, "/Items/m1/Images/Primary")
        XCTAssertEqual(file.backdropURL?.path, "/Items/m1/Images/Backdrop/0")
        XCTAssertTrue(file.isPlayed)
    }

    func testEmbyItemWithoutImagesHasNoArtwork() throws {
        let json = #"{"Items":[{"Id":"f1","Name":"Folder","Type":"Folder","IsFolder":true}],"TotalRecordCount":1}"#
        let file = try XCTUnwrap(EmbyService.remoteFiles(
            fromListing: Data(json.utf8),
            baseURL: URL(string: "https://emby.example")!,
            apiPrefix: "emby/",
            token: "TOKEN"
        ).first)
        XCTAssertTrue(file.isDirectory)
        XCTAssertNil(file.posterURL)
        XCTAssertNil(file.backdropURL)
        XCTAssertNil(file.playbackPosition)
    }

    // MARK: - Helpers

    private func makeFile(
        path: String = "/Movies/a.mkv",
        posterURL: URL? = nil,
        backdropURL: URL? = nil,
        playbackPosition: TimeInterval? = nil,
        runtime: TimeInterval? = nil,
        isPlayed: Bool = false
    ) -> RemoteFile {
        RemoteFile(
            name: (path as NSString).lastPathComponent,
            path: path,
            size: 1,
            isDirectory: false,
            modifiedDate: nil,
            type: .video,
            posterURL: posterURL,
            backdropURL: backdropURL,
            playbackPosition: playbackPosition,
            runtime: runtime,
            isPlayed: isPlayed
        )
    }

    private func makeItem(path: String, connectionId: UUID) -> MediaItem {
        let item = MediaItem(title: "Item", fileURL: URL(string: "https://dav.example\(path)")!)
        item.serverId = path
        item.sourceConnectionId = connectionId
        return item
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.makeContainerThrowing(
            cloudKitDatabase: .none,
            isStoredInMemoryOnly: true
        )
        self.container = container
        return ModelContext(container)
    }

    private var container: ModelContainer?
}
