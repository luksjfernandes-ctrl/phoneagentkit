import Foundation

/// Regras determinísticas introduzidas no agente v4.
/// Estas funções não consultam serviços nem dados pessoais; por isso são regressões
/// unit-testáveis antes de qualquer bateria cega.
public enum V4Safety {
    public struct PastDateDecision: Equatable, Sendable {
        public let date: Date
        public let warning: String?
        public let requiresConfirmation: Bool

        public init(date: Date, warning: String?, requiresConfirmation: Bool) {
            self.date = date
            self.warning = warning
            self.requiresConfirmation = requiresConfirmation
        }
    }

    /// Uma data passada não é descartada silenciosamente: a ação só pode prosseguir
    /// depois de uma confirmação explícita que mostre o aviso ao usuário.
    public static func dateDecision(_ date: Date, now: Date) -> PastDateDecision {
        guard date <= now else { return PastDateDecision(date: date, warning: nil, requiresConfirmation: true) }
        let f = ISO8601DateFormatter()
        return PastDateDecision(date: date,
                                warning: "O horário pedido já passou (\(f.string(from: date))). Confirma mesmo assim?",
                                requiresConfirmation: true)
    }

    /// Resolve o item de origem em texto real. O identificador nunca é usado como
    /// conteúdo: ele apenas seleciona a leitura que o código já fez.
    public static func sourceText(for origin: String, sources: [String: String]) -> String? {
        let key = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let text = sources[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// Maior sequência de tokens consecutivos do tópico que aparece na fonte.
    /// Pontuação, caixa e acentos não criam uma diferença artificial.
    public static func copiedRun(topic: String, source: String) -> Int {
        let t = tokens(topic), s = tokens(source)
        guard t.count >= 8, s.count >= 8 else { return 0 }
        var best = 0
        for start in t.indices {
            var run = 0
            while start + run < t.count, let p = s.firstIndex(of: t[start + run]) {
                // A busca acima é apenas um atalho; a sequência é confirmada em
                // todas as posições abaixo, evitando confundir tokens repetidos.
                if s.count - p < t.count - start { break }
                let end = min(t.count - start, s.count - p)
                var n = 0
                while n < end, t[start + n] == s[p + n] { n += 1 }
                run = max(run, n)
                if run >= 8 { return run }
                break
            }
            best = max(best, run)
        }
        // O algoritmo acima cobre a primeira ocorrência de cada token; este
        // segundo laço torna a garantia explícita para fontes com repetições.
        if best < 8 {
            for i in 0..<(t.count - 7) {
                for j in 0..<(s.count - 7) {
                    var n = 0
                    while i + n < t.count, j + n < s.count, t[i + n] == s[j + n] { n += 1 }
                    best = max(best, n)
                    if best >= 8 { return best }
                }
            }
        }
        return best
    }

    public static func rejectsCopy(topic: String, source: String, minimum: Int = 8) -> Bool {
        copiedRun(topic: topic, source: source) >= minimum
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
