import Foundation

/// Data relativa resolvida pelo CÓDIGO, não pelo modelo: "sexta às 10h" = próxima sexta às 10h que ainda
/// não passou. Medido na Bateria B v2: o 3B, com um calendário no prompt, converteu "sexta às 10h" em
/// hoje às 10h (já passado) em 3 de 3.
public enum RelativeDate {
    static let dias: [(Int, [String])] = [   // weekday do Calendar (1 = domingo)
        (1, ["domingo", "sunday"]), (2, ["segunda", "segunda-feira", "monday"]), (3, ["terca", "terca-feira", "tuesday"]),
        (4, ["quarta", "quarta-feira", "wednesday"]), (5, ["quinta", "quinta-feira", "thursday"]),
        (6, ["sexta", "sexta-feira", "friday"]), (7, ["sabado", "saturday"]),
    ]

    static let meses: [(Int, [String])] = [
        (1, ["janeiro", "jan", "january"]), (2, ["fevereiro", "fev", "february", "feb"]), (3, ["marco", "mar", "march"]),
        (4, ["abril", "abr", "april", "apr"]), (5, ["maio", "mai", "may"]), (6, ["junho", "jun", "june"]),
        (7, ["julho", "jul", "july"]), (8, ["agosto", "ago", "august", "aug"]), (9, ["setembro", "set", "september", "sep", "sept"]),
        (10, ["outubro", "out", "october", "oct"]), (11, ["novembro", "nov", "november"]), (12, ["dezembro", "dez", "december", "dec"]),
    ]
    /// Pistas de data que este resolvedor não entende: com elas, nil (e o chamador não inventa hoje/amanhã).
    static let naoEntendo = #"\b(mes|meses|month|months|ano que vem|proximo ano|next year|fim de|end of|feriado|holiday|vespera|eve)\b"#
    /// "semana que vem", "próxima semana", "next week": pedem um dia da semana junto (sem ele, nil).
    static let semanaQueVem = #"\b(semana que vem|proxima semana|next week)\b"#

    static func grupos(_ s: String, _ padrao: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: padrao),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } ?? "" }
    }

    /// Hora e minuto da frase: "10h", "10h30", "10:30", "às 10", "3pm", "at 10".
    public static func time(_ frase: String) -> (Int, Int)? {
        let s = frase.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        func ok(_ h: Int, _ m: Int) -> (Int, Int)? { (0...23).contains(h) && (0...59).contains(m) ? (h, m) : nil }
        if let g = grupos(s, #"(?<![\d/:])(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#), var h = Int(g[1]) {
            if g[3] == "pm" && h < 12 { h += 12 }; if g[3] == "am" && h == 12 { h = 0 }
            return ok(h, Int(g[2]) ?? 0)
        }
        // "3 da tarde", "8 da noite": soma 12
        func tarde(_ h: Int) -> Int { h < 12 && tem(s, #"\bda (tarde|noite)\b"#) ? h + 12 : h }
        if let g = grupos(s, #"(?<![\d/])(\d{1,2}):(\d{2})(?![\d/])"#), let h = Int(g[1]), let m = Int(g[2]) { return ok(tarde(h), m) }
        if let g = grupos(s, #"(?<![\d/])(\d{1,2})\s*h(?:oras?)?(?:\s*(\d{2}))?\b"#), let h = Int(g[1]) { return ok(tarde(h), Int(g[2]) ?? 0) }
        // "às 10" / "at 10". Sem acento, "as 3 propostas" é artigo: só vale se não vier palavra depois (ou "da tarde")
        let l = frase.lowercased()
        if let g = grupos(l, #"(?:(?<![\p{L}])às|\bat)\s+(\d{1,2})(?![\d/:])"#) ?? grupos(s, #"\bas\s+(\d{1,2})(?![\d/:])(?!\s*[a-z]{3,})"#),
           let h = Int(g[1]) { return ok(tarde(h), 0) }
        return nil
    }

    /// Resolve a frase em data e hora futuras, ou nil se a frase não tiver dia e hora reconhecíveis.
    /// Convenções (congeladas na Bateria B v3):
    /// - dia da semana, "próxima sexta", "next Friday": a próxima ocorrência cuja hora ainda não passou (hoje conta);
    /// - dia da semana + "da semana que vem"/"da próxima semana"/"next week": esse dia na semana (segunda a domingo)
    ///   seguinte à atual; "semana que vem" sem dia da semana: nil;
    /// - "daqui a N dias", "em N dias", "in N days": hoje + N; "dia N": o próximo dia N do mês que ainda não passou;
    /// - "dd/MM" e "14 de outubro": este ano, ou o próximo se já passou; "hoje"/"amanhã"/"depois de amanhã";
    /// - só a hora: hoje se ainda não passou, senão amanhã;
    /// - mês que vem, fim de semana, feriado, véspera: nil (o chamador não inventa).
    /// "hoje às 8h" quando já são 10h devolve o horário passado: quem chama rejeita (não há futuro para "hoje").
    public static func resolve(_ frase: String, now: Date, calendar: Calendar) -> Date? {
        guard let (h, m) = time(frase) else { return nil }
        let s = frase.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        let hoje = calendar.startOfDay(for: now)
        func em(_ dia: Date) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: dia)! }
        func mais(_ n: Int, _ d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }

        if tem(s, naoEntendo) { return nil }
        if let g = grupos(s, #"\b(?:daqui a|em|in)\s+(\d{1,2})\s+(?:dias?|days?)\b"#), let n = Int(g[1]) { return em(mais(n, hoje)) }
        if s.contains("depois de amanha") || s.contains("day after tomorrow") { return em(mais(2, hoje)) }
        if tem(s, #"\b(amanha|tomorrow)\b"#) { return em(mais(1, hoje)) }
        if tem(s, #"\b(hoje|today|tonight)\b"#) { return em(hoje) }
        if let g = grupos(s, #"(?<!\d)(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?(?![\d])"#), let d = Int(g[1]), let mes = Int(g[2]) {
            var c = calendar.dateComponents([.year], from: now)
            if let a = Int(g[3]) { c.year = a < 100 ? 2000 + a : a }
            c.month = mes; c.day = d; c.hour = h; c.minute = m
            guard var alvo = calendar.date(from: c), calendar.component(.day, from: alvo) == d else { return nil }
            if g[3].isEmpty && alvo <= now { c.year! += 1; alvo = calendar.date(from: c)! }
            return alvo
        }
        // "14 de outubro", "14 outubro", "October 14", "Oct 14th"
        let nomesMes = meses.flatMap { $0.1 }.sorted { $0.count > $1.count }.joined(separator: "|")
        let porExtenso = grupos(s, #"(?<!\d)(\d{1,2})\s*(?:de\s+)?("# + nomesMes + #")\b"#).map { ($0[1], $0[2]) }
            ?? grupos(s, #"\b("# + nomesMes + #")\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?!\d)"#).map { ($0[2], $0[1]) }
        if let (dt, nm) = porExtenso, let d = Int(dt), let mes = meses.first(where: { $0.1.contains(nm) })?.0 {
            var c = calendar.dateComponents([.year], from: now)
            c.month = mes; c.day = d; c.hour = h; c.minute = m
            guard var alvo = calendar.date(from: c), calendar.component(.day, from: alvo) == d else { return nil }
            if alvo <= now { c.year! += 1; alvo = calendar.date(from: c)! }
            return alvo
        }
        let proximaSemana = tem(s, semanaQueVem)
        for (wd, nomes) in dias where nomes.contains(where: { tem(s, #"(?<![\p{L}])"# + $0 + #"(?![\p{L}])"#) }) {
            if proximaSemana {
                // segunda da semana atual (segunda a domingo) + 7, depois o dia pedido
                let atual = (calendar.component(.weekday, from: hoje) + 5) % 7   // 0 = segunda
                let segundaQueVem = mais(7 - atual, hoje)
                return em(mais((wd + 5) % 7, segundaQueVem))
            }
            for i in 0...7 {
                let d = mais(i, hoje)
                if calendar.component(.weekday, from: d) == wd && em(d) > now { return em(d) }
            }
        }
        if proximaSemana { return nil }
        if let g = grupos(s, #"\bdia\s+(\d{1,2})(?![\d/])"#), let d = Int(g[1]), (1...31).contains(d) {
            // o próximo dia d que existe no mês e ainda não passou
            for k in 0...12 {
                guard let mes = calendar.date(byAdding: .month, value: k, to: hoje) else { continue }
                var c = calendar.dateComponents([.year, .month], from: mes)
                c.day = d; c.hour = h; c.minute = m
                if let alvo = calendar.date(from: c), calendar.component(.day, from: alvo) == d, alvo > now { return alvo }
            }
            return nil
        }
        let hojeNaHora = em(hoje)
        return hojeNaHora > now ? hojeNaHora : em(mais(1, hoje))
    }

    static func tem(_ s: String, _ p: String) -> Bool { s.range(of: p, options: .regularExpression) != nil }
}
