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
        .target(
            name: "CopilotCore",
            dependencies: [.product(name: "Yams", package: "Yams")]
        ),
        .executableTarget(
            name: "InterviewCopilot",
            dependencies: ["CopilotCore"]
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
