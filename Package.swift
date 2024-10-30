// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignalRClient",
    products: [
        .library(name: "SignalRClient", targets: ["SignalRClient"]),
    ],
    dependencies: [
        // .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        // .package(url: "https://github.com/daltoniam/Starscream.git", exact: "4.0.6"),
        // .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.0.0"),
        // Add other dependencies here
    ],
    targets: [
        // .target(
        //     name: "CNIOExtrasZlib",
        //     dependencies: [],
        //     linkerSettings: [
        //         .linkedLibrary("z")
        //     ]
        // ),
        .target(
            name: "SignalRClient",
            dependencies: [ ],
            linkerSettings: [
                .linkedLibrary("z")
            ]),
        .testTarget(name: "SignalRClientTests", dependencies: ["SignalRClient"]),
    ]
)
