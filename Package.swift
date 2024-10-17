// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignalRClient",
    products: [
        .library(name: "SignalRClient", targets: ["SignalRClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        // Add other dependencies here
    ],
    targets: [
        .target(name: "SignalRClient", dependencies: ["NIO", "NIOWebSocket"]),
        .testTarget(name: "SignalRClientTests", dependencies: ["SignalRClient"]),
    ]
)
