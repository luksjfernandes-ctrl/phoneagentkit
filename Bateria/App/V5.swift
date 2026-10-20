import Foundation
import MCP

/// Bateria B · agente v5: entrada explícita da rodada nova. O motor é o de `V3.swift` com as correções da v5.
/// Nenhuma tarefa cega é embutida aqui.
enum V5 {
    static func rodar(blocos: [String], rodadas: Int = 3, log: @escaping @Sendable (String) -> Void) async {
        await V3.rodar(blocos: blocos, rodadas: rodadas, log: log)
    }

    /// Issue #3, conferência ao vivo: lista as issues abertas de um repositório público e grava só número e título.
    static func listaGithub(_ repo: String, max: Int, log: @escaping @Sendable (String) -> Void) async {
        do {
            let cli = try await Conectores.conectar("composio", log: log)
            let itens = try await V2.githubIssues(cli, repo: repo, max: max)
            Saida.gravar("lista-github.json", itens.map { ["n": "\($0.n)", "titulo": $0.titulo] })
            log("lista github \(repo): \(itens.count) issues, \(Set(itens.map(\.n)).count) distintas")
            await cli.disconnect()
        } catch { log("lista github falhou: \(error)") }
    }
}
