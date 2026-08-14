// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MusicFreeVLCKitConsumer",
    platforms: [.iOS(.v12)],
    products: [
        .executable(name: "MusicFreeVLCKitConsumer", targets: ["MusicFreeVLCKitConsumer"])
    ],
    targets: [
        .executableTarget(
            name: "MusicFreeVLCKitConsumer",
            dependencies: ["VLCKit"],
            path: "Sources/Consumer"
        ),
        .binaryTarget(
            name: "VLCKit",
            path: "Artifacts/VLCKit.xcframework"
        )
    ]
)
