import XCTest
@testable import VanmoCore

final class EmbyListingTests: XCTestCase {
    func testTitledVideoItemsArePlayableWithoutAnExtension() {
        for itemType in ["Movie", "Episode", "Video", "MusicVideo", "Trailer"] {
            XCTAssertEqual(
                EmbyService.remoteFileType(itemType: itemType, isFolder: false, path: nil, name: "Big Buck Bunny"),
                .video,
                itemType
            )
        }
    }

    func testFoldersStayDirectories() {
        XCTAssertEqual(
            EmbyService.remoteFileType(itemType: "Series", isFolder: true, path: nil, name: "Show"),
            .directory
        )
    }

    func testUnknownItemTypeFallsBackToPathThenName() {
        XCTAssertEqual(
            EmbyService.remoteFileType(itemType: "Unknown", isFolder: false, path: "/media/clip.mkv", name: "Clip"),
            .video
        )
        XCTAssertEqual(
            EmbyService.remoteFileType(itemType: "Unknown", isFolder: false, path: nil, name: "cover.jpg"),
            .image
        )
        XCTAssertEqual(
            EmbyService.remoteFileType(itemType: "Unknown", isFolder: false, path: "", name: "Notes"),
            .other
        )
    }
}
