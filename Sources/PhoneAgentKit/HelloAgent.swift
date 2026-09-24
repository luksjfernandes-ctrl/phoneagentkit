import Foundation
import FoundationModels
import MCP

/// Exemplo mínimo, sem conector pessoal: conecta no servidor MCP público do DeepWiki (sem login),
/// enxuga as ferramentas para o orçamento e responde uma pergunta sobre um repositório público.
public enum HelloAgent {
    public static let publicServer = URL(string: "https://mcp.deepwiki.com/mcp")!

    public enum Failure: Error, CustomStringConvertible {
        case modelUnavailable(String)
        public var description: String {
            switch self { case .modelUnavailable(let why): "Apple Intelligence is not available on this device (\(why))." }
        }
    }

    /// Motor único: usado pelo app, pela linha de comando e pelo App Intent (Siri/Atalhos).
    /// `source` é a fonte marcada pelo usuário: aqui, um repositório público no formato dono/repo.
    public static func ask(_ question: String, source: String? = nil,
                           log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let info = ModelInfo.current()
        log("model: \(info)")
        guard info.isAvailable else { throw Failure.modelUnavailable(info.availability) }
        let client = try await MCPConnection.connect(to: publicServer)
        defer { Task { await client.disconnect() } }
        let tools = try await client.listTools().tools
        // metade da janela para as ferramentas; o resto fica para a conversa e a resposta
        let (kept, used) = try await ToolBudget.fit(tools, client: client, trimming: .init(requiredOnly: true),
                                                     preferred: ["ask_question"], budget: info.contextSize / 2)
        log("tools: \(kept.count)/\(tools.count) kept, \(used) tokens")
        let session = LanguageModelSession(tools: kept, instructions: """
            You answer questions about public GitHub repositories using the tools. \
            Use repoName in the form owner/repo. Answer briefly.
            """)
        let prompt = source.map { "Repository: \($0)\n\(question)" } ?? question
        return try await session.respond(to: prompt).content
    }

    /// Caminho fonte-marcada (usado pela Siri/Atalhos): o CÓDIGO chama a ferramenta do repositório
    /// marcado; o modelo local só redige a resposta a partir do que voltou. Sem listTools nem escolha livre.
    public static func askPinned(_ question: String, repository: String,
                                 log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let info = ModelInfo.current()
        log("model: \(info)")
        guard info.isAvailable else { throw Failure.modelUnavailable(info.availability) }
        let client = try await MCPConnection.connect(to: publicServer)
        defer { Task { await client.disconnect() } }
        let (content, _) = try await client.callTool(name: "ask_question", arguments: [
            "repoName": .string(repository), "question": .string(question),
        ])
        let facts = MCPConnection.text(content)
        log("facts: \(facts.count) chars")
        return try await PinnedSource.answer(question, source: repository, facts: facts, factLimit: 2400)
    }

    public static func run(question: String = "In the repository modelcontextprotocol/swift-sdk, which client transports are supported?",
                           source: String? = nil, log: @escaping @Sendable (String) -> Void) async {
        do {
            let t0 = Date()
            let answer = try await ask(question, source: source, log: log)
            log(String(format: "answer (%.1fs): %@", Date().timeIntervalSince(t0), answer))
        } catch {
            log("error: \(error)")
        }
    }
}
