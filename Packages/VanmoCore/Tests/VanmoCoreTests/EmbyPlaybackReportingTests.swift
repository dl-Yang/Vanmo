import XCTest
@testable import VanmoCore

final class EmbyPlaybackReportingTests: XCTestCase {
    override func tearDown() {
        RecordingURLProtocol.reset()
        super.tearDown()
    }

    func testTranscodePlaySessionIDComesFromPlaylistOnly() throws {
        let playlist = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?MediaSourceId=253013&playSessionId=abc123&api_key=SECRET"))
        XCTAssertEqual(EmbyTranscodeClient.playSessionID(in: playlist), "abc123")
        let direct = try XCTUnwrap(URL(string: "https://emby.example/emby/Videos/253013/stream?static=true&PlaySessionId=abc123"))
        XCTAssertNil(EmbyTranscodeClient.playSessionID(in: direct))
        let bare = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?MediaSourceId=253013"))
        XCTAssertNil(EmbyTranscodeClient.playSessionID(in: bare))
    }

    @MainActor
    func testSessionSwitchesPlaySessionIDWithPlaybackURL() throws {
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        let session = EmbyPlaybackSession(item: item, connection: nil)
        let reporterID = session.playSessionId
        XCTAssertFalse(session.isTranscoding)

        let direct = try XCTUnwrap(URL(string: "https://emby.example/emby/Videos/253013/stream?static=true"))
        XCTAssertEqual(session.adoptPlaySession(from: direct), [])
        XCTAssertEqual(session.playSessionId, reporterID)

        let p720 = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?PlaySessionId=first"))
        XCTAssertEqual(session.adoptPlaySession(from: p720), [])
        XCTAssertEqual(session.playSessionId, "first")
        XCTAssertTrue(session.isTranscoding)

        let p480 = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?PlaySessionId=second"))
        XCTAssertEqual(session.adoptPlaySession(from: p480), ["first"])
        XCTAssertEqual(session.playSessionId, "second")
        XCTAssertEqual(session.adoptPlaySession(from: p480), [])

        XCTAssertEqual(session.adoptPlaySession(from: direct), ["second"])
        XCTAssertEqual(session.playSessionId, reporterID)
        XCTAssertFalse(session.isTranscoding)
    }

    @MainActor
    func testUnsettledTranscodeEndsOnlyWhenAnotherURLIsAdopted() throws {
        let item = MediaItem(title: "Movie", fileURL: URL(fileURLWithPath: "/tmp/movie.mkv"))
        let session = EmbyPlaybackSession(item: item, connection: nil)
        let p720 = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?PlaySessionId=current"))
        let superseded = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?PlaySessionId=superseded"))
        let failed = try XCTUnwrap(URL(string: "https://emby.example/emby/videos/253013/master.m3u8?PlaySessionId=failed"))
        _ = session.adoptPlaySession(from: p720)

        session.noteUnsettledTranscode(superseded)
        session.noteUnsettledTranscode(failed)
        session.noteUnsettledTranscode(p720)
        XCTAssertEqual(session.unsettledTranscodeIds, ["superseded", "failed"])

        // 恢复到当前地址：其余未定转码都要结束，当前的保留。
        XCTAssertEqual(session.adoptPlaySession(from: p720), ["failed", "superseded"])
        XCTAssertEqual(session.playSessionId, "current")
        XCTAssertTrue(session.unsettledTranscodeIds.isEmpty)

        // 未定的转码最终被采用时不能结束它。
        session.noteUnsettledTranscode(superseded)
        XCTAssertEqual(session.adoptPlaySession(from: superseded), ["current"])
        XCTAssertEqual(session.playSessionId, "superseded")
    }

    func testStopActiveEncodingsTargetsDeviceAndPlaySession() async throws {
        for (type, prefix) in [(ConnectionType.emby, "emby/"), (ConnectionType.jellyfin, "")] {
            RecordingURLProtocol.reset()
            let service = makeService(type: type, apiPrefix: prefix)
            try await service.stopActiveEncodings(playSessionId: "abc123")

            let request = try XCTUnwrap(RecordingURLProtocol.requests.last)
            XCTAssertEqual(request.httpMethod, "DELETE")
            let url = try XCTUnwrap(request.url)
            XCTAssertEqual(url.path, "/\(prefix)Videos/ActiveEncodings")
            let items = queryItems(url)
            XCTAssertEqual(items["PlaySessionId"], "abc123")
            XCTAssertEqual(items["DeviceId"], PlatformDeviceInfo.deviceIdentifier)
            XCTAssertEqual(items["api_key"], "TOKEN")
        }
    }

    func testCheckInReportsTranscodePlayMethod() async throws {
        let service = makeService(type: .emby, apiPrefix: "emby/")
        try await service.reportPlaybackStopped(
            itemId: "253013",
            positionTicks: 10,
            playSessionId: "abc123",
            isTranscoding: true
        )
        try await service.reportPlaybackProgress(
            itemId: "253013",
            positionTicks: 10,
            isPaused: false,
            eventName: "TimeUpdate",
            playSessionId: "reporter"
        )

        let bodies = RecordingURLProtocol.bodies
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies.first?["PlaySessionId"] as? String, "abc123")
        XCTAssertEqual(bodies.first?["PlayMethod"] as? String, "Transcode")
        XCTAssertEqual(bodies.last?["PlayMethod"] as? String, "DirectPlay")
        XCTAssertEqual(RecordingURLProtocol.requests.first?.url?.path, "/emby/Sessions/Playing/Stopped")
    }

    private func makeService(type: ConnectionType, apiPrefix: String) -> EmbyService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingURLProtocol.self]
        let service = EmbyService(type: type, apiPrefix: apiPrefix, session: URLSession(configuration: configuration))
        service.restoreSession(
            config: ConnectionConfig(type: type, host: "media.example", port: 8096),
            token: "TOKEN",
            userId: "user"
        )
        return service
    }

    private func queryItems(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [(request: URLRequest, body: Data?)] = []

    static var requests: [URLRequest] {
        lock.withLock { recorded.map(\.request) }
    }

    static var bodies: [[String: Any]] {
        lock.withLock {
            recorded.compactMap { entry in
                entry.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            }
        }
    }

    static func reset() {
        lock.withLock { recorded.removeAll() }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.readAll)
        Self.lock.withLock { Self.recorded.append((request, body)) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
