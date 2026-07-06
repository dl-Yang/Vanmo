// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VanmoCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VanmoCore", targets: ["VanmoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/drmohundro/SWXMLHash.git", from: "8.1.1"),
        .package(url: "https://github.com/kishikawakatsumi/SMBClient.git", from: "0.3.1"),
    ],
    targets: [
        .target(
            name: "VanmoCore",
            dependencies: [
                .product(name: "SWXMLHash", package: "SWXMLHash"),
                .product(name: "SMBClient", package: "SMBClient"),
            ],
            swiftSettings: [
                .define("CLOUDKIT_SYNC_ENABLED", .when(configuration: .release)),
            ]
        ),
        .testTarget(
            name: "VanmoCoreTests",
            dependencies: ["VanmoCore"]
        ),
    ]
)
