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
        // ask_question responde com IA do servidor; fica de fora para que só o modelo local responda
        let tools = try await client.listTools().tools.filter { $0.name != "ask_question" }
        // metade da janela para as ferramentas; o resto fica para a conversa e a resposta
        let (kept, used) = try await ToolBudget.fit(tools, client: client, trimming: .init(requiredOnly: true),
                                                     preferred: ["read_wiki_structure", "read_wiki_contents"], budget: info.contextSize / 2)
        log("tools: \(kept.count)/\(tools.count) kept, \(used) tokens")
        let session = LanguageModelSession(tools: kept, instructions: """
            You answer questions about public GitHub repositories using the tools. \
            Use repoName in the form owner/repo. Answer briefly.
            """)
        let prompt = source.map { "Repository: \($0)\n\(question)" } ?? question
        return try await session.respond(to: prompt).content
    }

    /// Caminho fonte-marcada (usado pela Siri/Atalhos). Tudo o que responde é o modelo LOCAL:
    /// o servidor só devolve o texto da wiki do repositório (`read_wiki_contents`, sem IA do lado de lá).
    /// O código corta em páginas e seções; o modelo escolhe nos menus numerados e responde só com a seção.
    public static func askPinned(_ question: String, repository: String, sectionLimit: Int = 1500,
                                 log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        let info = ModelInfo.current()
        log("model: \(info)")
        guard info.isAvailable else { throw Failure.modelUnavailable(info.availability) }
        let client = try await MCPConnection.connect(to: publicServer)
        defer { Task { await client.disconnect() } }
        let (content, _) = try await client.callTool(name: "read_wiki_contents", arguments: ["repoName": .string(repository)])
        let all = MarkdownSections.split(MCPConnection.text(content), prefix: "# Page: ")
        let pages = MarkdownSections.rank(all, for: question)
        log("wiki: \(all.count) pages, menu: \(pages.map(\.title).joined(separator: " | "))")
        let choose = "Pick the option most likely to answer the request. Answer 0 if none fits."
        // o código decide quando só um título bate com a pergunta; o modelo só escolhe nos empates
        let byCode = MarkdownSections.uniqueTitleMatch(pages, for: question)
        guard let p = try await pick(byCode, NumberedMenu(pages.map(\.title)), question, choose)
        else { return "The wiki of \(repository) has no page about that." }
        // a introdução da página (antes do primeiro ##) entra como 1ª opção: é ela que responde perguntas gerais
        let body = pages[p].body
        let intro = body.components(separatedBy: "\n## ").first ?? body
        let sections = [MarkdownSection(title: "Overview of \(pages[p].title)", body: intro)]
            + MarkdownSections.rank(MarkdownSections.split(body, prefix: "## "), for: question, limit: 5)
        log("page: \(pages[p].title) (\(byCode == nil ? "model" : "code"))")
        var facts = pages[p].body
        var source = "\(repository) › \(pages[p].title)"
        let sectionByCode = MarkdownSections.uniqueTitleMatch(sections, for: question)
        if let s = try await pick(sectionByCode, NumberedMenu(sections.map(\.title)), question, choose) {
            facts = sections[s].body
            source += " › \(sections[s].title)"
        }
        log("section: \(source) (\(sectionByCode == nil ? "model" : "code")), \(min(facts.count, sectionLimit)) chars")
        return try await PinnedSource.answer(question, source: source, facts: String(facts.prefix(sectionLimit)))
    }

    static func pick(_ byCode: Int?, _ menu: NumberedMenu, _ question: String, _ instructions: String) async throws -> Int? {
        if let byCode { return byCode }
        return try await menu.choose(for: question, instructions: instructions)
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
