import Foundation

/// GupTrack's app API (docs/app-api.md): `{base}/api/app/v1/{endpoint}`, JSON with a bearer token. Signing in, `me`
/// and the library live here; each screen's own calls are `APIClient` extensions next to its models (Home.swift,
/// Browse.swift, TitlePage.swift…), at the doc's paths. The demo answers them from fixtures recorded at the same
/// paths (mobile/fixtures/demo/api/<path>.json).
enum AppAPI {
    static let prefix = "/api/app/v1"
    static let app = "guptrack"
    static let version = 1
}

// MARK: §1 the server

/// GET server (no token): what is there. Check `app == "guptrack"` and `api == 1` before showing a sign-in screen.
struct ServerInfo: Codable, Equatable, Sendable {
    var app: String
    var api: Int
    /// true until the first account is made on the website (it needs the setup code on the PC)
    var setupOpen: Bool
    var serverTime: Int64
}

// MARK: §4 signing in

/// What the app describes itself as in every sign-in call: `name` ≤ 60 (shown in Connected apps), `platform` ≤ 30.
struct DeviceInfo: Codable, Equatable, Sendable {
    var name: String
    var platform: String

    init(name: String, platform: String) {
        self.name = String(name.prefix(60))
        self.platform = String(platform.prefix(30))
    }
}

/// A connected phone (or Harbor) as the website lists it (`Device`, src/sync/devices.server.ts).
struct Device: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: Int
    /// "app" (this app) or "sync" (Harbor)
    var scope: String
    var app: String
    var name: String
    var platform: String
    var createdAt: Int64
    var lastUsedAt: Int64?
}

/// The signed-in account (`Me`, src/settings/profile.ts).
struct Me: Codable, Equatable, Hashable, Sendable {
    var username: String
    /// "owner" | "member"
    var role: String
}

/// Every sign-in answer: the phone's token (shown once; GupTrack keeps only a hash), the device row and who.
/// Joining adds the recovery codes (show them once); recovering says how many codes are left.
struct SignInAnswer: Codable, Equatable, Sendable {
    var token: String
    var device: Device
    var user: Me
    var serverTime: Int64
    var recoveryCodes: [String]?
    var codesLeft: Int?
}

struct PairCheckBody: Codable, Equatable, Sendable { var code: String }

/// POST auth/pair/check: whose code it is, without using it ("Sign in as mika?")
struct PairCheck: Codable, Equatable, Sendable {
    struct Who: Codable, Equatable, Sendable { var username: String }
    var user: Who
    var serverTime: Int64
}

struct PairBody: Codable, Equatable, Sendable {
    var code: String
    var device: DeviceInfo
}

struct SignInBody: Codable, Equatable, Sendable {
    var username: String
    var password: String
    var device: DeviceInfo
}

/// POST auth/join: a new account with an invite
struct JoinBody: Codable, Equatable, Sendable {
    /// the code from the invite link
    var invite: String
    var username: String
    var password: String
    var device: DeviceInfo
}

/// POST auth/recover: a new password with a recovery code (every browser and app is signed out first)
struct RecoverBody: Codable, Equatable, Sendable {
    var username: String
    var code: String
    var password: String
    var device: DeviceInfo
}

/// The profile everyone sees (`Profile`, src/settings/profile.ts). `avatar` is a GupTrack address ("/media/…",
/// fetched with the token, §5) or null.
struct Profile: Codable, Equatable, Sendable {
    /// "" = not set yet
    var name: String
    var avatar: String?
    /// the bio and its banner (BioState); the app reads it where it shows it
    var bio: JSONValue?
    /// when this library was started (ms)
    var joined: Int64
}

/// Preferences (Settings › Appearance and Preferences; `Prefs`, src/settings/prefs.ts).
struct Prefs: Codable, Equatable, Sendable {
    struct Notify: Codable, Equatable, Sendable {
        var episodes: Bool
        var sequels: Bool
        var releases: Bool
        /// "watching" | "planning"
        var lists: String
        var friends: Bool
        var comments: Bool
        var social: Bool
        var messages: Bool
        var desktop: Bool
    }

    /// "english" | "romaji" | "native"
    var titleLanguage: String
    /// "100" | "10.0" | "10" | "5" | "3"
    var scoreFormat: String
    var adult: Bool
    /// "hide" | "show"
    var spoilers: String
    var theme: String
    var smartProgress: Bool
    var autoDates: Bool
    /// lists switched off in Settings
    var hidden: [APIMedia]
    var notify: Notify
    /// "mdy" | "dmy" | "mdy-num" | "dmy-num" | "iso"
    var dateFormat: String
    /// "sunday" | "monday"
    var weekStart: String
}

/// GET me: who and how
struct MeAnswer: Codable, Equatable, Sendable {
    var me: Me
    var profile: Profile
    var prefs: Prefs
    var device: Device
    var serverTime: Int64

    /// the account as the screens show it (the name falls back to the username until one is set)
    func user(on base: URL?) -> UserRef {
        UserRef(username: me.username, name: profile.name.isEmpty ? me.username : profile.name,
                avatar: Pictures.url(profile.avatar, base: base))
    }
}

extension APIClient {
    func server() async throws -> ServerInfo { try await get("server") }

    func checkPairing(code: String) async throws -> PairCheck {
        try await send("POST", "auth/pair/check", PairCheckBody(code: code))
    }

    func pair(code: String, device: DeviceInfo) async throws -> SignInAnswer {
        try await send("POST", "auth/pair", PairBody(code: code, device: device))
    }

    func signIn(username: String, password: String, device: DeviceInfo) async throws -> SignInAnswer {
        try await send("POST", "auth/sign-in", SignInBody(username: username, password: password, device: device))
    }

    func join(_ body: JoinBody) async throws -> SignInAnswer { try await send("POST", "auth/join", body) }

    func recover(_ body: RecoverBody) async throws -> SignInAnswer { try await send("POST", "auth/recover", body) }

    /// POST auth/sign-out: removes this phone's token on the server
    func signOut() async throws -> OKReply { try await send("POST", "auth/sign-out") }

    func me() async throws -> MeAnswer { try await get("me") }

    /// the same server with a token (right after joining, before the account is kept)
    func signedIn(_ token: String) -> APIClient { APIClient(transport: transport, token: token) }

    /// PATCH settings/profile: the name and/or the bio (BioState, which holds the banner and its fade)
    func updateProfile(_ patch: ProfilePatch) async throws -> ProfileAnswer {
        try await send("PATCH", "settings/profile", patch)
    }
}

struct ProfilePatch: Codable, Equatable, Sendable {
    var name: String?
    var bio: JSONValue?

    init(name: String? = nil, bio: JSONValue? = nil) {
        self.name = name
        self.bio = bio
    }
}

/// `{ profile }`: the answer to every Settings › Profile change
struct ProfileAnswer: Codable, Equatable, Sendable { var profile: Profile }

// MARK: §5 pictures

/// Pictures in answers are full https addresses (the catalogues: no token) or GupTrack addresses starting with `/`,
/// fetched as `{base}/api/app/v1/files` + address with the token.
enum Pictures {
    /// the server and token the image loader uses for GupTrack's own pictures (set while signed in)
    nonisolated(unsafe) static var signedIn: (base: URL, token: String)?

    /// an address from an answer as a URL to fetch
    static func url(_ address: String?, base: URL?) -> URL? {
        guard let address, !address.isEmpty else { return nil }
        if address.hasPrefix("/") {
            guard let base else { return nil }
            return APIRequest("GET", "files" + address).url(on: base)
        }
        guard let u = URL(string: address), u.scheme == "https" else { return nil }
        return u
    }

    /// A picture's URL as a model decoded it, ready to fetch. Models keep addresses as they came (a GupTrack "/…"
    /// address decodes as a relative URL); the image loader resolves it on the signed-in server.
    static func resolve(_ url: URL) -> URL? {
        if url.scheme == nil { return Self.url(url.relativeString, base: signedIn?.base) }
        if url.scheme == "https" { return url }
        // GupTrack's own pictures on a plain-http server (a dev server on the same Mac)
        if url.scheme == "http", let s = signedIn, url.host == s.base.host, url.port == s.base.port { return url }
        return nil
    }

    /// the Authorization header for a picture on the signed-in server (nil for the catalogues' pictures)
    static func authorization(for url: URL) -> String? {
        guard let s = signedIn, url.host == s.base.host, url.port == s.base.port,
              url.path.contains(AppAPI.prefix + "/files/") else { return nil }
        return "Bearer " + s.token
    }
}

// MARK: §7 the library

extension APIClient {
    /// GET library/changes?since=<cursor>&limit=<1–500>
    func libraryChanges(since cursor: String?, limit: Int? = nil) async throws -> ChangeFeed {
        var q: [URLQueryItem] = []
        if let cursor { q.append(URLQueryItem(name: "since", value: cursor)) }
        if let limit { q.append(URLQueryItem(name: "limit", value: String(min(500, max(1, limit))))) }
        return try await get("library/changes", query: q)
    }

    /// POST library/write: the outbox's ops (1–100); their request ids are in the body, not the header
    func writeLibrary(_ batch: WriteBatch) async throws -> WriteAnswer {
        try await call(APIRequest("POST", "library/write", body: try Self.encoder.encode(batch), token: token))
    }
}

extension APIClient {
    /// an id or name as one path segment: only the unreserved characters stay as they are
    static func segment(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    /// RFC 3986's unreserved characters (ASCII only: `.alphanumerics` would let "é" through unencoded)
    private static let unreserved: CharacterSet = {
        var set = CharacterSet(charactersIn: "-._~")
        for r in ["A"..."Z", "a"..."z", "0"..."9"] as [ClosedRange<Unicode.Scalar>] { set.insert(charactersIn: r) }
        return set
    }()
}
