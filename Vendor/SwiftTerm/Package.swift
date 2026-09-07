// swift-tools-version:6.0
import PackageDescription

// Library-only snapshot of upstream v1.20.0. Build metadata is pinned in source;
// the upstream Git metadata generator and unrelated executable targets are omitted.
let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SwiftTerm", targets: ["SwiftTerm"])],
    targets: [.target(name: "SwiftTerm", path: "Sources/SwiftTerm",
                      exclude: ["iOS", "Mac/README.md"],
                      resources: [.process("Apple/Metal/Shaders.metal")])],
    swiftLanguageModes: [.v5]
)
