// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EchoSub",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EchoSub", targets: ["EchoSub"]),
    ],
    targets: [
        .executableTarget(
            name: "EchoSub",
            path: "Sources/EchoSub",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "EchoSubTests",
            dependencies: ["EchoSub"],
            path: "Tests/EchoSubTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
