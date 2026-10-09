// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SquiggleDraw", platforms: [.macOS(.v14)], products: [.executable(name: "SquiggleDraw", targets: ["SquiggleDraw"])], targets: [.target(name: "SquiggleCore"), .executableTarget(name: "SquiggleDraw", dependencies: ["SquiggleCore"], resources: [.copy("Resources/Samples")]), .executableTarget(name: "SquiggleSamples", dependencies: ["SquiggleCore"]), .testTarget(name: "SquiggleCoreTests", dependencies: ["SquiggleCore"])])
