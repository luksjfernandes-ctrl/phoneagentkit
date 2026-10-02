import Foundation

enum Saida {
    /// Grava em Documents (iOS: puxar com devicectl; macOS: ~/Library/Containers ou ~/Documents).
    static func gravar(_ nome: String, _ dado: some Encodable) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        guard let d = try? enc.encode(dado) else { return }
        var pasta = URL.documentsDirectory
        #if os(macOS)
        pasta = pasta.appending(path: "BateriaB")
        #endif
        try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
        try? d.write(to: pasta.appending(path: nome))
    }
}
