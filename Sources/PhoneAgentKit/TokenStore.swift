import Foundation
import Security

/// Guarda tokens OAuth no Keychain do aparelho (só este aparelho, depois do primeiro desbloqueio).
public struct TokenStore: Sendable {
    public let service: String
    public init(service: String) { self.service = service }

    public func save(_ token: OAuthToken, account: String) {
        let expiry = Date().addingTimeInterval(TimeInterval(token.expiresIn ?? 3600) - 60)
        let data = try? JSONSerialization.data(withJSONObject: ["t": token.accessToken, "v": expiry.timeIntervalSince1970])
        let base = query(account)
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Devolve o token só se ainda não venceu.
    public func load(account: String) -> OAuthToken? {
        var q = query(account)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let t = o["t"] as? String, let v = o["v"] as? Double, Date().timeIntervalSince1970 < v
        else { return nil }
        return OAuthToken(accessToken: t, expiresIn: Int(v - Date().timeIntervalSince1970))
    }

    public func delete(account: String) { SecItemDelete(query(account) as CFDictionary) }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
