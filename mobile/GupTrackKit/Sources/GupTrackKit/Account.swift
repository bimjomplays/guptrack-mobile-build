import Foundation
#if canImport(Security)
import Security
#endif

/// The server this iPhone is signed in to and its device token. Lives only in the Keychain (this device only,
/// readable after first unlock so the widget's refresh works), never in UserDefaults or files.
struct ServerAccount: Codable, Equatable, Sendable {
    var baseURL: URL
    var token: String
    var deviceId: String
    var user: UserRef
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

/// The pairing link the website's Settings › Connected apps shows as a QR code:
///     guptrack://pair?v=1&url=<percent-encoded https://<pc>.<tailnet>.ts.net>&code=<one-time code>
/// The address must be HTTPS (a Tailscale name, or any https host once GupTrack is hosted).
struct PairLink: Equatable, Sendable {
    let baseURL: URL
    let code: String

    enum Problem: Error, Equatable {
        case notOurs, newerVersion, badAddress, badCode

        var message: String {
            switch self {
            case .notOurs: return "That isn't a GupTrack pairing code. On the website, open Settings › Connected apps."
            case .newerVersion: return "The website made a code this app doesn't know yet. Update the app."
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
            q[it.name] = it.value ?? ""
        }
        guard let v = q["v"].flatMap(Int.init) else { return .failure(.notOurs) }
        guard v == 1 else { return .failure(v > 1 ? .newerVersion : .notOurs) }
        guard let raw = q["url"], let url = serverURL(raw) else { return .failure(.badAddress) }
        guard let code = q["code"], isCode(code) else { return .failure(.badCode) }
        return .success(PairLink(baseURL: url, code: code))
    }

    /// https://host[:port][/] with nothing else (no user, path, query or fragment). A bare name typed on the
    /// connect screen ("guptrack.example.ts.net") gets https:// in front.
    static func serverURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let c = URLComponents(string: s), c.scheme?.lowercased() == "https",
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.path.isEmpty || c.path == "/", let host = c.host?.lowercased(), !host.isEmpty,
              host.contains("."), host.unicodeScalars.allSatisfy({ CharacterSet.hostChars.contains($0) })
        else { return nil }
        var out = URLComponents()
        out.scheme = "https"
        out.host = host
        out.port = c.port
        return out.url
    }

    /// base64url without padding, 32 bytes or more
    static func isCode(_ s: String) -> Bool {
        (43...128).contains(s.count) && s.unicodeScalars.allSatisfy(CharacterSet.codeChars.contains)
    }
}

extension CharacterSet {
    private static let lower = "abcdefghijklmnopqrstuvwxyz", digits = "0123456789"
    static let hostChars = CharacterSet(charactersIn: lower + digits + "-.")
    static let codeChars = CharacterSet(charactersIn: lower + lower.uppercased() + digits + "-_")
}

/// How strong a new password is, for the Join screen's meter.
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
