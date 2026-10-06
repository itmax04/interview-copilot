import CopilotCore
import Foundation

// CLI для evals (evals/README.md). Наборы `bank` и `turn` подключаются на P-05 и P-06.
let args = CommandLine.arguments.dropFirst()
switch args.first {
case "bank", "turn":
    FileHandle.standardError.write(Data("copilot-eval \(args.first!): набор ещё не реализован (P-05/P-06)\n".utf8))
    exit(2)
default:
    print("usage: copilot-eval <bank|turn> [options]")
    exit(args.isEmpty ? 0 : 64)
}
