// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoiceAssistantApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VoiceAssistantApp",
            targets: ["VoiceAssistantApp"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/armadsen/ORSSerialPort.git",
            from: "2.1.0"
        ),
        .package(
            url: "https://github.com/exPHAT/SwiftWhisper.git",
            branch: "master"
        )
    ],
    targets: [
        .executableTarget(
            name: "VoiceAssistantApp",
            dependencies: [
                .product(name: "ORSSerial", package: "ORSSerialPort"),
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            resources: [
                .copy("Resources/ggml-base.bin")
            ]
        ),
    ]
)