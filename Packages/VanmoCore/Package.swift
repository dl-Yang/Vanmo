// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VanmoCore",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "VanmoCore", targets: ["VanmoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/drmohundro/SWXMLHash.git", from: "8.1.1"),
        // PR #234 on top of 66eafaa: requireSigning plus SMB 3.1.1 AES-GCM.
        // Return to kishikawakatsumi/SMBClient when that commit lands on main.
        .package(url: "https://github.com/thatcube/SMBClient.git", revision: "d8baadc1a4f1287ebf1e8b4702ca38bd6e237fef"),
        // Password SFTP client. Citadel 0.12.1 pins Wellz26/swift-nio-ssh 0.3.x.
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.1"),
    ],
    targets: [
        .target(
            name: "VanmoCore",
            dependencies: [
                .product(name: "SWXMLHash", package: "SWXMLHash"),
                .product(name: "SMBClient", package: "SMBClient"),
                .product(name: "Citadel", package: "Citadel"),
            ],
            resources: [
                .process("Localization/Resources"),
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
