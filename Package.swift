// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignalRClient",
    products: [
        .library(name: "SignalRClient", targets: ["SignalRClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/websocket-kit.git", from: "2.15.0"),
        // .package(url: "https://github.com/Zewo/zlib.git", )
        // Add other dependencies here
    ],
    targets: [
        .target(
            name: "SignalRClient",
            dependencies: [
                .product(name: "WebSocketKit", package: "websocket-kit")
            ]
        ),
        // .testTarget(name: "SignalRClientTests", dependencies: ["SignalRClient"]),
    ]
)
