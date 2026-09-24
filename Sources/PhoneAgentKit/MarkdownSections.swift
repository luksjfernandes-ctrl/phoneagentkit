import Foundation

/// Corta um documento Markdown em seções por um prefixo de título ("# Page: ", "## ").
/// Serve para montar menus numerados: o modelo escolhe a seção e só ela entra no contexto.
public struct MarkdownSection: Sendable, Equatable {
    public let title: String
    public let body: String
}

public enum MarkdownSections {
    public static func split(_ text: String, prefix: String) -> [MarkdownSection] {
        var out: [MarkdownSection] = []
        var title: String?
        var lines: [Substring] = []
        func flush() {
            if let title { out.append(.init(title: title, body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))) }
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) {
                flush()
                title = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                lines = []
            } else {
                lines.append(line)
            }
        }
        flush()
        return out
    }
}

extension MarkdownSections {
    /// O código encurta o menu antes do modelo: ordena as seções pelas palavras da pergunta
    /// (título pesa mais que corpo) e devolve só as `limit` primeiras. Num modelo de 3B, um menu de 40+
    /// títulos erra; um de poucos acerta.
    /// Palavras da pergunta que contam (mais de 3 letras, sem acento).
    public static func keywords(_ question: String) -> Set<String> {
        Set(question.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 3 })
    }

    /// Se exatamente um título contém uma palavra da pergunta, o código decide sem perguntar ao modelo.
    public static func uniqueTitleMatch(_ sections: [MarkdownSection], for question: String) -> Int? {
        let words = keywords(question)
        let hits = sections.indices.filter { i in words.contains { sections[i].title.lowercased().contains($0) } }
        return hits.count == 1 ? hits[0] : nil
    }

    public static func rank(_ sections: [MarkdownSection], for question: String, limit: Int = 6) -> [MarkdownSection] {
        let words = keywords(question)
        guard !words.isEmpty else { return Array(sections.prefix(limit)) }
        func score(_ s: MarkdownSection) -> Int {
            let t = s.title.lowercased(), b = s.body.lowercased()
            return words.reduce(0) { $0 + (t.contains($1) ? 10 : 0) + min(b.components(separatedBy: $1).count - 1, 5) }
        }
        return sections.enumerated().sorted { (score($0.element), -$0.offset) > (score($1.element), -$1.offset) }
            .prefix(limit).map(\.element)
    }
}
