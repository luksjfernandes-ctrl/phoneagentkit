import Foundation
import FoundationModels

/// O que o sistema entregou neste aparelho: disponibilidade, variante e janela de contexto.
/// O app não escolhe a variante; num iPhone não-Pro medimos 4.096 tokens, num Mac M4, 8.192.
public struct ModelInfo: Sendable, CustomStringConvertible {
    public let isAvailable: Bool
    public let availability: String
    public let variant: String
    public let contextSize: Int

    public static func current(_ model: SystemLanguageModel = .default) -> ModelInfo {
        ModelInfo(isAvailable: model.isAvailable, availability: "\(model.availability)",
                  variant: model.isAvailable ? variantName(model) : "-",
                  contextSize: model.isAvailable ? model.contextSize : 0)
    }

    /// A variante só é exposta a partir do iOS/macOS 27.
    static func variantName(_ model: SystemLanguageModel) -> String {
        if #available(iOS 27.0, macOS 27.0, *) { return model.variant.displayName }
        return "unknown (needs iOS 27)"
    }

    public var description: String { "available=\(isAvailable) variant=\(variant) context=\(contextSize) (\(availability))" }

    /// Quantos tokens sobram depois de reservar o espaço das ferramentas e da resposta.
    public func remaining(afterTools tools: Int, reservingForAnswer answer: Int = 600) -> Int {
        max(0, contextSize - tools - answer)
    }
}
