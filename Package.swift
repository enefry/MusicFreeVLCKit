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
            url: "https://github.com/enefry/MusicFreeVLCKit/releases/download/4.0.0-audio.20260814.2/MusicFreeVLCKit.xcframework.zip",
            checksum: "d8fe1db6555e7c57efd5e96795ef256213323ae3b107839f02823bc5fb99f9d9"
        )
    ]
)
