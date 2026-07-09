// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "TimezoneBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TimezoneBar", targets: ["TimezoneBar"])
    ],
    targets: [
        .executableTarget(
            name: "TimezoneBar",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
