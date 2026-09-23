// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AppleHomeReadingTests", platforms: [.macOS(.v14)], targets: [
    .target(name: "ReadingCore", path: "Sources", exclude: ["AppleHomeApp.swift", "AppleHomeView.swift", "AppleHomeModel.swift"], sources: ["ReadingTracker.swift", "HomeCommand.swift"]),
    .testTarget(name: "ReadingCoreTests", dependencies: ["ReadingCore"])
])
