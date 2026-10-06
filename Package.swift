// swift-tools-version:6.0
import PackageDescription

// Стек и разрешённые зависимости — docs/decisions/ADR-0001-stack.md (п. 2, 9).
let package = Package(
    name: "InterviewCopilot",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "InterviewCopilot", targets: ["InterviewCopilot"]),
        .executable(name: "copilot-eval", targets: ["copilot-eval"]),
        .library(name: "CopilotCore", targets: ["CopilotCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    ],
    targets: [
        // whisper.cpp — готовый XCFramework из релизов (ADR-0001 п. 5); SHA256 = сумма архива из GitHub Releases.
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
        .target(
            name: "CopilotCore",
            dependencies: [.product(name: "Yams", package: "Yams"), "whisper"]
        ),
        .executableTarget(
            name: "InterviewCopilot",
            dependencies: ["CopilotCore"],
            // В .app фреймворки лежат в Contents/Frameworks (scripts/build-app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "copilot-eval",
            dependencies: ["CopilotCore"]
        ),
        .testTarget(
            name: "CopilotCoreTests",
            dependencies: ["CopilotCore"]
        ),
    ]
)
