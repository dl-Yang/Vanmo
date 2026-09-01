import XCTest
@testable import VanmoCore

final class MediaCapabilityTagsTests: XCTestCase {
    func testResolutionClassification() {
        XCTAssertEqual(VideoResolutionLabel.classify(width: 3840, height: 2160), .k4)
        XCTAssertEqual(VideoResolutionLabel.classify(width: 4096, height: 2160), .k4)
        XCTAssertEqual(VideoResolutionLabel.classify(width: 2560, height: 1440), .k2)
        XCTAssertEqual(VideoResolutionLabel.classify(width: 1920, height: 1080), .p1080)
        XCTAssertEqual(VideoResolutionLabel.classify(width: 1280, height: 720), .low)
        XCTAssertEqual(VideoResolutionLabel.classify(width: 720, height: 480), .low)
        XCTAssertNil(VideoResolutionLabel.classify(width: nil, height: nil))
        XCTAssertNil(VideoResolutionLabel.classify(width: 0, height: 0))
    }

    func testPlexResolutionTokenFallback() {
        XCTAssertEqual(VideoResolutionLabel.dimensions(fromResolutionToken: "4k")?.width, 3840)
        XCTAssertEqual(VideoResolutionLabel.dimensions(fromResolutionToken: "1080")?.height, 1080)
        XCTAssertNil(VideoResolutionLabel.dimensions(fromResolutionToken: nil))
    }

    func testContentRatingHiddenWhenMissing() {
        XCTAssertNil(MediaCapabilityTags.normalizedContentRating(nil))
        XCTAssertNil(MediaCapabilityTags.normalizedContentRating("   "))
        XCTAssertEqual(MediaCapabilityTags.normalizedContentRating("TV-MA"), "TV-MA")
    }

    func testDisplayTagsOmitMissingValues() {
        XCTAssertEqual(
            MediaCapabilityTags.displayTags(
                contentRating: nil,
                width: nil,
                height: nil,
                dynamicRange: nil,
                audioTracks: [],
                fileName: "Movie.mkv"
            ),
            []
        )
        XCTAssertEqual(
            MediaCapabilityTags.displayTags(
                contentRating: "TV-MA",
                width: 3840,
                height: 2160,
                dynamicRange: DynamicRange.dolbyVision.rawValue,
                audioTracks: [],
                fileName: nil
            ),
            ["TV-MA", "4K", "DOLBY"]
        )
        XCTAssertEqual(
            MediaCapabilityTags.displayTags(
                contentRating: nil,
                width: nil,
                height: nil,
                dynamicRange: nil,
                audioTracks: [],
                fileName: "Movie.2020.1080p.BluRay.mkv"
            ),
            ["1080P"]
        )
    }

    func testResolutionFromFileName() {
        XCTAssertEqual(VideoResolutionLabel.classify(fileName: "Show.S01E01.2160p.mkv"), .k4)
        XCTAssertEqual(VideoResolutionLabel.classify(fileName: "Title.4K.UHD.mkv"), .k4)
        XCTAssertEqual(VideoResolutionLabel.classify(fileName: "Title.1080p.mkv"), .p1080)
        XCTAssertEqual(VideoResolutionLabel.classify(fileName: "Title.720p.mkv"), .low)
        XCTAssertNil(VideoResolutionLabel.classify(fileName: "Movie.mkv"))
    }

    func testDolbyDetectionFromAudioAndFileName() {
        XCTAssertTrue(
            MediaCapabilityTags.detectsDolby(
                dynamicRange: nil,
                audioTracks: [AudioTrackInfo(id: 0, codec: "truehd")],
                fileName: nil
            )
        )
        XCTAssertTrue(
            MediaCapabilityTags.detectsDolby(
                dynamicRange: nil,
                audioTracks: [],
                fileName: "Show.S01E01.Atmos.mkv"
            )
        )
        XCTAssertFalse(
            MediaCapabilityTags.detectsDolby(
                dynamicRange: DynamicRange.sdr.rawValue,
                audioTracks: [AudioTrackInfo(id: 0, codec: "aac")],
                fileName: "Show.S01E01.1080p.mkv"
            )
        )
    }

    func testOnlyExplicitDolbyVisionPersistsAsDynamicRange() {
        XCTAssertTrue(MediaCapabilityTags.isDolbyVisionRange("DOVI"))
        XCTAssertTrue(MediaCapabilityTags.isDolbyVisionRange(DynamicRange.dolbyVision.rawValue))
        XCTAssertFalse(MediaCapabilityTags.isDolbyVisionRange("Atmos"))
        XCTAssertFalse(MediaCapabilityTags.isDolbyVisionRange("truehd"))
        XCTAssertFalse(MediaCapabilityTags.isDolbyVisionRange("HDR10"))
    }

    func testShouldProbeWhenSuccessfulProbeMissingDimensions() {
        let item = MediaItem(title: "Sample", fileURL: URL(fileURLWithPath: "/tmp/sample.mkv"))
        item.duration = 120
        item.probeStatus = ProbeStatus.success.rawValue
        item.probeFingerprint = ProbeFingerprint.from(item: item).storageValue
        XCTAssertTrue(MediaProbeApplicator.shouldProbe(item: item))

        item.videoWidth = 1920
        item.videoHeight = 1080
        XCTAssertFalse(MediaProbeApplicator.shouldProbe(item: item))
    }

    func testShouldNotProbeSeriesContainers() {
        let show = MediaItem(title: "Show", fileURL: URL(fileURLWithPath: "/tmp/show"))
        show.mediaType = .tvShow
        XCTAssertFalse(MediaProbeApplicator.shouldProbe(item: show))

        let boxSet = MediaItem(title: "Box", fileURL: URL(fileURLWithPath: "/tmp/box"))
        boxSet.mediaType = .boxSet
        XCTAssertFalse(MediaProbeApplicator.shouldProbe(item: boxSet))
    }

    func testDisplayTagsFromEpisodeFileName() {
        XCTAssertEqual(
            MediaCapabilityTags.displayTags(
                contentRating: "TV-MA",
                width: nil,
                height: nil,
                dynamicRange: nil,
                audioTracks: [],
                fileName: "Show.S01E01.1080p.mkv"
            ),
            ["TV-MA", "1080P"]
        )
    }
}
