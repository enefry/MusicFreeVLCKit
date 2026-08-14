// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VLCKit",
    platforms: [
        .iOS(.v12),
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
            url: "https://github.com/enefry/MusicFreeVLCKit/releases/download/4.0.0-audio.20260814.3/MusicFreeVLCKit.xcframework.zip",
            checksum: "ca6152d7c4e413c6463b29d0961911ac038b8b3c0eb97eb1b9f358228e81833f"
        )
    ]
)
