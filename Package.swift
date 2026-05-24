// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "untype-s",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "untype", targets: ["untype"]),
        .executable(name: "untype-input-helper", targets: ["untype-input-helper"]),
        .library(name: "UntypeCore", targets: ["UntypeCore"])
    ],
    targets: [
        .executableTarget(
            name: "untype",
            dependencies: ["UntypeCore"]
        ),
        .executableTarget(
            name: "untype-input-helper",
            dependencies: ["UntypeCore"]
        ),
        .target(
            name: "UntypeCore"
        ),
        .testTarget(
            name: "UntypeCoreTests",
            dependencies: ["UntypeCore"]
        )
    ]
)
