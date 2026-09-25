import AuthenticationServices
import Foundation
import MCP
import PhoneAgentKit
#if os(iOS)
import UIKit
#endif

/// Conectores de terceiros (B1, B3, B5): login OAuth nativo com o esquema do app e token no Keychain.
/// Os endereços ficam em `conectores.json` (Documents, fora do git), para trocar sem recompilar:
///   [{"nome": "asana", "servidor": "https://mcp.asana.com/..."}]
enum Conectores {
    struct Conector: Codable { let nome: String; let servidor: String }
    static let esquema = "bateriab"
    static let chaveiro = TokenStore(service: "br.com.letoapp.bateriab")

    static func pasta() -> URL {
        #if os(macOS)
        return URL.documentsDirectory.appending(path: "BateriaB")
        #else
        return URL.documentsDirectory
        #endif
    }

    static func lista() -> [Conector] {
        guard let d = try? Data(contentsOf: pasta().appending(path: "conectores.json")),
              let cs = try? JSONDecoder().decode([Conector].self, from: d) else { return [] }
        return cs
    }

    /// Conecta com o token guardado; sem token, abre o login (a senha é digitada pelo usuário).
    static func conectar(_ nome: String, log: @Sendable (String) -> Void) async throws -> Client {
        guard let c = lista().first(where: { $0.nome == nome }), let url = URL(string: c.servidor) else {
            throw NSError(domain: "Bateria", code: 1, userInfo: [NSLocalizedDescriptionKey: "conector \(nome) ausente em conectores.json"])
        }
        if let t = chaveiro.load(account: nome), let cli = try? await MCPConnection.connect(to: url, token: t, clientName: "Bateria B"),
           (try? await cli.listTools()) != nil {
            log("\(nome): conectado com token guardado"); return cli
        }
        // servidor público (sem OAuth): conecta direto; só pede login se o servidor exigir
        if let cli = try? await MCPConnection.connect(to: url, clientName: "Bateria B"), (try? await cli.listTools()) != nil {
            log("\(nome): servidor sem autenticação"); return cli
        }
        log("\(nome): abrindo login OAuth (registro dinâmico + PKCE, retorno \(esquema)://)")
        let oauth = NativeOAuth(redirectURI: URL(string: "\(esquema)://oauth/callback")!, clientName: "Bateria B")
        let token = try await oauth.authorize(server: url, presenter: LoginWeb())
        chaveiro.save(token, account: nome)
        log("\(nome): login feito, token no Keychain")
        return try await MCPConnection.connect(to: url, token: token, clientName: "Bateria B")
    }

    /// Descoberta: grava nome, descrição e esquema de cada ferramenta (sem dados do usuário).
    /// É daqui que sai o adaptador das tarefas do B1 (quais ferramentas o CÓDIGO chama para buscar e para o gabarito).
    static func descobrir(_ nome: String, log: @escaping @Sendable (String) -> Void) async {
        do {
            let cli = try await conectar(nome, log: log)
            let tools = try await cli.listTools().tools
            struct F: Encodable { let nome: String; let descricao: String; let esquema: Value }
            Saida.gravar("ferramentas-\(nome).json", tools.map { F(nome: $0.name, descricao: $0.description ?? "", esquema: $0.inputSchema) })
            log("\(nome): \(tools.count) ferramentas → ferramentas-\(nome).json")
            await cli.disconnect()
        } catch { log("\(nome): falhou: \(error)") }
    }
}

final class LoginWeb: NSObject, OAuthAuthorizationDelegate, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private var sessao: ASWebAuthenticationSession?

    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                let s = ASWebAuthenticationSession(url: url, callback: .customScheme(Conectores.esquema)) { retorno, erro in
                    if let retorno { cont.resume(returning: retorno) } else { cont.resume(throwing: erro ?? URLError(.userCancelledAuthentication)) }
                }
                s.presentationContextProvider = self
                self.sessao = s
                s.start()
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        #else
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #endif
    }
}
