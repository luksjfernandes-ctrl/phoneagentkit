import CryptoKit
import Foundation
import MCP

public struct OAuthToken: Sendable, Equatable {
    public let accessToken: String
    public let expiresIn: Int?
    public init(accessToken: String, expiresIn: Int?) { self.accessToken = accessToken; self.expiresIn = expiresIn }
}

public enum NativeOAuthError: Error, Equatable {
    case discoveryFailed, registrationFailed, stateMismatch
    case missingCode(String)
    case tokenRejected(String)
}

/// OAuth 2.1 para app nativo (RFC 8252): descoberta, registro dinâmico (RFC 7591), PKCE S256 e retorno
/// pelo esquema próprio do app. O SDK oficial do MCP só aceita retorno https/loopback, o que não serve no iOS;
/// por isso o fluxo é feito aqui e o token entra no transporte como cabeçalho (ver `MCPConnection`).
public struct NativeOAuth: Sendable {
    /// Ex.: URL(string: "myapp://oauth/callback")! — o esquema precisa estar no Info.plist do app.
    public let redirectURI: URL
    public let clientName: String
    public let scope: String?

    public init(redirectURI: URL, clientName: String, scope: String? = nil) {
        self.redirectURI = redirectURI; self.clientName = clientName; self.scope = scope
    }

    public func authorize(server: URL, presenter: any OAuthAuthorizationDelegate) async throws -> OAuthToken {
        // 1. Descoberta: recurso protegido → servidor de autorização → endpoints
        let root = URL(string: "\(server.scheme ?? "https")://\(server.host ?? "")")!
        let resource = (try? await Self.json(root.appending(path: ".well-known/oauth-protected-resource"))) ?? [:]
        let issuer = (resource["authorization_servers"] as? [String])?.first.flatMap(URL.init(string:)) ?? root
        let meta = try await Self.json(issuer.appending(path: ".well-known/oauth-authorization-server"))
        guard let authURL = (meta["authorization_endpoint"] as? String).flatMap(URL.init(string:)),
              let tokenURL = (meta["token_endpoint"] as? String).flatMap(URL.init(string:)),
              let registerURL = (meta["registration_endpoint"] as? String).flatMap(URL.init(string:))
        else { throw NativeOAuthError.discoveryFailed }

        // 2. Registro dinâmico: cliente público, sem segredo
        let reg = try await Self.json(registerURL, body: [
            "client_name": clientName, "redirect_uris": [redirectURI.absoluteString],
            "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ])
        guard let clientID = reg["client_id"] as? String else { throw NativeOAuthError.registrationFailed }

        // 3. PKCE + estado anti-CSRF; 4. tela de login do sistema
        let pkce = PKCE()
        let state = PKCE.random(16)
        let url = authorizationURL(endpoint: authURL, clientID: clientID, pkce: pkce, state: state,
                                   resource: (resource["resource"] as? String) ?? root.absoluteString)
        let back = try await presenter.presentAuthorizationURL(url)
        let code = try Self.code(from: back, expectedState: state)

        // 5. Troca do código pelo token
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form([
            "grant_type": "authorization_code", "code": code, "redirect_uri": redirectURI.absoluteString,
            "client_id": clientID, "code_verifier": pkce.verifier,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let tok = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let access = tok["access_token"] as? String else {
            throw NativeOAuthError.tokenRejected("\(tok["error"] ?? "?") \(tok["error_description"] ?? "")")
        }
        return OAuthToken(accessToken: access, expiresIn: tok["expires_in"] as? Int)
    }

    /// Monta a URL de autorização (pura, testável).
    public func authorizationURL(endpoint: URL, clientID: String, pkce: PKCE, state: String, resource: String) -> URL {
        var c = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI.absoluteString),
            .init(name: "code_challenge", value: pkce.challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state), .init(name: "resource", value: resource),
        ] + (scope.map { [.init(name: "scope", value: $0)] } ?? [])
        return c.url!
    }

    /// Lê o `code` da URL de retorno, conferindo o `state`.
    public static func code(from callback: URL, expectedState: String) throws -> String {
        let q = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard q.first(where: { $0.name == "state" })?.value == expectedState else { throw NativeOAuthError.stateMismatch }
        guard let code = q.first(where: { $0.name == "code" })?.value else {
            throw NativeOAuthError.missingCode(q.first(where: { $0.name == "error" })?.value ?? "?")
        }
        return code
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)!
    }

    static func json(_ url: URL, body: [String: Any]? = nil) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

/// Par verificador/desafio do PKCE (S256).
public struct PKCE: Sendable {
    public let verifier: String
    public var challenge: String { Self.challenge(for: verifier) }
    public init(verifier: String = PKCE.random(32)) { self.verifier = verifier }

    public static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }
    public static func random(_ bytes: Int) -> String {
        Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).base64URL
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
