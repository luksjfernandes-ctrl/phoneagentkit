import Foundation
import PhoneAgentKit
import SwiftUI

@main
struct HelloAgentApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var lines: [String] = []
    @State private var question = "What is the stdio transport?"
    @State private var repository = "modelcontextprotocol/modelcontextprotocol"
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Question", text: $question, axis: .vertical)
                    TextField("Repository (owner/repo)", text: $repository)
                }
                Section {
                    Button(running ? "Running…" : "Ask") {
                        Task { await ask() }
                    }.disabled(running)
                }
                Section("Log") { ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) } }
            }
            .navigationTitle("Hello agent")
        }
        // `--autorun` responde sem toque: permite verificar o motor no aparelho pelo console
        .task { if ProcessInfo.processInfo.arguments.contains("--autorun") { await ask() } }
    }

    /// Mesmo caminho do App Intent: fonte marcada, só o modelo local responde.
    func ask() async {
        running = true; lines = []
        let add: @Sendable (String) -> Void = { line in print("HELLO " + line); Task { @MainActor in lines.append(line) } }
        let t0 = Date()
        do {
            let answer = try await HelloAgent.askPinned(question, repository: repository, log: add)
            add(String(format: "answer (%.1fs): %@", Date().timeIntervalSince(t0), answer))
        } catch { add("error: \(error)") }
        running = false
    }
}
