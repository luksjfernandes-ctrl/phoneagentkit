import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

@main
struct BateriaApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var lines: [String] = []
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Permissões") { Task { await run { log in _ = await Permissoes.pedir(log: log) } } }
                    Button("B4 · nativo (3 rodadas)") { Task { await run { await B4.rodar(log: $0) } } }
                    Button("B6(a) · 150 chamadas em 45 min") { Task { await run { await B6.rodar(log: $0) } } }
                    ForEach(Conectores.lista().map(\.nome), id: \.self) { n in
                        Button("Login + descoberta: \(n)") { Task { await run { await Conectores.descobrir(n, log: $0) } } }
                    }
                    Button("B5 · injeção (3 rodadas)") { Task { await run { await B5.rodar(log: $0) } } }
                }.disabled(running)
                Section("Log") { ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) } }
            }
            .navigationTitle("Bateria B")
        }
        // `--b4`, `--b6` e `--perm` rodam sem toque (conferência pelo console)
        .task {
            let a = ProcessInfo.processInfo.arguments
            if a.contains("--perm") { await run { log in _ = await Permissoes.pedir(log: log) } }
            if a.contains("--b4") { await run { await B4.rodar(log: $0) } }
            if a.contains("--b6") { await run { await B6.rodar(log: $0) } }
            if let i = a.firstIndex(of: "--descobrir"), i + 1 < a.count { let n = a[i + 1]; await run { await Conectores.descobrir(n, log: $0) } }
            if a.contains("--b5") { await run { await B5.rodar(log: $0) } }
        }
    }

    func run(_ body: (@escaping @Sendable (String) -> Void) async -> Void) async {
        running = true
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true   // tela apagada = app em segundo plano = falso bloqueio
        #endif
        let add: @Sendable (String) -> Void = { line in print("BAT " + line); Task { @MainActor in lines.append(line) } }
        await body(add)
        running = false
    }
}

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
