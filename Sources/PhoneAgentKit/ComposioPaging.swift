import Foundation

/// Pagina no código um resultado grande do Composio (issue #3).
///
/// Acima de um certo tamanho, o Composio devolve só um `data_preview` cortado e guarda o resto no workbench remoto,
/// que o kit bloqueia de propósito. O caminho é pedir páginas pequenas e unir no código. Se mesmo assim uma página
/// vier cortada, a mesma página é pedida de novo com metade do tamanho, até 1.
public enum ComposioPaging {
    public struct Page<Item: Sendable>: Sendable {
        public let items: [Item]
        /// Próximo cursor (token do Gmail) ou nil quando acabou. Para APIs por número de página, use `hasMore`.
        public let next: String?
        public let hasMore: Bool
        /// A resposta veio como `data_preview` (cortada): esta página precisa ser pedida menor.
        public let truncated: Bool
        /// Itens crus que a página consumiu, antes de qualquer filtro (a lista de issues do GitHub vem com PRs).
        /// nil = `items.count`.
        public let consumed: Int?

        public init(items: [Item], next: String? = nil, hasMore: Bool, truncated: Bool = false, consumed: Int? = nil) {
            self.items = items; self.next = next; self.hasMore = hasMore; self.truncated = truncated; self.consumed = consumed
        }
    }

    public struct Request: Equatable, Sendable {
        public let page: Int        // 1, 2, 3… (para APIs por número de página)
        public let cursor: String?  // para APIs por cursor
        public let pageSize: Int
    }

    public enum Failure: Error, Equatable { case truncatedAtSizeOne(page: Int) }

    /// O texto cru do Composio indica corte?
    public static func isTruncated(_ raw: String) -> Bool { raw.contains("\"data_preview\"") }

    /// Junta as páginas até `maxItems` ou até acabar. Com página por número, o tamanho que funcionou continua
    /// valendo nas próximas, e o deslocamento é recalculado pelos itens já recebidos.
    public static func collect<Item: Sendable>(pageSize: Int, maxItems: Int,
                                               fetch: (Request) async throws -> Page<Item>) async throws -> [Item] {
        var itens: [Item] = [], tamanho = max(1, pageSize), cursor: String? = nil, deslocamento = 0
        while itens.count < maxItems {
            // por número de página, a próxima página com o tamanho atual começa logo depois do que já foi consumido
            if cursor == nil, deslocamento % tamanho != 0 { tamanho = 1 }
            let pagina = cursor == nil ? deslocamento / tamanho + 1 : 0
            let p = try await fetch(Request(page: pagina, cursor: cursor, pageSize: tamanho))
            if p.truncated {
                guard tamanho > 1 else { throw Failure.truncatedAtSizeOne(page: pagina) }
                tamanho = max(1, tamanho / 2)
                continue
            }
            let consumidos = p.consumed ?? p.items.count
            itens += p.items
            deslocamento += consumidos
            guard p.hasMore, consumidos > 0 else { break }
            cursor = p.next
        }
        return Array(itens.prefix(maxItems))
    }
}
