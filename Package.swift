// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Postino", platforms: [.macOS(.v13)], products: [.executable(name: "Postino", targets: ["Postino"])], targets: [.target(name: "RelayCore"), .executableTarget(name: "Postino", dependencies: ["RelayCore"]), .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"])])
