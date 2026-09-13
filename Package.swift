// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VLCKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_13),
        .tvOS(.v12),
        .watchOS("7.4"),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "VLCKit", targets: ["VLCKit"])
    ],
    targets: [
        .binaryTarget(
            name: "VLCKit",
            url: "https://github.com/enefry/MusicFreeVLCKit/releases/download/4.0.0-audio.20260814.4/MusicFreeVLCKit.xcframework.zip",
            checksum: "db5f44ce6655d6a5ea89f482d938e779e5be5a04a91b58c874c55988b3c6a38f"
        )
    ]
)
