// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiCONE",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MiCONECore", swiftSettings: [.swiftLanguageMode(.v5)], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "MiCONE", dependencies: ["MiCONECore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "MiCONECoreTests", dependencies: ["MiCONECore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
