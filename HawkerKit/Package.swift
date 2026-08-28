// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HawkerKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15), .visionOS(.v2), .watchOS(.v11)],
    products: [
        .library(name: "HawkerKit", targets: ["HawkerKit"])
    ],
    targets: [
        .target(
            name: "HawkerKit",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HawkerKitTests",
            dependencies: ["HawkerKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
