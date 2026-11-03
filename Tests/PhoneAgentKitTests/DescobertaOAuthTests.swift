import Foundation
import Testing
@testable import PhoneAgentKit

/// Regressão da descoberta OAuth: a raiz do servidor perdia a porta.
/// Com `https://mcp.example.com:8443/mcp`, os metadados eram buscados em `https://mcp.example.com/.well-known/…`,
/// outro serviço, e o `resource` enviado ao login apontava para ele.
@Suite struct DescobertaOAuthTests {
    @Test func raizDaDescobertaMantemAPorta() {
        #expect(NativeOAuth.discoveryRoot(for: URL(string: "http://localhost:8080/mcp")!).absoluteString == "http://localhost:8080")
        #expect(NativeOAuth.discoveryRoot(for: URL(string: "https://mcp.example.com:8443/mcp?x=1#f")!).absoluteString == "https://mcp.example.com:8443")
        #expect(NativeOAuth.discoveryRoot(for: URL(string: "http://localhost:8080/mcp")!)
            .appending(path: ".well-known/oauth-protected-resource").absoluteString == "http://localhost:8080/.well-known/oauth-protected-resource")
        // sem porta, igual a antes
        #expect(NativeOAuth.discoveryRoot(for: URL(string: "https://mcp.example.com/mcp")!).absoluteString == "https://mcp.example.com")
    }
}
