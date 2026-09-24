import PhoneAgentKit
import SwiftUI

@main
struct HelloAgentApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @State private var lines: [String] = []
    @State private var question = "In the repository modelcontextprotocol/swift-sdk, which client transports are supported?"
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section { TextField("Question", text: $question, axis: .vertical) }
                Section {
                    Button(running ? "Running…" : "Ask") {
                        running = true; lines = []
                        Task {
                            await HelloAgent.run(question: question) { line in Task { @MainActor in lines.append(line) } }
                            running = false
                        }
                    }.disabled(running)
                }
                Section("Log") { ForEach(Array(lines.enumerated()), id: \.offset) { Text($0.element).font(.caption.monospaced()) } }
            }
            .navigationTitle("Hello agent")
        }
    }
}
