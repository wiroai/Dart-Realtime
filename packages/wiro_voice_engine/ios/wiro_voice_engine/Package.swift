// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "wiro_voice_engine",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "wiro-voice-engine", targets: ["wiro_voice_engine"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "wiro_voice_engine",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
