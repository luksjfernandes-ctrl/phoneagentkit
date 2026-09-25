import Foundation
import FoundationModels
import MCP
import PhoneAgentKit

/// B1b · Composio (connect.composio.dev/mcp, login do próprio usuário).
/// Padrão do kit: o modelo NUNCA vê as meta-ferramentas. O código busca, lista conexões e executa;
/// o modelo só preenche os argumentos de UMA ferramenta enxuta do app escolhido pelo usuário.
/// Bloqueadas pelo código: execução remota de código (REMOTE_WORKBENCH, REMOTE_BASH_TOOL) e as de skill/feedback.
enum Composio {
    static let bloqueadas: Set<String> = ["COMPOSIO_REMOTE_WORKBENCH", "COMPOSIO_REMOTE_BASH_TOOL", "COMPOSIO_SUBMIT_FEEDBACK",
                                          "COMPOSIO_MANAGE_SKILL", "COMPOSIO_SEARCH_SKILLS", "COMPOSIO_USE_SKILL", "COMPOSIO_WAIT_FOR_CONNECTIONS"]
    static let apps = ["gmail", "googlecalendar", "googledrive", "googlesheets", "notion", "slack", "github", "linear", "asana", "outlook"]

    static func texto(_ cli: Client, _ nome: String, _ args: [String: Value]) async throws -> String {
        guard !bloqueadas.contains(nome) else { throw NSError(domain: "Composio", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(nome) bloqueada pelo código"]) }
        let (c, _) = try await cli.callTool(name: nome, arguments: args)
        return MCPConnection.text(c)
    }

    struct Sonda: Codable {
        var aparelho = "", tokensCruas = -1, tokensSemBloqueadas = -1, janela = 0
        var porFerramenta: [String: Int] = [:]
        var conexoes = "", busca = "", tokensBusca = -1, esquema = "", tokensEsquemaEnxuto = -1, erros: [String] = []
    }

    /// Só leitura: nenhuma chamada cria, altera ou apaga nada.
    static func sonda(log: @escaping @Sendable (String) -> Void) async {
        var s = Sonda(aparelho: ModelInfo.current().description, janela: ModelInfo.current().contextSize)
        let modelo = SystemLanguageModel.default
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            let tools = try await cli.listTools().tools
            let cruas = tools.compactMap { try? MCPTool($0, client: cli, trimming: .init(descriptionLimit: 100_000)) }
            s.tokensCruas = (try? await modelo.tokenCount(for: cruas as [any FoundationModels.Tool])) ?? -1
            for t in cruas { s.porFerramenta[t.name] = (try? await modelo.tokenCount(for: [t] as [any FoundationModels.Tool])) ?? -1 }
            let permitidas = cruas.filter { !bloqueadas.contains($0.name) }
            s.tokensSemBloqueadas = (try? await modelo.tokenCount(for: permitidas as [any FoundationModels.Tool])) ?? -1
            log("composio: \(tools.count) ferramentas = \(s.tokensCruas) tokens (janela \(s.janela)); sem as bloqueadas = \(s.tokensSemBloqueadas)")

            // conexões ativas (ação "list": sem efeito colateral, pela descrição do próprio servidor)
            do {
                s.conexoes = try await texto(cli, "COMPOSIO_MANAGE_CONNECTIONS",
                    ["toolkits": .array(apps.map { .object(["name": .string($0), "action": .string("list")]) })])
                log("composio: conexões → \(s.conexoes.count) caracteres")
            } catch { s.erros.append("conexoes: \(error)") }

            // busca de exemplo (feita pelo código): quanto a resposta pesa na janela
            do {
                s.busca = try await texto(cli, "COMPOSIO_SEARCH_TOOLS",
                    ["queries": .array([.object(["use_case": .string("fetch the latest emails from gmail inbox")])])])
                s.tokensBusca = (try? await modelo.tokenCount(for: Instructions(s.busca))) ?? -1
                log("composio: busca → \(s.busca.count) caracteres = \(s.tokensBusca) tokens")
            } catch { s.erros.append("busca: \(error)") }

            // esquema de uma ferramenta de leitura, cru e enxuto
            do {
                s.esquema = try await texto(cli, "COMPOSIO_GET_TOOL_SCHEMAS", ["tool_slugs": .array([.string("GMAIL_FETCH_EMAILS")])])
                if let d = s.esquema.data(using: .utf8), let v = try? JSONDecoder().decode(Value.self, from: d),
                   let schema = acharEsquema(v) {
                    let t = MCP.Tool(name: "GMAIL_FETCH_EMAILS", description: "Fetch emails from Gmail.", inputSchema: schema)
                    if let enxuta = try? MCPTool(t, client: cli, trimming: .init(descriptionLimit: 160, requiredOnly: true)) {
                        s.tokensEsquemaEnxuto = (try? await modelo.tokenCount(for: [enxuta] as [any FoundationModels.Tool])) ?? -1
                    }
                }
                log("composio: esquema GMAIL_FETCH_EMAILS → enxuto = \(s.tokensEsquemaEnxuto) tokens")
            } catch { s.erros.append("esquema: \(error)") }
            await cli.disconnect()
        } catch { s.erros.append("\(error)"); log("composio: falhou: \(error)") }
        Saida.gravar("composio-sonda.json", s)
        log("composio: sonda gravada (composio-sonda.json)")
    }

    /// Gera links de conexão ("add") para os apps pedidos — escrita só de conexão, autorizada pelo Lucas.
    /// Os links vão para arquivo (fora do git), não para o log.
    static func conectarApps(_ apps: [String], log: @escaping @Sendable (String) -> Void) async {
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            let t = try await texto(cli, "COMPOSIO_MANAGE_CONNECTIONS",
                ["toolkits": .array(apps.map { .object(["name": .string($0), "action": .string("add")]) })])
            Saida.gravar("composio-links.json", ["resposta": t])
            log("composio: links de conexão gravados em composio-links.json (\(apps.joined(separator: ", ")))")
            await cli.disconnect()
        } catch { log("composio: falhou ao gerar links: \(error)") }
    }

    /// Sonda de encanamento (só leitura): executa slugs com argumentos dados e grava a resposta crua.
    /// Uso: --exec '[{"tool_slug":"...","arguments":{...}}]'   ou   --esquemas SLUG1,SLUG2
    static func exec(_ json: String, log: @escaping @Sendable (String) -> Void) async {
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            let v = try JSONDecoder().decode(Value.self, from: Data(json.utf8))
            let t = try await texto(cli, "COMPOSIO_MULTI_EXECUTE_TOOL", ["tools": v, "sync_response_to_workbench": .bool(false),
                                                                         "thought": .string("read-only probe by app code")])
            Saida.gravar("composio-exec.json", ["texto": t]); log("composio exec: \(t.count) caracteres")
            await cli.disconnect()
        } catch { log("composio exec falhou: \(error)") }
    }
    static func esquemas(_ slugs: [String], log: @escaping @Sendable (String) -> Void) async {
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            let t = try await texto(cli, "COMPOSIO_GET_TOOL_SCHEMAS", ["tool_slugs": .array(slugs.map { .string($0) })])
            Saida.gravar("composio-esquemas.json", ["texto": t]); log("composio esquemas: \(t.count) caracteres")
            await cli.disconnect()
        } catch { log("composio esquemas falhou: \(error)") }
    }

    /// Procura o primeiro objeto com "properties" (o input_schema) na resposta.
    static func acharEsquema(_ v: Value) -> Value? {
        switch v {
        case .object(let o):
            if o["properties"] != nil { return v }
            for (_, x) in o { if let r = acharEsquema(x) { return r } }
        case .array(let a): for x in a { if let r = acharEsquema(x) { return r } }
        default: break
        }
        return nil
    }
}
