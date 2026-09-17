import XCTest
@testable import VanmoCore

final class DownloadActivityPresentationTests: XCTestCase {
    private let destination = DownloadDestination(rootPath: "/tmp")

    func testMovieShowsLatestDownloading() {
        let older = snapshot(
            title: "Old Movie",
            mediaType: .movie,
            status: .downloading,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let newer = snapshot(
            title: "New Movie",
            mediaType: .movie,
            status: .downloading,
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        let presentation = DownloadActivityPresentation.select(from: [older, newer])

        XCTAssertEqual(presentation.task?.id, newer.id)
        XCTAssertFalse(presentation.didCompleteCurrent)
        XCTAssertFalse(presentation.shouldEnd)
        XCTAssertEqual(presentation.title, "New Movie")
    }

    func testSingleEpisodeFallsBackToLatestQueued() {
        let queued = snapshot(
            title: "Pilot",
            mediaType: .tvEpisode,
            status: .queued,
            showTitle: "Solo",
            seriesServerID: "solo-1",
            createdAt: Date(timeIntervalSince1970: 30)
        )
        let paused = snapshot(
            title: "Other",
            mediaType: .movie,
            status: .paused,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let presentation = DownloadActivityPresentation.select(from: [queued, paused])

        XCTAssertEqual(presentation.task?.id, queued.id)
        XCTAssertEqual(presentation.title, "Solo · Pilot")
    }

    func testSeriesShowsDownloadingEpisodeThenAdvances() {
        let first = snapshot(
            title: "E1",
            mediaType: .tvEpisode,
            status: .completed,
            showTitle: "Show",
            seriesServerID: "show-1",
            seasonNumber: 1,
            episodeNumber: 1
        )
        let second = snapshot(
            title: "E2",
            mediaType: .tvEpisode,
            status: .downloading,
            showTitle: "Show",
            seriesServerID: "show-1",
            seasonNumber: 1,
            episodeNumber: 2
        )
        let third = snapshot(
            title: "E3",
            mediaType: .tvEpisode,
            status: .queued,
            showTitle: "Show",
            seriesServerID: "show-1",
            seasonNumber: 1,
            episodeNumber: 3
        )

        let current = DownloadActivityPresentation.select(from: [first, second, third])
        XCTAssertEqual(current.task?.id, second.id)
        XCTAssertFalse(current.didCompleteCurrent)

        var finishedSecond = second
        finishedSecond.status = .completed
        finishedSecond.updatedAt = Date()
        let advanced = DownloadActivityPresentation.select(
            from: [first, finishedSecond, third],
            previouslyDisplayedID: second.id
        )
        XCTAssertEqual(advanced.task?.id, third.id)
        XCTAssertTrue(advanced.didCompleteCurrent)
        XCTAssertFalse(advanced.shouldEnd)
    }

    func testSeriesClearsAfterLastEpisodeCompletes() {
        let last = snapshot(
            title: "Finale",
            mediaType: .tvEpisode,
            status: .completed,
            showTitle: "Show",
            seriesServerID: "show-9",
            seasonNumber: 1,
            episodeNumber: 2
        )
        let earlier = snapshot(
            title: "Opener",
            mediaType: .tvEpisode,
            status: .completed,
            showTitle: "Show",
            seriesServerID: "show-9",
            seasonNumber: 1,
            episodeNumber: 1
        )

        let presentation = DownloadActivityPresentation.select(
            from: [earlier, last],
            previouslyDisplayedID: last.id
        )

        XCTAssertNil(presentation.task)
        XCTAssertTrue(presentation.didCompleteCurrent)
        XCTAssertTrue(presentation.shouldEnd)
    }

    func testEmptyTasksEndWithoutCompletionPulse() {
        let presentation = DownloadActivityPresentation.select(from: [])
        XCTAssertNil(presentation.task)
        XCTAssertFalse(presentation.didCompleteCurrent)
        XCTAssertTrue(presentation.shouldEnd)
    }

    private func snapshot(
        title: String,
        mediaType: MediaType,
        status: DownloadTaskStatus,
        showTitle: String? = nil,
        seriesServerID: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1),
        updatedAt: Date = Date(timeIntervalSince1970: 1)
    ) -> DownloadTaskSnapshot {
        let request = DownloadRequest(
            sourceConnectionId: UUID(),
            connectionType: .smb,
            remotePath: "/\(title).mkv",
            fileName: "\(title).mkv",
            displayTitle: title,
            mediaType: mediaType,
            showTitle: showTitle,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber,
            episodeTitle: title
        )
        return DownloadTaskSnapshot(
            request: request,
            destination: destination,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
