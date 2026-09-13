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
            url: "https://github.com/enefry/MusicFreeVLCKit/releases/download/4.0.0-audio.20260907.2/MusicFreeVLCKit.xcframework.zip",
            checksum: "7cfe14d9fd175e03fe15091b82fdcc4f5f54705b38641c7fc148fb7f169a5451"
        )
    ]
)
