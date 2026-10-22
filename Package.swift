// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WorkMemoryCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MemoryCore", targets: ["MemoryCore"])],
    targets: [
        .target(name: "MemoryCore", path: "app/ios/Core"),
        .testTarget(name: "MemoryCoreTests", dependencies: ["MemoryCore"], path: "tests/MemoryCoreTests")
    ]
)
