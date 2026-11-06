import Foundation
import Testing
@testable import PhoneAgentKit

/// Regressões de texto com acento e letras cuja minúscula muda de tamanho.
@Suite struct TextoUnicodeTests {
    /// `trimMeta` achava o marcador na versão minúscula e cortava a original com aquele índice.
    /// "İ" vira "i̇" (3 bytes em vez de 2) e o "K" de kelvin vira "k" (1 byte em vez de 3): o corte saía deslocado.
    @Test func trimMetaCortaNoLugarCertoComMinusculaDeOutroTamanho() {
        #expect(PinnedSource.trimMeta("İstanbul office. What is missing: the date") == "İstanbul office.")
        #expect(PinnedSource.trimMeta("Temp 5 \u{212A}. What is missing: the date") == "Temp 5 \u{212A}.")
        #expect(PinnedSource.trimMeta("Fica em São Paulo. O que falta: a data") == "Fica em São Paulo.")
    }

    /// A pergunta perdia o acento em `keywords`, mas título e corpo não: "instalação" nunca casava com "Instalação".
    @Test func menuCasaPalavraComAcento() {
        let s = [MarkdownSection(title: "Uso", body: ""), MarkdownSection(title: "Instalação", body: "")]
        #expect(MarkdownSections.uniqueTitleMatch(s, for: "como faço a instalação?") == 1)
        #expect(MarkdownSections.rank(s, for: "como faço a instalação?", limit: 1).map(\.title) == ["Instalação"])
        let corpo = [MarkdownSection(title: "A", body: "nada aqui"), MarkdownSection(title: "B", body: "configuração e configuração")]
        #expect(MarkdownSections.rank(corpo, for: "qual a configuração?", limit: 1).map(\.title) == ["B"])
    }
}
