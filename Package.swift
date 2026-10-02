// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NimbusCashier",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8), .visionOS(.v1)],
    products: [
        .library(name: "NimbusCashier", targets: ["NimbusCashier"]),
    ],
    targets: [
        .target(name: "NimbusCashier", resources: [.copy("Resources/paywall-art.json")]),
        .testTarget(name: "NimbusCashierTests", dependencies: ["NimbusCashier"], resources: [.copy("Fixtures")]),
    ]
)
