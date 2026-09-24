import Foundation
import PhoneAgentKit

// Roda no Mac com Apple Intelligence: `swift run HelloAgentCLI "sua pergunta"`
let question = CommandLine.arguments.dropFirst().joined(separator: " ")
if question.isEmpty {
    await HelloAgent.run { print($0) }
} else {
    await HelloAgent.run(question: question) { print($0) }
}
