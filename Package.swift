// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cuebar",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "Cuebar", targets: ["Cuebar"])
    ],
    targets: [
        .target(
            name: "CuebarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Cuebar",
            dependencies: ["CuebarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CuebarCoreTests",
            dependencies: ["CuebarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
