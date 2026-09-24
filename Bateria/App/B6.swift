import Foundation
import FoundationModels
import PhoneAgentKit

/// B6(a) · cota: 150 chamadas de 1 etapa em 45 min, app em primeiro plano, uma a cada 18 s.
/// Mede rateLimited, p50/p95 e chamadas acima de 60 s. Prompts fixos, fora das tarefas cegas.
enum B6 {
    static let prompts = [
        "Resuma em uma frase: o PhoneAgentKit conecta ferramentas MCP ao modelo local do iPhone, sem servidor próprio.",
        "Translate to English: a reunião foi remarcada para a próxima semana.",
        "Classifique o sentimento (positivo, neutro, negativo): o app travou de novo hoje cedo.",
        "Give three short title ideas for a note about weekly planning.",
        "Extraia a data desta frase: entregar o relatório até 3 de outubro.",
    ]

    struct Chamada: Codable { let n: Int; let inicio: Date; let segundos: Double; let erro: String?; let limitado: Bool }
    struct Relatorio: Codable {
        let aparelho: String, commit: String, inicio: Date
        var chamadas: [Chamada] = []
        var resumo = ""
    }

    static func rodar(total: Int = 150, intervalo: Double = 18, log: @escaping @Sendable (String) -> Void) async {
        let args = ProcessInfo.processInfo.arguments
        let commit = args.firstIndex(of: "--commit").map { args[$0 + 1] } ?? "?"
        let n = args.firstIndex(of: "--b6-total").flatMap { Int(args[$0 + 1]) } ?? total
        var rel = Relatorio(aparelho: ModelInfo.current().description, commit: commit, inicio: Date())
        let arquivo = "b6a-\(Int(rel.inicio.timeIntervalSince1970)).json"
        log("B6a \(rel.aparelho) \(n) chamadas, uma a cada \(intervalo)s")
        for i in 0..<n {
            let alvo = rel.inicio.addingTimeInterval(Double(i) * intervalo)
            let espera = alvo.timeIntervalSinceNow
            if espera > 0 { try? await Task.sleep(for: .seconds(espera)) }
            let t0 = Date()
            var erro: String?, limitado = false
            do { _ = try await LanguageModelSession().respond(to: prompts[i % prompts.count]) }
            catch let e as LanguageModelSession.GenerationError {
                if case .rateLimited = e { limitado = true }
                erro = String("\(e)".prefix(160))
            } catch { erro = String("\(error)".prefix(160)) }
            let c = Chamada(n: i + 1, inicio: t0, segundos: Date().timeIntervalSince(t0), erro: erro, limitado: limitado)
            rel.chamadas.append(c)
            log(String(format: "B6a %03d %.1fs %@", c.n, c.segundos, limitado ? "RATE-LIMITED" : (erro ?? "ok")))
            rel.resumo = resumo(rel.chamadas)
            Saida.gravar(arquivo, rel)
        }
        log("B6a fim: \(rel.resumo) → \(arquivo)")
    }

    static func resumo(_ cs: [Chamada]) -> String {
        let t = cs.map(\.segundos).sorted()
        func p(_ q: Double) -> Double { t.isEmpty ? 0 : t[min(t.count - 1, Int((q * Double(t.count)).rounded(.up)) - 1)] }
        let dur = (cs.last.map { $0.inicio.addingTimeInterval($0.segundos) } ?? Date()).timeIntervalSince(cs.first?.inicio ?? Date())
        return String(format: "%d chamadas em %.1f min · rateLimited=%d · outros erros=%d · p50=%.2fs p95=%.2fs max=%.1fs · >60s=%d",
                      cs.count, dur / 60, cs.filter(\.limitado).count, cs.filter { $0.erro != nil && !$0.limitado }.count,
                      p(0.5), p(0.95), t.last ?? 0, cs.filter { $0.segundos > 60 }.count)
    }
}
