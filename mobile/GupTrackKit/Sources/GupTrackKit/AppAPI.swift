import Foundation

/// The app API's shape (/api/app/v1 on the GupTrack server, next to Harbor's /api/sync/v1). Sign-in, the server's
/// hello and the library sync live here; each screen's own calls are `APIClient` extensions next to its models
/// (Home.swift, Browse.swift, TitlePage.swift…), named after the paths the demo fixtures are recorded under
/// (mobile/fixtures/demo/api/<path>.json).
enum AppAPI {
    static let prefix = "/api/app/v1"
    static let version = 1
}

// MARK: hello and sign-in

/// GET hello: what the server is (no token needed)
struct ServerHello: Codable, Equatable, Sendable {
    var app: String               // "guptrack"
    var version: String
    var api: Int
    var name: String              // the server's name, shown on the sign-in screen
    var joining: String           // "open" | "invite" | "closed"
    var passkeys: Bool
}

/// POST auth/pair: the one-time code from the website's Settings › Connected apps QR
struct PairBody: Codable, Equatable, Sendable {
    var code: String
    var device: String
}

/// POST auth/sign-in
struct SignInBody: Codable, Equatable, Sendable {
    var username: String
    var password: String
    var device: String
}

/// POST auth/join: a new account on the server
struct JoinBody: Codable, Equatable, Sendable {
    var username: String
    var displayName: String
    var password: String
    var device: String
    var invite: String?
}

/// what pairing, signing in and joining give the device: its own token (revocable from the website), who it is
struct DeviceGrant: Codable, Equatable, Sendable {
    var token: String
    var deviceId: String
    var user: UserRef
    /// only after joining: shown once, never again
    var recoveryCodes: [String]?
}

extension APIClient {
    func hello() async throws -> ServerHello { try await get("hello") }

    func pair(code: String, device: String) async throws -> DeviceGrant {
        try await send("POST", "auth/pair", PairBody(code: code, device: device))
    }

    func signIn(username: String, password: String, device: String) async throws -> DeviceGrant {
        try await send("POST", "auth/sign-in", SignInBody(username: username, password: password, device: device))
    }

    func join(_ body: JoinBody) async throws -> DeviceGrant { try await send("POST", "auth/join", body) }

    /// POST auth/sign-out: revokes this device's token on the server
    func signOut() async throws -> OKReply { try await send("POST", "auth/sign-out") }
}

// MARK: the library sync (offline library, LibraryStore)

/// One change the server made to the library, from the change feed.
struct FeedChange: Codable, Equatable, Sendable {
    var titleId: String
    var revision: Int
    /// nil when the title left the list
    var entry: LibraryEntry?
}

/// GET library/changes?since=<cursor>: changes after the cursor, oldest first. `reset` means the cursor is too old
/// (or missing): the page starts a full copy, so entries not in it (over all pages) are gone.
struct ChangePage: Codable, Equatable, Sendable {
    var changes: [FeedChange]
    var cursor: String
    var more: Bool
    var reset: Bool
}

/// One local edit going up: the request id makes it safe to send twice (the server applies each id once).
struct OutgoingChange: Codable, Equatable, Sendable {
    var requestId: String
    var titleId: String
    var patch: LibraryPatch
    /// the title, when it isn't on the list yet (adding from Browse while offline)
    var title: Title?
}

/// POST library/changes
struct ChangeBatch: Codable, Equatable, Sendable {
    var changes: [OutgoingChange]
}

/// the server's answer per request id: applied (with the entry as it is now) or rejected (why)
struct ChangeResult: Codable, Equatable, Sendable {
    var requestId: String
    var ok: Bool
    var revision: Int?
    var entry: LibraryEntry?
    var error: String?
}

struct ChangeBatchReply: Codable, Equatable, Sendable {
    var results: [ChangeResult]
}

extension APIClient {
    func libraryChanges(since cursor: String?) async throws -> ChangePage {
        try await get("library/changes", query: cursor.map { [URLQueryItem(name: "since", value: $0)] } ?? [])
    }

    func pushChanges(_ batch: ChangeBatch) async throws -> ChangeBatchReply {
        try await send("POST", "library/changes", batch)
    }

    /// GET lists: your custom lists
    func customLists() async throws -> [CustomList] { try await get("lists") }
}
