import Foundation

/// Bateria B · agente v4.
///
/// A implementação permanece no módulo de medição para preservar o corretor e o
/// formato de dados da v3, mas esta é a entrada explícita usada pelo app na nova
/// rodada. Nenhuma tarefa cega é embutida aqui.
enum V4 {
    static func rodar(blocos: [String], rodadas: Int = 3, log: @escaping @Sendable (String) -> Void) async {
        await V3.rodar(blocos: blocos, rodadas: rodadas, log: log)
    }
}
