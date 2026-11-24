import Foundation

@main
struct SessionCookiesTests {
    static func cookie(name: String = "remember_admin_user_token", domain: String = "app.account-a.test", value: String = "signed-token", expires: Date? = Date().addingTimeInterval(3600), secure: Bool = true, httpOnly: Bool = true) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/"]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        properties[HTTPCookiePropertyKey.sameSitePolicy] = "lax"
        return HTTPCookie(properties: properties)!
    }

    static func main() throws {
        let remembered = cookie()
        let device = cookie(name: "unitymob_admin_device_id")
        let otherTenant = cookie(domain: "app.account-b.test")
        let expires = remembered.expiresDate!
        let decoded = SessionCookieArchive.decode(try SessionCookieArchive.encode([
            remembered, device, otherTenant,
            cookie(name: "_unitymob_crm_session"), // sessão transitória nunca vira persistente
            cookie(expires: nil), cookie(expires: Date().addingTimeInterval(-10)),
            cookie(secure: false), cookie(httpOnly: false), cookie(name: "unrelated")
        ]))
        assert(decoded.count == 3)
        assert(Set(decoded.map { $0.domain }) == ["app.account-a.test", "app.account-b.test"])
        assert(decoded.allSatisfy { $0.isSecure && $0.isHTTPOnly })
        assert(decoded.first!.expiresDate == expires)
        assert(decoded.first!.value == "signed-token")
        assert(decoded.first!.path == "/")
        assert(decoded.first!.properties?[HTTPCookiePropertyKey.sameSitePolicy] as? String == "lax")

        // WebKit esvaziado: recupera somente credenciais ainda válidas, cada qual no seu domínio.
        assert(SessionCookieArchive.missing(saved: decoded, current: []).count == 3)
        // Cookie atual vence o backup: não desfaz rotação feita pelo servidor.
        let rotated = cookie(value: "new-token")
        let missing = SessionCookieArchive.missing(saved: decoded, current: [rotated])
        assert(missing.count == 2)
        assert(!missing.contains { $0.name == remembered.name && $0.domain == remembered.domain })
        // Logout gera arquivo vazio, sem ressuscitar o lembrar-me no próximo boot.
        let emptyArchive = try SessionCookieArchive.encode([])
        assert(SessionCookieArchive.decode(emptyArchive).isEmpty)
        let afterLogout = SessionCookieArchive.decode(try SessionCookieArchive.encode([device]))
        assert(afterLogout.map { $0.name } == ["unitymob_admin_device_id"])
        assert(SessionCookieArchive.decode(Data("invalid".utf8)).isEmpty)
        assert(!SessionCookieArchive.eligible(remembered, now: expires.addingTimeInterval(1)))
        print("Session cookies: filtering, expiry, tenant domains, rotation, logout and archive round-trip passed")
    }
}
