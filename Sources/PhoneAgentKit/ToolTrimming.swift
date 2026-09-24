import Foundation
import FoundationModels
import MCP

/// Como enxugar ferramentas MCP para caberem na janela do modelo local.
/// Medido: 45 ferramentas cruas de um conector popular = 14.221 tokens; a janela do iPhone não-Pro é 4.096.
public struct ToolTrimming: Sendable {
    public var descriptionLimit: Int
    public var requiredOnly: Bool
    public var outputLimit: Int

    public init(descriptionLimit: Int = 300, requiredOnly: Bool = false, outputLimit: Int = 1500) {
        self.descriptionLimit = descriptionLimit; self.requiredOnly = requiredOnly; self.outputLimit = outputLimit
    }

    /// Corta a descrição no limite, preferindo terminar numa frase.
    public func description(_ s: String) -> String {
        guard s.count > descriptionLimit else { return s }
        let cut = String(s.prefix(descriptionLimit))
        if let dot = cut.lastIndex(of: "."), cut.distance(from: cut.startIndex, to: dot) > descriptionLimit / 2 {
            return String(cut[...dot])
        }
        return cut
    }
}

/// Escolhe o subconjunto de ferramentas que cabe num orçamento de tokens.
public enum ToolBudget {
    /// Guloso, na ordem de `preferred` (depois o resto): entra quem couber. `cost` mede uma ferramenta.
    public static func fit<T>(_ tools: [T], name: (T) -> String, preferred: [String] = [], budget: Int,
                              cost: (T) async throws -> Int) async rethrows -> (kept: [T], used: Int) {
        let rank = Dictionary(uniqueKeysWithValues: preferred.enumerated().map { ($1, $0) })
        let ordered = tools.enumerated().sorted {
            (rank[name($0.element)] ?? preferred.count + $0.offset) < (rank[name($1.element)] ?? preferred.count + $1.offset)
        }.map(\.element)
        var kept: [T] = [], used = 0
        for t in ordered {
            let c = try await cost(t)
            if used + c <= budget { kept.append(t); used += c }
        }
        return (kept, used)
    }

    /// Converte ferramentas MCP, enxuga e mantém só as que cabem no orçamento, medindo com o próprio modelo.
    public static func fit(_ tools: [MCP.Tool], client: Client, trimming: ToolTrimming = .init(),
                           preferred: [String] = [], budget: Int,
                           model: SystemLanguageModel = .default) async throws -> (kept: [MCPTool], used: Int) {
        let converted = tools.compactMap { try? MCPTool($0, client: client, trimming: trimming) }
        return try await fit(converted, name: \.name, preferred: preferred, budget: budget) {
            try await model.tokenCount(for: [$0] as [any FoundationModels.Tool])
        }
    }
}
