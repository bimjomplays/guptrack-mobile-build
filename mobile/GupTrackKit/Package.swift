// swift-tools-version: 6.0
// GupTrackKit: the iPhone app's plain logic (models, the app API client, the token store, the offline library with
// its outbox, routes, formats, demo data), with no SwiftUI or UIKit, so it builds and tests on Linux in seconds
// (`swift test` here). The app target compiles these same files (mobile/ios/project.yml), so nothing is `public`.
// The same shape as the GupWorks app's GupKit package.
import PackageDescription

let package = Package(
    name: "GupTrackKit",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "GupTrackKit", targets: ["GupTrackKit"])],
    dependencies: [
        // the offline library's SQLite database; builds on Linux too (system libsqlite3)
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.12.0"),
    ],
    targets: [
        .target(name: "GupTrackKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "GupTrackKitTests", dependencies: ["GupTrackKit"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
