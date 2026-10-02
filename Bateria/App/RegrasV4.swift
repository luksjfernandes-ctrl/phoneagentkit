import Foundation
import FoundationModels
import MCP
import PhoneAgentKit

// Regras compartilhadas pelo app e pelos testes locais, sem consultar contas.
extension V3 {
    static func falha(_ mensagem: String) -> NSError {
        NSError(domain: "V3", code: 8, userInfo: [NSLocalizedDescriptionKey: mensagem])
    }

    struct Referencia {
        let texto: String
        let suspeitos: [String]
        let cortes: [String]
    }

    static func referencia(origem: String?, fontes: [String: String], literal: String) throws -> Referencia {
        let bruto: String
        if let origem {
            guard let texto = V4Safety.sourceText(for: origem, sources: fontes) else {
                throw falha("Leitura obrigatória da origem \(origem) ausente ou vazia")
            }
            bruto = texto
        } else {
            bruto = literal
        }
        // As guardas recebem o texto inteiro, antes de qualquer truncamento.
        let filtrado = UntrustedText.filter(bruto)
        let guardado = UntrustedText.guardOutput(filtrado.kept, request: "referência do item")
        let linha = guardado.kept.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return Referencia(texto: linha.map { String($0.prefix(120)) } ?? "item lido",
                          suspeitos: filtrado.suspicious, cortes: guardado.cut)
    }

    struct Proposta {
        let titulo: String
        let decisao: V4Safety.PastDateDecision
        var quando: Date { decisao.date }
        var confirmacao: String {
            "Criar lembrete: \(titulo) · \(Nativo.formato("yyyy-MM-dd HH:mm").string(from: quando))"
                + (decisao.warning.map { "\n\($0)" } ?? "\nConfirma?")
        }
    }

    /// O texto apresentado deve ser o da proposta inteira, inclusive o aviso.
    /// A gravação injetável permite provar o bloqueio sem abrir o EventKit.
    static func confirmar(_ p: Proposta, toque: Bool, confirmacaoApresentada: String?,
                          gravar: (V2.Proposta) throws -> Bool = { try V2.confirmar($0, toque: true) }) throws -> Bool {
        guard toque else { return false }
        if p.decisao.requiresConfirmation || p.decisao.warning != nil {
            guard confirmacaoApresentada == p.confirmacao else {
                throw falha("Confirmação não apresentou a proposta e seu aviso")
            }
        }
        return try gravar(V2.Proposta(titulo: p.titulo, quando: p.quando))
    }

    /// A apresentação acontece antes do toque simulado, mesmo no harness local.
    static func confirmarNoHarness(_ p: Proposta, apresentar: (String) -> Void,
                                   gravar: (V2.Proposta) throws -> Bool = { try V2.confirmar($0, toque: true) }) throws -> Bool {
        let texto = p.confirmacao
        apresentar(texto)
        return try confirmar(p, toque: true, confirmacaoApresentada: texto, gravar: gravar)
    }

    @Generable struct PEmail {
        @Guide(description: "Remetente citado na frase; vazio se nenhum") var remetente: String
        @Guide(description: "Assunto ou trecho de assunto citado; vazio se nenhum") var assunto: String
        @Guide(description: "Início do período yyyy-MM-dd HH:mm pelo calendário; vazio se nenhum") var desde: String
        @Guide(description: "Fim exclusivo do período yyyy-MM-dd HH:mm; vazio se nenhum") var ate: String
        @Guide(description: "true somente se a frase pedir não lidos") var naoLidos: Bool
    }

    static func consultaEmail(_ p: PEmail, chip: String) throws -> String {
        func citado(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var partes: [String] = []
        if !p.remetente.isEmpty { partes.append("from:\(citado(p.remetente))") }
        if !p.assunto.isEmpty { partes.append("subject:\(citado(p.assunto))") }
        if p.naoLidos || chip == "mais_antigo_nao_lido" { partes.append("is:unread") }
        for (valor, operador) in [(p.desde, "after"), (p.ate, "before")] where !valor.isEmpty {
            guard let d = V2.data(valor) else { throw falha("Período inválido no pedido: \(valor)") }
            partes.append("\(operador):\(V2.epoch(d))")
        }
        return partes.joined(separator: " ")
    }

    static func maisAntigoNaoLido(_ mensagens: [V2.Msg]) -> V2.Msg? {
        mensagens.filter(\.naoLida).min { $0.data < $1.data }
    }

    /// Não recebe a tarefa nem sua consulta de gabarito: só a frase do usuário.
    static func emailsDoPedido(_ frase: String, chip: String, agora: Date,
                              extrair: (String, Date) async throws -> PEmail,
                              buscar: (String, Int) async throws -> [V2.Msg]) async throws -> [V2.Msg] {
        let p = try await extrair(frase, agora)
        let mensagens = try await buscar(consultaEmail(p, chip: chip), 500)
        if chip == "mais_antigo_nao_lido" { return maisAntigoNaoLido(mensagens).map { [$0] } ?? [] }
        return Array(mensagens.sorted { $0.data > $1.data }.prefix(1))
    }

    static func fonteEmailSelecionado(_ selecionados: [String: V2.Msg]) -> [String: String] {
        selecionados.mapValues { "E-mail — \($0.assunto)" }
    }

    static func avaliarG(_ resp: String, tarefa t: GTarefa, gabarito gab: [V2.Msg]) -> Bool {
        // A consulta independente pode vir em ordem decrescente e incluir lidos.
        let alvo = t.chip == "mais_antigo_nao_lido" || ["mais_antigo", "mais_antigo_nao_lido"].contains(t.tipo)
            ? maisAntigoNaoLido(gab) : gab.first
        switch t.tipo {
        case "contagem": return V2.num(resp, gab.count)
        case "existe": return gab.isEmpty ? V2.nega(resp) : V2.num(resp, gab.count) && !resp.lowercased().hasPrefix("não")
        case "assunto": return alvo.map { V2.cita(resp, $0.assunto) } ?? V2.nega(resp)
        case "data", "quando": return alvo.map { V2.cita(resp, Nativo.formato("yyyy-MM-dd HH:mm").string(from: $0.data)) } ?? V2.nega(resp)
        case "remetente", "quem_mandou": return alvo.map { V2.cita(resp, Gmail.nome($0.remetente)) } ?? V2.nega(resp)
        case "mais_antigo", "mais_antigo_nao_lido":
            return alvo.map { V2.cita(resp, $0.assunto) && V2.cita(resp, Gmail.nome($0.remetente)) } ?? V2.nega(resp)
        default:
            let assuntos = gab.prefix(t.n ?? 3).map(\.assunto)
            let pos = assuntos.map { a in resp.lowercased().range(of: String(a.lowercased().prefix(30)))?.lowerBound }
            return assuntos.count == (t.n ?? 3) && pos.allSatisfy { $0 != nil } && pos.map { $0! } == pos.map { $0! }.sorted()
        }
    }

    static func ehPR(chip: String, frase: String) -> Bool {
        chip == "resumir_pr" || frase.range(of: #"\b(?:pr|pull\s+request)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func objetoGitHub(_ v: Value, numero: Int) -> [String: Value]? {
        switch v {
        case .object(let o):
            if o["title"] != nil, o["number"] == .int(numero) || o["number"] == .double(Double(numero)) { return o }
            for x in o.values { if let encontrado = objetoGitHub(x, numero: numero) { return encontrado } }
        case .array(let a):
            for x in a { if let encontrado = objetoGitHub(x, numero: numero) { return encontrado } }
        case .string(let s):
            if let decodificado = try? JSONDecoder().decode(Value.self, from: Data(s.utf8)) { return objetoGitHub(decodificado, numero: numero) }
        default: break
        }
        return nil
    }

    static func autorGitHub(_ objeto: [String: Value]) -> String {
        guard case .object(let usuario)? = objeto["user"], case .string(let login)? = usuario["login"], !login.isEmpty else { return "desconhecido" }
        return login
    }

    static func metadadoH(chip: String, frase: String, numero: Int, dono: String, repo: String,
                          executar: (String, [String: Value]) async throws -> Value) async throws -> String {
        let pr = ehPR(chip: chip, frase: frase)
        let endpoint = pr ? "GITHUB_GET_A_PULL_REQUEST" : "GITHUB_GET_AN_ISSUE"
        let chave = pr ? "pull_number" : "issue_number"
        let valor = try await executar(endpoint, ["owner": .string(dono), "repo": .string(repo), chave: .int(numero)])
        guard let objeto = objetoGitHub(valor, numero: numero) else { throw falha("Item \(numero) não encontrado") }
        let tipo = pr ? "PR" : "issue"
        if chip == "autor" { return "Autor da \(tipo) #\(numero): \(autorGitHub(objeto))." }
        let fechamento: String
        if case .string(let data)? = objeto["closed_at"], !data.isEmpty { fechamento = data }
        else { fechamento = "aberta" }
        return "closed_at da \(tipo) #\(numero): \(fechamento)."
    }

    static func avaliarMetadadoH(_ resp: String, tarefa t: V2.H) throws -> Bool {
        let esperado: String
        if t.chip == "autor" {
            guard let autor = t.autor, !autor.isEmpty else { throw falha("Gabarito de autor ausente em \(t.id)") }
            esperado = autor
        } else {
            if let data = t.closed_at, !data.isEmpty { esperado = data }
            else if t.estado == "open" { esperado = "aberta" }
            else { throw falha("Gabarito de closed_at ausente em \(t.id)") }
        }
        // As respostas desses chips são montadas por código: compare o valor inteiro.
        let rotulo = t.chip == "autor" ? "Autor " : "closed_at "
        guard resp.hasPrefix(rotulo), let separador = resp.range(of: ": ") else { return false }
        var valor = String(resp[separador.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if valor.hasSuffix(".") { valor.removeLast() }
        return valor.caseInsensitiveCompare(esperado) == .orderedSame
    }
}
