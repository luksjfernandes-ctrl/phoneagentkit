import AppIntents
import OSLog
import PhoneAgentKit

/// "Perguntar ao agente": expõe o mesmo motor do app para a Siri e para os Atalhos.
/// A fonte (repositório público dono/repo) é marcada pelo usuário, como no padrão fonte-marcada.
struct AskAgentIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask the agent"
    static let description = IntentDescription("Answers from the wiki of a public GitHub repository. A public MCP server returns the text; the on-device model picks the section and writes the answer.")

    @Parameter(title: "Question", default: "What is the stdio transport?", requestValueDialog: "What do you want to know?")
    var question: String

    @Parameter(title: "Repository", description: "owner/repo", default: "modelcontextprotocol/modelcontextprotocol")
    var repository: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question) about \(\.$repository)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let log = Logger(subsystem: "com.example.helloagent", category: "intent")
        log.notice("perform: \(question, privacy: .public) @ \(repository, privacy: .public)")
        let answer: String
        do {
            answer = try await HelloAgent.askPinned(question, repository: repository) { log.notice("\($0, privacy: .public)") }
        } catch {
            log.error("falhou: \(String(describing: error), privacy: .public)")
            throw error
        }
        log.notice("resposta pronta")
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

/// Deixa o intent disponível na Siri e nos Atalhos sem o usuário criar nada.
struct HelloAgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskAgentIntent(), phrases: [
            "Ask \(.applicationName)",
            "Ask \(.applicationName) a question",
        ], shortTitle: "Ask the agent", systemImageName: "sparkles")
    }
}
