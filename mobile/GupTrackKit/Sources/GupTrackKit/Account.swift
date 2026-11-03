import Foundation
#if canImport(Security)
import Security
#endif

/// The server this iPhone is signed in to and its device token. Lives only in the Keychain (this device only,
/// readable after first unlock so the widget's refresh works), never in UserDefaults or files.
struct ServerAccount: Codable, Equatable, Sendable {
    var baseURL: URL
    var token: String
    /// this phone's row in Settings › Connected apps
    var deviceId: Int
    var user: UserRef
    /// "owner" | "member"
    var role: String = "member"
    var signedInAt: Date

    /// the host for the UI ("guptrack.example.ts.net" -> "guptrack")
    var shortHost: String { String((baseURL.host ?? "").split(separator: ".").first ?? "") }
}

/// Where the account is kept. The app uses the Keychain; tests and Linux use memory.
protocol TokenStore: AnyObject {
    func load() -> ServerAccount?
    @discardableResult func save(_ account: ServerAccount) -> Bool
    func clear()
}

final class MemoryTokenStore: TokenStore {
    private var kept: ServerAccount?
    init(_ account: ServerAccount? = nil) { kept = account }
    func load() -> ServerAccount? { kept }
    func save(_ account: ServerAccount) -> Bool { kept = account; return true }
    func clear() { kept = nil }
}

#if canImport(Security)
final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "server"

    init(service: String = "app.guptrack.phone.account") {
        self.service = service
    }

    private var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() -> ServerAccount? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? APIClient.decoder.decode(ServerAccount.self, from: data)
    }

    @discardableResult
    func save(_ a: ServerAccount) -> Bool {
        guard let data = try? APIClient.encoder.encode(a) else { return false }
        let attrs: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(item as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(item.merging(attrs) { $1 } as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    func clear() {
        SecItemDelete(item as CFDictionary)
    }
}
#endif

/// The pairing link the website's Settings › Connected apps shows as a QR code (docs/app-api.md §4.1):
///     guptrack://pair?server=<encoded base URL>&code=<code like 7KQ4-M2XD>
/// The address is HTTPS (a Tailscale name, or any https host once GupTrack is hosted); plain http only for this
/// machine (http://127.0.0.1:3000 while developing).
struct PairLink: Equatable, Sendable {
    let baseURL: URL
    /// the code as shown: "7KQ4-M2XD"
    let code: String

    enum Problem: Error, Equatable {
        case notOurs, badAddress, badCode

        var message: String {
            switch self {
            case .notOurs: return "That isn't a GupTrack pairing code. On the website, open Settings › Connected apps."
            case .badAddress: return "The code's server address isn't an HTTPS address, so the app won't use it."
            case .badCode: return "The code is cut off or damaged. Make a new one on the website."
            }
        }
    }

    static func parse(_ text: String) -> Result<PairLink, Problem> {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.scheme?.lowercased() == "guptrack", c.host?.lowercased() == "pair",
              c.path.isEmpty || c.path == "/", let items = c.queryItems else { return .failure(.notOurs) }
        var q: [String: String] = [:]
        for it in items {
            guard q[it.name] == nil else { return .failure(.notOurs) }
            // URLSearchParams writes a space as "+"
            q[it.name] = (it.value ?? "").replacingOccurrences(of: "+", with: " ")
        }
        guard let raw = q["server"], let url = serverURL(raw) else { return .failure(.badAddress) }
        guard let code = q["code"].flatMap(pairingCode) else { return .failure(.badCode) }
        return .success(PairLink(baseURL: url, code: code))
    }

    /// https://host[:port][/] with nothing else (no user, path, query or fragment); http only for this machine.
    /// A bare name typed on the connect screen ("guptrack.example.ts.net") gets https:// in front.
    static func serverURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let c = URLComponents(string: s), let scheme = c.scheme?.lowercased(),
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", let host = c.host?.lowercased(), !host.isEmpty
        else { return nil }
        let loopback = ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
        switch scheme {
        case "https":
            guard loopback || (host.contains(".") && host.unicodeScalars.allSatisfy(CharacterSet.hostChars.contains))
            else { return nil }
        case "http":
            guard loopback else { return nil }
        default:
            return nil
        }
        var out = URLComponents()
        out.scheme = scheme
        out.host = host
        out.port = c.port
        return out.url
    }

    /// A typed or scanned code as the website compares it (src/sync/devices.server.ts normalizePairing): case,
    /// spaces and dashes don't matter, O reads as 0 and I/L as 1. Returns "XXXX-XXXX", or nil when it isn't one.
    static func pairingCode(_ raw: String) -> String? {
        guard raw.count <= 40 else { return nil }
        var s = ""
        for ch in raw.uppercased() where !(ch.isWhitespace || ch == "-") {
            switch ch {
            case "O": s.append("0")
            case "I", "L": s.append("1")
            default: s.append(ch)
            }
        }
        guard s.count == 8, s.allSatisfy(crockford.contains) else { return nil }
        return String(s.prefix(4)) + "-" + String(s.suffix(4))
    }

    /// Crockford base 32: the digits and A–Z without I, L, O and U
    static let crockford: Set<Character> = Set((48...57).map { Character(UnicodeScalar($0)) }
        + (65...90).map { Character(UnicodeScalar($0)) }.filter { !"ILOU".contains($0) })
}

extension CharacterSet {
    private static let lower = "abcdefghijklmnopqrstuvwxyz", digits = "0123456789"
    static let hostChars = CharacterSet(charactersIn: lower + digits + "-.")
}

enum PasswordStrength: Int, Comparable, Sendable {
    case tooShort, weak, fair, strong

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    /// the website's rule: 15 characters or more; longer and more varied is stronger
    static func of(_ p: String) -> PasswordStrength {
        guard p.count >= 15 else { return .tooShort }
        var kinds = 0
        if p.rangeOfCharacter(from: .lowercaseLetters) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: .uppercaseLetters) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: .decimalDigits) != nil { kinds += 1 }
        if p.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { kinds += 1 }
        let words = p.split(separator: " ").count
        if p.count >= 24 || (kinds >= 3 && p.count >= 18) || words >= 4 { return .strong }
        if kinds >= 2 || words >= 3 { return .fair }
        return .weak
    }

    var label: String {
        switch self {
        case .tooShort: return "At least 15 characters"
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        }
    }

    /// how much of the meter is filled (0...1)
    var fill: Double { [0.1, 0.33, 0.66, 1][rawValue] }
}
