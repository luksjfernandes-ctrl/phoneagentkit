import Foundation
import PhoneAgentKit

// Roda no Mac com Apple Intelligence:
//   swift run HelloAgentCLI "pergunta"                     → caminho livre (ferramentas enxugadas)
//   swift run HelloAgentCLI --pinned dono/repo "pergunta"  → fonte marcada (o mesmo do App Intent)
var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--pinned", args.count >= 3 {
    let repo = args[1], question = args.dropFirst(2).joined(separator: " ")
    let t0 = Date()
    do {
        let answer = try await HelloAgent.askPinned(question, repository: repo) { print($0) }
        print(String(format: "answer (%.1fs): %@", Date().timeIntervalSince(t0), answer))
    } catch { print("error: \(error)") }
} else if args.isEmpty {
    await HelloAgent.run { print($0) }
} else {
    await HelloAgent.run(question: args.joined(separator: " ")) { print($0) }
}
