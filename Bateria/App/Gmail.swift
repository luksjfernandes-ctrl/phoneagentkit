import Foundation
import FoundationModels
import MCP
import PhoneAgentKit

/// Prova do Gmail via Composio (login do próprio usuário), só leitura, só metadado.
/// O modelo recebe no máximo remetente, assunto e data — nunca o corpo. Nenhuma ação (enviar, marcar, apagar).
/// O gabarito é calculado pelo código, no aparelho, a partir da MESMA busca; a resposta do modelo NÃO é gravada
/// (só a nota e a trilha), para nenhum conteúdo de e-mail sair do aparelho.
/// ATENÇÃO: estas perguntas foram escritas por quem escreveu o agente (não são cegas) — declarado no relatório.
enum Gmail {
    struct Msg { let remetente: String; let assunto: String; let data: Date; let naoLida: Bool }
    struct Resultado: Codable { let pergunta: String; let rodada: Int; var trilha: [String] = []; var nota = ""; var erro: String?; var segundos = 0.0 }

    static func buscar(_ cli: Client, consulta: String, max: Int = 50) async throws -> [Msg] {
        let t = try await Composio.texto(cli, "COMPOSIO_MULTI_EXECUTE_TOOL", [
            "tools": .array([.object(["tool_slug": .string("GMAIL_FETCH_EMAILS"), "arguments": .object([
                "query": .string(consulta), "max_results": .int(max), "include_payload": .bool(false), "verbose": .bool(false)])])]),
            "sync_response_to_workbench": .bool(false), "thought": .string("read-only metadata fetch by app code")])
        let v = (try? JSONDecoder().decode(Value.self, from: Data(t.utf8))) ?? .string(t)
        if !estruturaGravada { estruturaGravada = true; Saida.gravar("gmail-estrutura.json", ["chaves": chaves(v)]) }
        return mensagens(em: v)
    }
    nonisolated(unsafe) static var estruturaGravada = false

    /// Só os NOMES dos campos (sem valores), para diagnosticar o formato sem guardar conteúdo.
    static func chaves(_ v: Value, _ prefixo: String = "") -> [String] {
        switch v {
        case .object(let o): return o.flatMap { [prefixo + $0.key] + chaves($0.value, prefixo + $0.key + ".") }
        case .array(let a): return a.first.map { chaves($0, prefixo + "[].") } ?? []
        case .string(let t) where t.hasPrefix("{"): return (try? JSONDecoder().decode(Value.self, from: Data(t.utf8))).map { chaves($0, prefixo) } ?? []
        default: return []
        }
    }

    static func mensagens(em v: Value) -> [Msg] {
        var out: [Msg] = []
        func s(_ o: [String: Value], _ ks: [String]) -> String {
            for k in ks { if case .string(let x)? = o[k], !x.isEmpty { return x } }
            return ""
        }
        func visitar(_ v: Value) {
            switch v {
            case .object(let o):
                if o["subject"] != nil || o["messageId"] != nil {
                    var rot: [String] = []
                    if case .array(let ls)? = o["labelIds"] { rot = ls.compactMap { if case .string(let x) = $0 { return x }; return nil } }
                    let dataTxt = s(o, ["messageTimestamp", "date", "internalDate"])
                    let data = ISO8601DateFormatter().date(from: dataTxt)
                        ?? Double(dataTxt).map { Date(timeIntervalSince1970: $0 > 1e11 ? $0 / 1000 : $0) } ?? .distantPast
                    out.append(Msg(remetente: s(o, ["sender", "from"]), assunto: s(o, ["subject"]), data: data, naoLida: rot.contains("UNREAD")))
                    return
                }
                for (_, x) in o { visitar(x) }
            case .array(let a): a.forEach(visitar)
            case .string(let t) where t.hasPrefix("{") || t.hasPrefix("["):
                if let v2 = try? JSONDecoder().decode(Value.self, from: Data(t.utf8)) { visitar(v2) }
            default: break
            }
        }
        visitar(v)
        return out.sorted { $0.data > $1.data }
    }

    static func nome(_ remetente: String) -> String {   // "Fulano <a@b>" → "Fulano"
        let n = remetente.components(separatedBy: "<").first!.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"")))
        return n.isEmpty ? remetente : n
    }
    static func linha(_ m: Msg) -> String {
        LabeledRecord(id: "", title: m.assunto, fields: [("From", nome(m.remetente)),
            ("Date", Nativo.formato("EEE dd/MM HH:mm").string(from: m.data)), ("Unread", m.naoLida ? "yes" : "no")]).line
    }
    static func contem(_ r: String, _ t: String) -> Bool { !t.isEmpty && PinnedSource.contains(r, String(t.prefix(30))) }

    static func rodar(rodadas: Int = 3, log: @escaping @Sendable (String) -> Void) async {
        log("GMAIL \(ModelInfo.current())")
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            let hoje = Nativo.inicioDoDia(Date()), ontem = Nativo.maisDias(-1, hoje)
            let f = Nativo.formato("yyyy/MM/dd")
            // Gabarito e fatos saem destas buscas (código); o modelo só vê as linhas rotuladas.
            let recentes = try await buscar(cli, consulta: "in:inbox after:\(f.string(from: Nativo.maisDias(-7, hoje)))")
            log("GMAIL \(recentes.count) mensagens (7 dias) lidas pelo código")
            guard let ultima = recentes.first else { log("GMAIL sem mensagens; nada a medir"); return }
            let deHoje = recentes.filter { $0.data >= hoje }, deOntem = recentes.filter { $0.data >= ontem && $0.data < hoje }
            let alvo = nome(recentes.dropFirst().first?.remetente ?? ultima.remetente)
            let doAlvo = recentes.first { nome($0.remetente) == alvo }
            struct P { let id, pedido: String; let menuOk: Int; let ok: (String) -> Bool }
            let perguntas = [
                P(id: "G1", pedido: "Quantos e-mails não lidos eu recebi hoje?", menuOk: 0) {
                    $0.range(of: "(?<![0-9])\(deHoje.filter(\.naoLida).count)(?![0-9])", options: .regularExpression) != nil },
                P(id: "G2", pedido: "Quem mandou o último e-mail?", menuOk: 1) { contem($0, nome(ultima.remetente)) },
                P(id: "G3", pedido: "Qual o assunto do e-mail mais recente de \(alvo)?", menuOk: 2) { contem($0, doAlvo?.assunto ?? "") },
                P(id: "G4", pedido: "Quantos e-mails eu recebi ontem?", menuOk: 3) {
                    $0.range(of: "(?<![0-9])\(deOntem.count)(?![0-9])", options: .regularExpression) != nil },
                P(id: "G5", pedido: "What's the subject of my most recent email?", menuOk: 1) { contem($0, ultima.assunto) },
            ]
            let menu = NumberedMenu(["Unread emails received today", "The most recent email", "The most recent email from a given sender",
                                     "Emails received yesterday", "Emails of the last 7 days"])
            var res: [Resultado] = []
            let arquivo = "gmail-\(Int(Date().timeIntervalSince1970)).json"
            for rodada in 1...rodadas {
                for p in perguntas {
                    var r = Resultado(pergunta: p.id, rodada: rodada)
                    let t0 = Date()
                    do {
                        let e = try await menu.choose(for: p.pedido, instructions: B4.escolha) ?? 4
                        r.trilha.append("visao=\(e + 1)\(e == p.menuOk ? "" : " (esperada \(p.menuOk + 1))")")
                        let sel: [Msg], filtro: String
                        switch e {
                        case 0: (sel, filtro) = (deHoje.filter(\.naoLida), "unread, received today")
                        case 1: (sel, filtro) = ([ultima], "most recent")
                        case 2:
                            let quem = try await LanguageModelSession(instructions: "Extract the sender name the user asks about.")
                                .respond(to: p.pedido, generating: B4.NomePessoa.self).content.nome
                            (sel, filtro) = (Array(recentes.filter { PinnedSource.contains($0.remetente, quem) }.prefix(1)), "most recent from \(quem)")
                        case 3: (sel, filtro) = (deOntem, "received yesterday")
                        default: (sel, filtro) = (recentes, "last 7 days")
                        }
                        let fatos = "\(sel.count) email(s) (\(filtro))" + (sel.isEmpty ? "." : ":\n" + sel.prefix(12).map { "- " + linha($0) }.joined(separator: "\n"))
                        let resposta = try await PinnedSource.answer(p.pedido, source: "Gmail", facts: fatos)
                        r.nota = p.ok(resposta) ? "ok" : "falhou"
                    } catch { r.erro = String("\(error)".prefix(200)); r.nota = "erro" }
                    r.segundos = Date().timeIntervalSince(t0)
                    log(String(format: "GMAIL R%d %@ %.1fs %@ [%@]", rodada, p.id, r.segundos, r.nota, r.trilha.joined(separator: " ")))
                    res.append(r); Saida.gravar(arquivo, res)
                }
            }
            log("GMAIL fim: \(res.filter { $0.nota == "ok" }.count)/\(res.count) → \(arquivo)")
            await cli.disconnect()
        } catch { log("GMAIL falhou: \(error)") }
    }
}
