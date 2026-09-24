import Foundation
import FoundationModels

/// Exemplo mínimo, sem conector pessoal: conecta no servidor MCP público do DeepWiki (sem login),
/// enxuga as ferramentas para o orçamento e responde uma pergunta sobre um repositório público.
public enum HelloAgent {
    public static let publicServer = URL(string: "https://mcp.deepwiki.com/mcp")!

    public static func run(question: String = "In the repository modelcontextprotocol/swift-sdk, which client transports are supported?",
                           log: @escaping @Sendable (String) -> Void) async {
        let info = ModelInfo.current()
        log("model: \(info)")
        guard info.isAvailable else { log("Apple Intelligence is not available on this device."); return }
        do {
            let client = try await MCPConnection.connect(to: publicServer)
            let tools = try await client.listTools().tools
            // metade da janela para as ferramentas; o resto fica para a conversa e a resposta
            let (kept, used) = try await ToolBudget.fit(tools, client: client, trimming: .init(requiredOnly: true),
                                                         preferred: ["ask_question"], budget: info.contextSize / 2)
            log("tools: \(kept.count)/\(tools.count) kept, \(used) tokens")
            let session = LanguageModelSession(tools: kept, instructions: """
                You answer questions about public GitHub repositories using the tools. \
                Use repoName in the form owner/repo. Answer briefly.
                """)
            let t0 = Date()
            let answer = try await session.respond(to: question).content
            log(String(format: "answer (%.1fs): %@", Date().timeIntervalSince(t0), answer))
            await client.disconnect()
        } catch {
            log("error: \(error)")
        }
    }
}
