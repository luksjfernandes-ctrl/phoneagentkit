import Foundation
import FoundationModels
import MCP
import PhoneAgentKit

/// B1 · 3º conector via Composio (GitHub), fonte marcada, só leitura.
/// O usuário aponta o repositório (@dono/repo) e, quando for o caso, a issue (@#n).
/// O modelo escolhe a visão num menu numerado; o CÓDIGO busca pelo Composio (MULTI_EXECUTE), filtra PRs,
/// rotula os campos e monta a lista; o modelo só redige a resposta a partir desses fatos.
/// Tarefas e gabarito vêm de `b1.json` (calculado no Mac pelo gh, na hora da rodada); a correção é feita no Mac.
enum B1 {
    struct Tarefa: Codable { let id: String; let pedido: String }
    struct Arquivo: Codable { let repo: String; let tarefas: [Tarefa] }
    struct Issue { let n: Int; let titulo: String; let estado: String; let criada: String; let rotulos: [String]
                   let responsaveis: [String]; let milestone: String; let prazo: String; let corpo: String }
    struct Resultado: Codable { let tarefa: String; let rodada: Int; var trilha: [String] = []; var resposta = ""; var erro: String?; var segundos = 0.0 }

    static let listar = "GITHUB_LIST_REPOSITORY_ISSUES", obter = "GITHUB_GET_AN_ISSUE"

    static func executar(_ cli: Client, _ slug: String, _ args: [String: Value]) async throws -> Value {
        let t = try await Composio.texto(cli, "COMPOSIO_MULTI_EXECUTE_TOOL", [
            "tools": .array([.object(["tool_slug": .string(slug), "arguments": .object(args)])]),
            "sync_response_to_workbench": .bool(false), "thought": .string("read-only fetch by app code")])
        return (try? JSONDecoder().decode(Value.self, from: Data(t.utf8))) ?? .string(t)
    }

    /// Acha objetos de issue ("number" + "title") em qualquer ponto da resposta; descarta PRs.
    static func issues(em v: Value) -> [Issue] {
        var out: [Issue] = []
        func s(_ o: [String: Value], _ k: String) -> String { if case .string(let x)? = o[k] { return x }; return "" }
        func visitar(_ v: Value) {
            switch v {
            case .object(let o):
                if case .int(let n)? = o["number"], o["title"] != nil {
                    if o["pull_request"] == nil || o["pull_request"] == .null {
                        var rot: [String] = [], resp: [String] = [], ms = "", prazo = ""
                        if case .array(let ls)? = o["labels"] { rot = ls.compactMap { if case .object(let l) = $0 { return s(l, "name") }; return nil } }
                        if case .array(let as_)? = o["assignees"] { resp = as_.compactMap { if case .object(let a) = $0 { return s(a, "login") }; return nil } }
                        if case .object(let m)? = o["milestone"] { ms = s(m, "title"); prazo = s(m, "due_on") }
                        out.append(Issue(n: n, titulo: s(o, "title"), estado: s(o, "state"), criada: String(s(o, "created_at").prefix(10)),
                                         rotulos: rot, responsaveis: resp, milestone: ms, prazo: prazo, corpo: String(s(o, "body").prefix(1200))))
                    }
                    return
                }
                for (_, x) in o { visitar(x) }
            case .array(let a): a.forEach(visitar)
            case .string(let t):   // resposta aninhada como texto JSON
                if t.hasPrefix("{") || t.hasPrefix("["), let v2 = try? JSONDecoder().decode(Value.self, from: Data(t.utf8)) { visitar(v2) }
            default: break
            }
        }
        visitar(v)
        var vistos = Set<Int>()
        return out.filter { vistos.insert($0.n).inserted }
    }

    static func abertas(_ cli: Client, dono: String, repo: String) async throws -> [Issue] {
        var todas: [Issue] = []
        for pagina in 1...5 {
            let v = try await executar(cli, listar, ["owner": .string(dono), "repo": .string(repo), "state": .string("open"),
                                                     "per_page": .int(100), "page": .int(pagina)])
            let lote = issues(em: v)
            todas += lote
            if lote.isEmpty { break }
        }
        var vistos = Set<Int>()
        return todas.filter { vistos.insert($0.n).inserted }
    }

    static func registro(_ i: Issue) -> LabeledRecord {
        LabeledRecord(id: "#\(i.n)", title: i.titulo, fields: [
            ("State", i.estado), ("Created", i.criada), ("Labels", i.rotulos.isEmpty ? "none" : i.rotulos.joined(separator: ", ")),
            ("Assignees", i.responsaveis.isEmpty ? "none" : i.responsaveis.joined(separator: ", ")),
            ("Milestone", i.milestone.isEmpty ? "none" : i.milestone + (i.prazo.isEmpty ? " (no due date)" : " (due \(i.prazo.prefix(10)))"))])
    }

    static func lista(_ is_: [Issue], fonte: String, filtro: String, limite: Int = 15) -> String {
        "\(is_.count) open issue(s) in \(fonte) (\(filtro))" + (is_.isEmpty ? "." :
            (is_.count > limite ? ", showing the first \(limite):\n" : ":\n") + is_.prefix(limite).map { "- " + registro($0).line }.joined(separator: "\n"))
    }

    static let escolha = "Pick the option that best answers the user's request."

    static func responder(_ pedido: String, cli: Client, dono: String, repo: String, trilha: inout [String]) async throws -> String {
        let fonte = "\(dono)/\(repo)"
        // @#n no pedido = item marcado pelo usuário: o código busca a issue, sem menu
        if let r = pedido.range(of: #"@#(\d+)"#, options: .regularExpression), let n = Int(pedido[r].dropFirst(2)) {
            trilha.append("item=#\(n)")
            let v = try await executar(cli, obter, ["owner": .string(dono), "repo": .string(repo), "issue_number": .int(n)])
            guard let i = issues(em: v).first(where: { $0.n == n }) else { return "Não encontrei a issue #\(n) em \(fonte)." }
            return try await PinnedSource.answer(pedido, source: "\(fonte) #\(n)",
                facts: registro(i).line + "\nBody (excerpt): " + i.corpo, labeled: registro(i))
        }
        let todas = try await abertas(cli, dono: dono, repo: repo)
        trilha.append("abertas=\(todas.count)")
        let menu = NumberedMenu(["Count of open issues", "The oldest open issue", "Open issues with a given label",
                                 "Overdue open issues (milestone due date already passed)", "All open issues"])
        let e = try await menu.choose(for: pedido, instructions: escolha) ?? 4
        trilha.append("visao=\(e + 1)")
        let fatos: String
        switch e {
        case 0: fatos = "\(todas.count) open issue(s) in \(fonte)."
        case 1: fatos = lista(todas.sorted { $0.criada < $1.criada }.prefix(1).map { $0 }, fonte: fonte, filtro: "oldest open issue")
        case 2:
            let rotulos = Array(Set(todas.flatMap(\.rotulos))).sorted()
            let m2 = NumberedMenu(rotulos)
            let k = try await m2.choose(for: pedido, instructions: escolha)
            let r = k.map { rotulos[$0] } ?? ""
            trilha.append("rotulo=\(r)")
            fatos = lista(todas.filter { $0.rotulos.contains(r) }.sorted { $0.n < $1.n }, fonte: fonte, filtro: "label \(r)")
        case 3:
            let hoje = ISO8601DateFormatter().string(from: Date())
            fatos = lista(todas.filter { !$0.prazo.isEmpty && $0.prazo < hoje }, fonte: fonte, filtro: "overdue by milestone due date")
                + "\n(Open milestones without a due date do not count as overdue.)"
        default: fatos = lista(todas, fonte: fonte, filtro: "all open")
        }
        return try await PinnedSource.answer(pedido, source: fonte, facts: fatos)
    }

    static func rodar(rodadas: Int = 3, log: @escaping @Sendable (String) -> Void) async {
        guard let d = try? Data(contentsOf: Conectores.pasta().appending(path: "b1.json")),
              let arq = try? JSONDecoder().decode(Arquivo.self, from: d) else { log("B1 sem b1.json"); return }
        let partes = arq.repo.split(separator: "/").map(String.init)
        let args = ProcessInfo.processInfo.arguments
        let commit = args.firstIndex(of: "--commit").map { args[$0 + 1] } ?? "?"
        log("B1 \(ModelInfo.current()) commit=\(commit) repo=\(arq.repo)")
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            // confere os slugs antes de medir (sem isso, erro de slug viraria "erro do modelo")
            let sch = try await Composio.texto(cli, "COMPOSIO_GET_TOOL_SCHEMAS", ["tool_slugs": .array([.string(listar), .string(obter)])])
            Saida.gravar("b1-esquemas.json", ["texto": sch])
            log("B1 esquemas: \(sch.count) caracteres")
            var res: [Resultado] = []
            let arquivo = "b1-\(Int(Date().timeIntervalSince1970)).json"
            for rodada in 1...rodadas {
                for t in arq.tarefas {
                    var r = Resultado(tarefa: t.id, rodada: rodada)
                    let t0 = Date()
                    do { r.resposta = try await responder(t.pedido, cli: cli, dono: partes[0], repo: partes[1], trilha: &r.trilha) }
                    catch { r.erro = String("\(error)".prefix(300)) }
                    r.segundos = Date().timeIntervalSince(t0)
                    log(String(format: "B1 R%d %@ %.1fs [%@] → %@", rodada, t.id, r.segundos, r.trilha.joined(separator: " "),
                               String((r.erro ?? r.resposta).prefix(160))))
                    res.append(r); Saida.gravar(arquivo, res)
                }
            }
            log("B1 fim → \(arquivo)")
            await cli.disconnect()
        } catch { log("B1 falhou: \(error)") }
    }
}
