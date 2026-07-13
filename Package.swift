// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DragTimer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DragTimer", targets: ["DragTimer"])
    ],
    targets: [
        .executableTarget(
            name: "DragTimer",
            path: "Sources/DragTimer"
        ),
        .testTarget(
            name: "DragTimerTests",
            dependencies: ["DragTimer"],
            path: "Tests/DragTimerTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
