import Foundation
import Security
import WebKit

// Não guarda senha nem cookie de sessão: o Devise continua decidindo se o
// lembrar-me é válido, inclusive depois de logout/revogação pelo servidor.
struct SessionCookieArchive {
    static let names: Set<String> = ["remember_admin_user_token", "unitymob_admin_device_id"]

    static func eligible(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        names.contains(cookie.name) && cookie.isSecure && cookie.isHTTPOnly &&
            (cookie.expiresDate.map { $0 > now } ?? false)
    }

    static func encode(_ cookies: [HTTPCookie]) throws -> Data {
        let properties = cookies.filter { eligible($0) }.compactMap { cookie -> [String: Any]? in
            cookie.properties?.reduce(into: [String: Any]()) { result, entry in
                result[entry.key.rawValue] = (entry.value as? URL)?.absoluteString ?? entry.value
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0)
    }

    static func decode(_ data: Data) -> [HTTPCookie] {
        guard let properties = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else { return [] }
        return properties.compactMap { values in
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: values.map { (HTTPCookiePropertyKey($0.key), $0.value) }))
        }.filter { eligible($0) }
    }

    static func key(_ cookie: HTTPCookie) -> String {
        "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
    }

    static func missing(saved: [HTTPCookie], current: [HTTPCookie]) -> [HTTPCookie] {
        let existing = Set(current.map { key($0) })
        return saved.filter { eligible($0) && !existing.contains(key($0)) }
    }
}

final class PersistentSessionCookies: NSObject, WKHTTPCookieStoreObserver {
    private let store: WKHTTPCookieStore
    private let query: [String: Any]
    private var snapshotVersion = 0

    init(store: WKHTTPCookieStore = WKWebsiteDataStore.default().httpCookieStore) {
        self.store = store
        self.query = [kSecClass as String: kSecClassGenericPassword,
                      kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "br.com.unitymob.field").session-cookies",
                      kSecAttrAccount as String: "persistent-cookies-v1"]
        super.init()
    }

    // Restaura antes de criar o WebView para não disparar uma navegação anônima.
    func restore(completion: @escaping () -> Void) {
        var item: CFTypeRef?
        var readQuery = query
        readQuery[kSecReturnData as String] = true
        let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
        let saved = (item as? Data).map { SessionCookieArchive.decode($0) } ?? []
        store.getAllCookies { [self] current in
            let group = DispatchGroup()
            for cookie in SessionCookieArchive.missing(saved: saved, current: current) {
                group.enter()
                store.setCookie(cookie) { group.leave() }
            }
            group.notify(queue: .main) { [self] in
                store.add(self)
                // Se o Keychain estiver bloqueado, não apaga o arquivo anterior.
                if status == errSecSuccess || status == errSecItemNotFound { capture() }
                completion()
            }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        capture()
    }

    func capture(completion: @escaping () -> Void = {}) {
        snapshotVersion += 1
        let version = snapshotVersion
        store.getAllCookies { [self] cookies in
            defer { completion() }
            guard version == snapshotVersion, let data = try? SessionCookieArchive.encode(cookies) else { return }
            let values: [String: Any] = [kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
            if status == errSecItemNotFound {
                let item = query.merging(values) { _, new in new }
                let addStatus = SecItemAdd(item as CFDictionary, nil)
                if addStatus != errSecSuccess { NSLog("[SessionCookies] Keychain write failed: %d", addStatus) }
            } else if status != errSecSuccess {
                NSLog("[SessionCookies] Keychain update failed: %d", status)
            }
        }
    }
}
