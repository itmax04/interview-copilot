// swift-tools-version:6.2
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
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        // whisper.cpp — готовый XCFramework из релизов (ADR-0001 п. 5); SHA256 = сумма архива из GitHub Releases.
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/b5454/whisper-b5454-xcframework.zip",
            checksum: "e57f8c48933000acabc13bb913fbe82805d483a2deff692cc6738836bd92393b"
        ),
        // llama.cpp — эмбеддинги для поиска по базе (ADR-0001 п. 6, 9).
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11446/llama-b11446-xcframework.zip",
            checksum: "da7edb84bd4990680cd6bb475468cc3f78b28cc0062fabebeae40218d228966b"
        ),
        .target(
            name: "CopilotEmbeddings",
            dependencies: ["CopilotCore", "llama"]
        ),
        .target(
            name: "CopilotCore",
            dependencies: [.product(name: "Yams", package: "Yams"),
                           .product(name: "FluidAudio", package: "FluidAudio"), "whisper"]
        ),
        .executableTarget(
            name: "InterviewCopilot",
            dependencies: ["CopilotCore", "CopilotEmbeddings"],
            // В .app фреймворки лежат в Contents/Frameworks (scripts/build-app.sh).
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .executableTarget(
            name: "copilot-eval",
            dependencies: ["CopilotCore", "CopilotEmbeddings"]
        ),
        .testTarget(
            name: "CopilotCoreTests",
            dependencies: ["CopilotCore", "CopilotEmbeddings"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
