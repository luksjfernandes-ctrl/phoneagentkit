import Foundation

/// Regras determinísticas do agente v5, testáveis sem o modelo.
public enum V5Safety {
    /// Teto da referência no título de uma ação.
    public static let referenceLimit = 60

    /// Título de uma ação: o texto que o usuário digitou + uma referência curta ao item lido ("issue #28250",
    /// o assunto de um e-mail, o título de uma página). Nunca o conteúdo lido.
    ///
    /// Bateria v4, A3: o título levava o texto inteiro da página de origem, e a cobrança plantada na página foi
    /// parar no lembrete. Aqui a referência passa pelo filtro e pela guarda; se cair em qualquer um, sai do título.
    public static func actionTitle(userText: String, reference: String) -> String {
        let usuario = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = reference.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ref.isEmpty, UntrustedText.motivo(ref) == nil,
              UntrustedText.guardOutput(ref, request: usuario).cut.isEmpty else { return usuario }
        return "\(usuario) — \(UntrustedText.cap(ref, referenceLimit))"
    }
}

/// Casa o remetente que a pessoa falou ("o Pedro da Apollo", "Metricool") com um endereço que o código já buscou.
/// Issue #1: o modelo extrai o nome de exibição e a busca do Gmail precisa do endereço.
public enum SenderMatch {
    /// `senders`: o campo `From` cru ("Nome <endereco@dominio>"). Devolve o endereço quando há exatamente um
    /// candidato; com zero ou mais de um, devolve nil e quem chama mantém a busca antiga.
    public static func resolve(_ spoken: String, senders: [String]) -> String? {
        let falado = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !falado.isEmpty else { return nil }
        if falado.contains("@") { return falado.lowercased() }
        let alvo = tokens(falado)
        guard !alvo.isEmpty else { return nil }
        var porEndereco: [String: Set<String>] = [:]   // endereço → tokens do nome e do endereço
        for s in senders {
            let e = address(s)
            guard !e.isEmpty else { continue }
            porEndereco[e, default: []].formUnion(tokens(displayName(s)))
            porEndereco[e, default: []].formUnion(tokens(e.replacingOccurrences(of: "@", with: " ")))
        }
        // 1º: nome de exibição idêntico (sem acento e sem caixa)
        let exato = Set(senders.filter { tokens(displayName($0)) == alvo && !address($0).isEmpty }.map(address))
        if exato.count == 1 { return exato.first }
        // 2º: todas as palavras faladas aparecem no nome ou no endereço
        let todos = porEndereco.filter { alvo.allSatisfy($0.value.contains) }.map(\.key)
        return todos.count == 1 ? todos[0] : nil
    }

    public static func address(_ from: String) -> String {
        if let a = from.range(of: "<"), let b = from.range(of: ">", range: a.upperBound..<from.endIndex) {
            return String(from[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
        }
        let t = from.trimmingCharacters(in: .whitespaces)
        return t.contains("@") ? t.lowercased() : ""
    }

    public static func displayName(_ from: String) -> String {
        guard let a = from.range(of: "<") else { return from.contains("@") ? "" : from }
        return from[..<a.lowerBound].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
    }

    /// Palavras sem acento, sem caixa e sem as de ligação ("o Pedro da Apollo" → pedro, apollo).
    static func tokens(_ s: String) -> Set<String> {
        let ligacao: Set<String> = ["o", "a", "os", "as", "de", "da", "do", "das", "dos", "e", "the", "from", "of"]
        return Set(s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !ligacao.contains($0) })
    }
}
