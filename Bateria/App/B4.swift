import Foundation
import FoundationModels
import PhoneAgentKit

/// B4 · nativo sem conector. Dois agentes nas mesmas tarefas:
/// - "kit": padrão do PhoneAgentKit, só leitura. O modelo escolhe num menu numerado, o código busca e rotula,
///   o modelo redige só a partir dos fatos (`PinnedSource.answer`). Datas saem do código.
/// - "v2": linha de base, tool calling livre como na bateria de 23/09 (ferramentas só de leitura).
/// O gabarito é calculado por código, da mesma loja, no instante da tarefa.
enum B4 {
    // MARK: Agente do kit

    static let escolha = "Pick the option that best answers the user's request."

    static func kit(_ pedido: String, agora: Date, trilha: inout [String]) async throws -> String {
        let fontes = NumberedMenu([
            "Calendar events (agenda, compromissos)",
            "Reminders (lembretes)",
            "A contact's phone or e-mail (contatos)",
            "Photos: when a photo was taken (fotos)",
            "Dates: which weekday a date falls on (calendário)",
        ])
        let f = try await fontes.choose(for: pedido, instructions: escolha)
        trilha.append("fonte=\(f.map { $0 + 1 } ?? 0)")
        let agoraTxt = "Now: " + Nativo.formato("EEEE dd/MM/yyyy HH:mm").string(from: agora)
        switch f {
        case 0:
            let (rotulo, eventos) = try await periodo(pedido, agora: agora, trilha: &trilha)
            let recs = eventos.map { LabeledRecord(id: "", title: $0.titulo, fields: [("When", quando($0))]) }
            return try await PinnedSource.answer(pedido, source: "Calendar",
                facts: agoraTxt + "\n" + PinnedSource.renderList(recs, source: "Calendar", filter: rotulo))
        case 1:
            let abertos = await Nativo.lembretesAbertos()
            let listas = Nativo.listasDeLembretes()
            let menu = NumberedMenu(["Overdue reminders", "Reminders due today", "All open reminders"]
                                    + listas.map { "Open reminders in the list \"\($0)\"" })
            let e = try await menu.choose(for: pedido, instructions: escolha) ?? 2
            trilha.append("lembretes=\(e + 1)")
            let hoje = Nativo.inicioDoDia(agora)
            let (rotulo, sel): (String, [Nativo.Lembrete]) = switch e {
            case 0: ("overdue", abertos.filter { Nativo.atrasado($0, agora: agora) })
            case 1: ("due today", abertos.filter { $0.vence.map { Nativo.inicioDoDia($0) == hoje } ?? false })
            case 2: ("open", abertos)
            default: ("list \(listas[e - 3])", abertos.filter { $0.lista == listas[e - 3] })
            }
            let recs = sel.map { l in
                LabeledRecord(id: "", title: l.titulo, fields: [("Due", l.vence.map { venc($0, hora: l.temHora) } ?? "no date"), ("List", l.lista)])
            }
            return try await PinnedSource.answer(pedido, source: "Reminders",
                facts: agoraTxt + "\n" + PinnedSource.renderList(recs, source: "Reminders", filter: rotulo))
        case 2:
            let nome = try await LanguageModelSession(instructions: "Extract the name of the person the user asks about.")
                .respond(to: pedido, generating: NomePessoa.self).content.nome
            trilha.append("nome=\(nome)")
            var achados = Nativo.contatos(nome: nome)
            if achados.isEmpty, let primeiro = nome.split(separator: " ").first { achados = Nativo.contatos(nome: String(primeiro)) }
            let recs = achados.prefix(5).map { c in
                LabeledRecord(id: "", title: c.nome, fields: [("Phone", c.telefones.joined(separator: ", ").ifEmpty("none")),
                                                             ("E-mail", c.emails.joined(separator: ", ").ifEmpty("none"))])
            }
            return try await PinnedSource.answer(pedido, source: "Contacts",
                facts: PinnedSource.renderList(Array(recs), source: "Contacts", filter: "name \(nome)"))
        case 3:
            let fato = Nativo.ultimaFoto().map { "Most recent photo taken: " + Nativo.formato("EEEE dd/MM/yyyy HH:mm").string(from: $0) }
                ?? "No photos in the library."
            return try await PinnedSource.answer(pedido, source: "Photos", facts: agoraTxt + "\n" + fato)
        case 4:
            return try await PinnedSource.answer(pedido, source: "Calendar table", facts: agoraTxt + "\n" + tabelaMeses(agora))
        default:
            return "Não sei qual fonte responde a isso."
        }
    }

    @Generable struct NomePessoa { @Guide(description: "Person's name as written by the user") var nome: String }

    /// Período por menu; as datas vêm do código.
    static func periodo(_ pedido: String, agora: Date, trilha: inout [String]) async throws -> (String, [Nativo.Evento]) {
        let hoje = Nativo.inicioDoDia(agora), d = Nativo.formato("EEEE dd/MM", "en_US")
        let sab = Nativo.proximo(7, depoisDe: Nativo.maisDias(-1, hoje))
        let dias = (1...7).map { Nativo.maisDias($0, hoje) }
        let menu = NumberedMenu(["Today (\(d.string(from: hoje)))", "Tomorrow (\(d.string(from: dias[0])))",
                                 "The next upcoming event", "This weekend (\(d.string(from: sab)) and \(d.string(from: Nativo.maisDias(1, sab))))",
                                 "The next 7 days"] + dias.map { d.string(from: $0) })
        let e = try await menu.choose(for: pedido, instructions: escolha) ?? 4
        trilha.append("periodo=\(e + 1)")
        switch e {
        case 0: return ("today", Nativo.eventos(de: hoje, ate: Nativo.maisDias(1, hoje)))
        case 1: return ("tomorrow", Nativo.eventos(de: dias[0], ate: dias[1]))
        case 2:
            let prox = Nativo.eventos(de: agora, ate: Nativo.maisDias(60, agora)).first { $0.inicio >= agora }
            return ("next upcoming", prox.map { [$0] } ?? [])
        case 3: return ("weekend", Nativo.eventos(de: sab, ate: Nativo.maisDias(2, sab)))
        case 4: return ("next 7 days", Nativo.eventos(de: agora, ate: Nativo.maisDias(7, hoje)))
        default:
            let x = dias[e - 5]
            return (d.string(from: x), Nativo.eventos(de: x, ate: Nativo.maisDias(1, x)))
        }
    }

    static func quando(_ e: Nativo.Evento) -> String {
        let d = Nativo.formato("EEE dd/MM")
        return e.diaTodo ? "\(d.string(from: e.inicio)) all day" : "\(d.string(from: e.inicio)) \(Nativo.hora.string(from: e.inicio))–\(Nativo.hora.string(from: e.fim))"
    }
    static func venc(_ v: Date, hora: Bool) -> String { Nativo.formato(hora ? "EEE dd/MM HH:mm" : "EEE dd/MM").string(from: v) }

    static func tabelaMeses(_ agora: Date) -> String {
        let c = Nativo.cal, ini = c.date(from: c.dateComponents([.year, .month], from: agora))!
        let fim = c.date(byAdding: .month, value: 2, to: ini)!
        var linhas: [String] = [], x = ini
        let f = Nativo.formato("dd/MM/yyyy"), s = Nativo.formato("EEEE"), s2 = Nativo.formato("EEEE", "en_US")
        while x < fim { linhas.append("\(f.string(from: x)) = \(s.string(from: x)) (\(s2.string(from: x)))"); x = Nativo.maisDias(1, x) }
        return linhas.joined(separator: "\n")
    }

    // MARK: Linha de base v2 (tool calling livre, instruções de 23/09 com o idioma do pedido)

    static func instrucoesV2(_ agora: Date) -> String {
        let semana = Nativo.formato("EEEE")
        let tabela = (0...7).map { i in
            let x = Nativo.maisDias(i, agora)
            return "\(semana.string(from: x)) = \(Nativo.dia.string(from: x))\(i == 0 ? " (hoje)" : i == 1 ? " (amanhã)" : "")"
        }.joined(separator: "\n")
        return """
            Assistente no iPhone do usuário. Horário de Brasília, agora \(Nativo.hora.string(from: agora)).
            Calendário (use exatamente estas datas):
            \(tabela)
            Regras:
            - Pedido sobre agenda, lembrete, contato ou foto: chame a ferramenta, não pergunte.
            - Converta dia da semana e "amanhã" usando o calendário acima.
            - Só pergunte se faltar QUEM ou O QUÊ (ex.: "aquilo", "ele").
            - Responda no idioma do pedido, curto, só com dados que vieram das ferramentas.
            """
    }

    struct LerAgenda: FoundationModels.Tool {
        let name = "ler_agenda"
        let description = "Lista os eventos da agenda do usuário entre duas datas."
        @Generable struct Arguments {
            @Guide(description: "Primeiro dia, yyyy-MM-dd") var inicio: String
            @Guide(description: "Último dia (inclusive), yyyy-MM-dd") var fim: String
        }
        func call(arguments a: Arguments) async throws -> String {
            guard let i = Nativo.dia.date(from: a.inicio), let f = Nativo.dia.date(from: a.fim) else { return "Datas inválidas." }
            let ev = Nativo.eventos(de: i, ate: Nativo.maisDias(1, f))
            if ev.isEmpty { return "Nenhum evento entre \(a.inicio) e \(a.fim)." }
            return ev.prefix(25).map { "\(quando($0)): \($0.titulo)" }.joined(separator: "\n")
        }
    }

    struct LerLembretes: FoundationModels.Tool {
        let name = "ler_lembretes"
        let description = "Lista os lembretes em aberto do usuário, com data de vencimento e lista."
        @Generable struct Arguments { @Guide(description: "Nome da lista, ou vazio para todas") var lista: String }
        func call(arguments a: Arguments) async throws -> String {
            let ls = await Nativo.lembretesAbertos().filter { a.lista.isEmpty || PinnedSource.contains($0.lista, a.lista) }
            if ls.isEmpty { return "Nenhum lembrete em aberto." }
            return ls.prefix(30).map { "\($0.titulo) · vence: \($0.vence.map { venc($0, hora: true) } ?? "sem data") · lista: \($0.lista)" }
                .joined(separator: "\n")
        }
    }

    struct BuscarContato: FoundationModels.Tool {
        let name = "buscar_contato"
        let description = "Busca um contato do usuário pelo nome e devolve telefones e e-mails."
        @Generable struct Arguments { @Guide(description: "Nome ou parte do nome") var nome: String }
        func call(arguments a: Arguments) async throws -> String {
            let cs = Nativo.contatos(nome: a.nome)
            if cs.isEmpty { return "Nenhum contato encontrado para '\(a.nome)'." }
            return cs.prefix(5).map { "\($0.nome): tel \($0.telefones.joined(separator: ", ").ifEmpty("—")); email \($0.emails.joined(separator: ", ").ifEmpty("—"))" }
                .joined(separator: "\n")
        }
    }

    struct UltimaFoto: FoundationModels.Tool {
        let name = "ultima_foto"
        let description = "Devolve a data e hora da foto mais recente da fototeca."
        @Generable struct Arguments { @Guide(description: "Deixe vazio") var nada: String }
        func call(arguments a: Arguments) async throws -> String {
            Nativo.ultimaFoto().map { Nativo.formato("EEEE dd/MM/yyyy HH:mm").string(from: $0) } ?? "Nenhuma foto."
        }
    }

    static func v2(_ pedido: String, agora: Date, trilha: inout [String]) async throws -> String {
        let s = LanguageModelSession(tools: [LerAgenda(), LerLembretes(), BuscarContato(), UltimaFoto()], instructions: instrucoesV2(agora))
        defer {
            for e in s.transcript { if case .toolCalls(let cs) = e { for c in cs { trilha.append("\(c.toolName)\(c.arguments.jsonString)") } } }
        }
        return try await s.respond(to: pedido).content
    }

    // MARK: Tarefas cegas (tarefas-v1.md, B4) e gabarito por código

    enum Gabarito: Codable {
        case titulos([String])     // vazio = a resposta tem de dizer que não há nada
        case numero(Int)
        case telefone([String])    // só dígitos
        case foto(Date?)
        case diaSemana(pt: String, en: String)
    }

    struct Tarefa { let id: String; let pedido: String; let gabarito: Gabarito; let idioma: String }

    static func tarefas(agora: Date, sorteio: inout Sorteio) async -> [Tarefa] {
        let hoje = Nativo.inicioDoDia(agora), amanha = Nativo.maisDias(1, hoje)
        let sexta = Nativo.proximo(6, depoisDe: hoje)
        let sab = Nativo.proximo(7, depoisDe: Nativo.maisDias(-1, hoje))
        let abertos = await Nativo.lembretesAbertos()
        let comTel = Nativo.todosComTelefone()
        let contato = comTel.isEmpty ? nil : comTel[sorteio.proximo(comTel.count)]
        let listasCheias = Array(Set(abertos.map(\.lista))).sorted()
        let lista = listasCheias.isEmpty ? "" : listasCheias[sorteio.proximo(listasCheias.count)]
        let c = Nativo.cal
        let mesQueVem = c.date(byAdding: .month, value: 1, to: c.date(from: c.dateComponents([.year, .month], from: agora))!)!
        let dia10 = c.date(byAdding: .day, value: 9, to: mesQueVem)!
        func t(_ e: [Nativo.Evento]) -> Gabarito { .titulos(e.map(\.titulo)) }
        let tarde = Nativo.eventos(de: c.date(byAdding: .hour, value: 12, to: sexta)!, ate: c.date(byAdding: .hour, value: 18, to: sexta)!)
        let prox = Nativo.eventos(de: agora, ate: Nativo.maisDias(60, agora)).first { $0.inicio >= agora }
        return [
            Tarefa(id: "B4.1", pedido: "O que eu tenho amanhã?", gabarito: t(Nativo.eventos(de: amanha, ate: Nativo.maisDias(1, amanha))), idioma: "pt"),
            Tarefa(id: "B4.2", pedido: "Qual é meu próximo compromisso?", gabarito: t(prox.map { [$0] } ?? []), idioma: "pt"),
            Tarefa(id: "B4.3", pedido: "Quais lembretes estão atrasados?", gabarito: .titulos(abertos.filter { Nativo.atrasado($0, agora: agora) }.map(\.titulo)), idioma: "pt"),
            Tarefa(id: "B4.4", pedido: "Qual o telefone de \(contato?.nome ?? "(sem contato)")?",
                   gabarito: .telefone(contato?.telefones.map(digitos) ?? []), idioma: "pt"),
            Tarefa(id: "B4.5", pedido: "Tenho algo na sexta à tarde?", gabarito: t(tarde), idioma: "pt"),
            Tarefa(id: "B4.6", pedido: "What's on my calendar this weekend?", gabarito: t(Nativo.eventos(de: sab, ate: Nativo.maisDias(2, sab))), idioma: "en"),
            Tarefa(id: "B4.7", pedido: "Quantos lembretes eu tenho na lista \(lista)?", gabarito: .numero(abertos.filter { $0.lista == lista }.count), idioma: "pt"),
            Tarefa(id: "B4.8", pedido: "Quando foi a última foto que tirei?", gabarito: .foto(Nativo.ultimaFoto()), idioma: "pt"),
            Tarefa(id: "B4.9", pedido: "Do I have any reminders due today?",
                   gabarito: .titulos(abertos.filter { $0.vence.map { Nativo.inicioDoDia($0) == hoje } ?? false }.map(\.titulo)), idioma: "en"),
            Tarefa(id: "B4.10", pedido: "Que dia da semana cai o dia 10 do mês que vem?",
                   gabarito: .diaSemana(pt: Nativo.formato("EEEE").string(from: dia10), en: Nativo.formato("EEEE", "en_US").string(from: dia10)), idioma: "pt"),
        ]
    }

    static func digitos(_ s: String) -> String { s.filter(\.isNumber) }
    static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
    // sem "no "/"sem ": em pt "no" é "em o" e daria falso acerto
    static let negativas = ["nao ", "nenhum", "nada", "none", "nothing", "no event", "no reminder", "no photo", "don't", "do not", "there are no", "you have no", "0 item"]

    /// "ok" ou "falhou: …". Não detecta invenção de item extra: isso vai para a revisão manual dos brutos.
    static func corrigir(_ r: String, _ g: Gabarito) -> String {
        let n = norm(r)
        switch g {
        case .titulos(let ts) where ts.isEmpty:
            return negativas.contains { n.contains($0) } ? "ok" : "falhou: esperava 'nada'"
        case .titulos(let ts):
            let faltam = ts.filter { !n.contains(norm(String($0.prefix(25)))) }
            return faltam.isEmpty ? "ok" : "falhou: faltam \(faltam.count)/\(ts.count)"
        case .numero(let k):
            let achou = r.range(of: "(?<![0-9])\(k)(?![0-9])", options: .regularExpression) != nil
            return achou ? "ok" : "falhou: esperava \(k)"
        case .telefone(let ts):
            let d = digitos(r)
            return ts.contains { d.contains(String($0.suffix(8))) } ? "ok" : "falhou: telefone ausente"
        case .foto(let data):
            guard let data else { return negativas.contains { n.contains($0) } ? "ok" : "falhou: esperava 'sem fotos'" }
            let c = Nativo.cal, dia = c.component(.day, from: data), mes = c.component(.month, from: data)
            let meses = [Nativo.formato("MMMM"), Nativo.formato("MMMM", "en_US"), Nativo.formato("MMM", "en_US")].map { norm($0.string(from: data)) }
            let temNum = r.range(of: String(format: "(?<![0-9])0?%d/0?%d(?![0-9])", dia, mes), options: .regularExpression) != nil
            let temNome = meses.contains { n.contains($0) } && r.range(of: "(?<![0-9])0?\(dia)(?![0-9])", options: .regularExpression) != nil
            let relativo = c.isDateInToday(data) && (n.contains("hoje") || n.contains("today"))
            return temNum || temNome || relativo ? "ok" : "falhou: data da foto ausente"
        case .diaSemana(let pt, let en):
            let alvo = norm(pt).components(separatedBy: "-").first ?? norm(pt)
            return n.contains(alvo) || n.contains(norm(en)) ? "ok" : "falhou: esperava \(pt)"
        }
    }

    // MARK: Execução

    struct Resultado: Codable {
        let modo: String, tarefa: String, rodada: Int, idioma: String, pedido: String
        let gabarito: Gabarito
        var trilha: [String] = []
        var resposta = ""
        var erro: String?
        var segundos = 0.0
        var nota = ""
    }
    struct Relatorio: Codable {
        let aparelho: String, commit: String, semente: UInt64, inicio: Date
        var resultados: [Resultado] = []
    }

    static func rodar(rodadas: Int = 3, modos: [String] = ["kit", "v2"], log: @escaping @Sendable (String) -> Void) async {
        guard await Permissoes.pedir(log: log) else { log("B4 sem permissões; parei"); return }
        let info = ModelInfo.current()
        let args = ProcessInfo.processInfo.arguments
        let commit = args.firstIndex(of: "--commit").map { args[$0 + 1] } ?? "?"
        var sorteio = Sorteio(semente: UInt64(Date().timeIntervalSince1970))
        var rel = Relatorio(aparelho: info.description, commit: commit, semente: sorteio.semente, inicio: Date())
        log("B4 \(info) commit=\(commit) semente=\(sorteio.semente)")
        let arquivo = "b4-\(Int(rel.inicio.timeIntervalSince1970)).json"
        for rodada in 1...rodadas {
            for modo in modos {
                var s = Sorteio(semente: sorteio.semente)   // mesmo sorteio nas rodadas e nos modos
                for t in await tarefas(agora: Date(), sorteio: &s) {
                    var r = Resultado(modo: modo, tarefa: t.id, rodada: rodada, idioma: t.idioma, pedido: t.pedido, gabarito: t.gabarito)
                    let t0 = Date()
                    do {
                        r.resposta = modo == "kit" ? try await kit(t.pedido, agora: t0, trilha: &r.trilha)
                                                   : try await v2(t.pedido, agora: t0, trilha: &r.trilha)
                    } catch { r.erro = String("\(error)".prefix(200)) }
                    r.segundos = Date().timeIntervalSince(t0)
                    r.nota = r.erro.map { "falhou: erro \($0)" } ?? corrigir(r.resposta, t.gabarito)
                    r.resposta = mascarar(r.resposta)
                    log(String(format: "B4 %@ R%d %@ %.1fs %@ [%@] → %@", modo, rodada, t.id, r.segundos, r.nota,
                               r.trilha.joined(separator: " "), String(r.resposta.prefix(140))))
                    rel.resultados.append(r)
                    Saida.gravar(arquivo, rel)   // a cada tarefa: queda não perde o que já rodou
                }
            }
        }
        _ = sorteio.proximo(1)
        for m in modos {
            let rs = rel.resultados.filter { $0.modo == m }
            log("B4 resumo \(m): \(rs.filter { $0.nota == "ok" }.count)/\(rs.count) ok automáticos")
        }
        log("B4 fim → \(arquivo)")
    }

    static func mascarar(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"[\w.+-]+@[\w-]+\.[\w.]+"#, with: "<email>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\+?\d[\d\s().-]{6,}(\d{4})"#, with: "***$1", options: .regularExpression)
        return t
    }
}

/// Sorteio reproduzível (a semente vai no relatório).
struct Sorteio {
    let semente: UInt64
    private var estado: UInt64
    init(semente: UInt64) { self.semente = semente; estado = semente }
    mutating func proximo(_ n: Int) -> Int {
        estado = estado &* 6364136223846793005 &+ 1442695040888963407
        return Int((estado >> 33) % UInt64(max(n, 1)))
    }
}

extension String { func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }
