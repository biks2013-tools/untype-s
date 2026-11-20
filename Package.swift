// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "untype-s",
    platforms: [
        .macOS(.v14),
        // The iPhone and iPad app (ios/, plan-075) uses UntypeCore.
        .iOS(.v17)
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
            name: "UntypeCore",
            dependencies: [.target(name: "UntypeAEC", condition: .when(platforms: [.macOS]))],
            linkerSettings: [.linkedLibrary("c++")]
        ),
        // WebRTC's echo canceller behind a C interface; rebuilt with
        // scripts/build-webrtc-apm.sh (sources of the interface in Vendor/UntypeAEC/shim).
        .binaryTarget(
            name: "UntypeAEC",
            path: "Vendor/UntypeAEC/UntypeAEC.xcframework"
        ),
        .testTarget(
            name: "UntypeCoreTests",
            dependencies: ["UntypeCore"]
        )
    ]
)
