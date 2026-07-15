// swift-tools-version: 5.9
// TempoCore — 순수 Foundation 코어 (MASTER §5.10: SwiftData 의존 금지, Linux swift test 가능)
import PackageDescription

let package = Package(
    name: "TempoCore",
    products: [
        .library(name: "TempoCore", targets: ["TempoCore"]),
    ],
    targets: [
        .target(name: "TempoCore"),
        .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"]),
    ]
)
