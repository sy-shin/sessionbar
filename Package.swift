// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sessionbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sessionbar", targets: ["sessionbar"]),
        .library(name: "SessionbarCore", targets: ["SessionbarCore"])
    ],
    targets: [
        .target(name: "SessionbarCore"),
        .executableTarget(name: "sessionbar", dependencies: ["SessionbarCore"]),
        .testTarget(name: "SessionbarTests", dependencies: ["SessionbarCore", "sessionbar"])
    ],
    swiftLanguageVersions: [.v5]
)
