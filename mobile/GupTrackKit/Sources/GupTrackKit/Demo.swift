import Foundation

/// The demo: the app on recorded answers instead of a server. Started with `-demo`; the screen tests and the
/// screenshots use it, and so can anyone trying the app without a GupTrack server.
///
/// Launch flags (also set by the screen tests through `Demo.args`):
///   -demo                      use the demo data, signed in as the demo user
///   -tab <home|browse|…>       the tab to open on
///   -open <route path>         push a page on its tab ("title/anime:210482"); repeat for a deeper stack
///   -sheet <sheet id>          show a sheet ("editor/anime:210482/false", "new-list")
///   -account <screen>          a signed-out screen (welcome, connect, sign-in, join)
///   -offline                   every call fails as if the server were unreachable
enum Demo {
    static var args: [String] = ProcessInfo.processInfo.arguments

    static var isOn: Bool { args.contains("-demo") }

    /// the value after a flag ("-tab library" -> "library")
    static func value(_ flag: String) -> String? { values(flag).last }

    /// every value after a repeated flag
    static func values(_ flag: String) -> [String] {
        var out: [String] = []
        var i = args.startIndex
        while i < args.endIndex {
            if args[i] == flag, args.index(after: i) < args.endIndex { out.append(args[args.index(after: i)]) }
            i = args.index(after: i)
        }
        return out
    }

    static func has(_ flag: String) -> Bool { args.contains(flag) }

    /// where the fixtures are: the app bundle's "demo" folder, or the repo's mobile/fixtures/demo under swift test
    static var root: URL = {
        if let env = ProcessInfo.processInfo.environment["GUPTRACK_FIXTURES"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        #if canImport(Darwin)
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let url = bundle.url(forResource: "demo", withExtension: nil) { return url }
        }
        #endif
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("fixtures/demo", isDirectory: true)
    }()

    /// the server address the demo pretends to use
    static let server = URL(string: "https://guptrack.example")!

    /// a fixture file's bytes ("api/me.json")
    static func data(_ relative: String) -> Data? {
        try? Data(contentsOf: root.appendingPathComponent(relative))
    }

    static func load<T: Decodable>(_ type: T.Type, _ relative: String) throws -> T {
        guard let d = data(relative) else { throw APIError.server(404, "not_found", "No demo data at \(relative).") }
        return try APIClient.decoder.decode(type, from: d)
    }

    /// "titles/anime:210482" -> "api/titles/anime_210482.json"; a query's first value picks a variant
    /// ("search?q=Frieren" -> "api/search/frieren.json")
    static func file(_ path: String, variant: String? = nil, method: String = "GET") -> String {
        var p = "api/" + safe(path)
        if let variant { p += "/" + slug(variant) }
        if method != "GET" { p += "." + method.lowercased() }
        return p + ".json"
    }

    static func safe(_ path: String) -> String {
        path.split(separator: "/").map { $0.replacingOccurrences(of: ":", with: "_") }.joined(separator: "/")
    }

    static func slug(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: ":", with: "_")
        var out = ""
        for ch in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) || ch == "_" { out.unicodeScalars.append(ch) }
            else if !out.hasSuffix("-") { out += "-" }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// the demo user, signed in (from GET me's fixture)
    static func account() -> ServerAccount {
        let me = try? load(MeAnswer.self, "api/me.json")
        return ServerAccount(baseURL: server, token: "demo-token", deviceId: me?.device.id ?? 1,
                             user: me?.user(on: server) ?? UserRef(username: "demo", name: "Demo", avatar: nil),
                             role: me?.me.role ?? "owner", signedInAt: Clock.demoNow)
    }

    /// the demo library as the screens show it (the change feed's fixture)
    static func library() -> [LibraryEntry] {
        ((try? load(ChangeFeed.self, "api/library/changes.json"))?.entries ?? []).map(\.library)
    }
}

/// The demo's library on the "server": the change feed's fixture, then every op written to it, each with the next
/// revision. Cursors are "demo.<rev>".
final class DemoLibrary: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: SyncEntry] = [:]
    private var removed: [String: (ChangeFeed.Removed, Int)] = [:]
    private var lists: [FeedList] = []
    private var rev = 0
    private var loaded = false

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let feed = try? Demo.load(ChangeFeed.self, "api/library/changes.json") else { return }
        for e in feed.entries {
            entries[e.titleId] = e
            rev = max(rev, e.rev)
        }
        lists = feed.lists.changed
        rev = max(rev, lists.map(\.rev).max() ?? 0)
    }

    var cursor: String { "demo.\(rev)" }

    /// GET library/changes: what changed after `since` (nil: everything); nil when the cursor isn't the demo's
    func changes(since: String?, limit: Int) -> ChangeFeed? {
        lock.lock(); defer { lock.unlock() }
        load()
        var after = 0
        if let since {
            guard since.hasPrefix("demo."), let n = Int(since.dropFirst(5)), n <= rev else { return nil }
            after = n
        }
        let page = entries.values.filter { $0.rev > after }.sorted { $0.rev < $1.rev }
        let shown = Array(page.prefix(limit))
        let more = page.count > shown.count
        let upTo = more ? (shown.last?.rev ?? after) : rev
        return ChangeFeed(entries: shown,
                          removed: removed.values.filter { $0.1 > after && $0.1 <= upTo }.map(\.0),
                          lists: .init(changed: lists.filter { $0.rev > after && $0.rev <= upTo }, removed: []),
                          cursor: "demo.\(upTo)", more: more, serverTime: Millis.of(Clock.now))
    }

    /// POST library/write: each op folded in with the website's list rules; an older op than the entry is stale
    func write(_ batch: WriteBatch) -> WriteAnswer {
        lock.lock(); defer { lock.unlock() }
        load()
        let results = batch.ops.map { op -> WriteResult in
            let key = op.titleId
            let now = entries[key]
            if let now, op.at < now.changedAt {
                return WriteResult(requestId: op.requestId, applied: false, reason: "stale", media: op.media, id: op.id,
                                   entry: now)
            }
            guard let next = op.applied(to: now?.entry) else {
                guard now != nil else {
                    return WriteResult(requestId: op.requestId, applied: false, reason: "not_on_list", media: op.media,
                                       id: op.id, entry: nil)
                }
                rev += 1
                entries[key] = nil
                removed[key] = (ChangeFeed.Removed(media: op.media, id: op.id, removedAt: op.at), rev)
                return WriteResult(requestId: op.requestId, applied: true, media: op.media, id: op.id, entry: nil,
                                   removed: true)
            }
            rev += 1
            var e = next
            e.updated = 0  // days since the last change, as the server writes it
            let s = SyncEntry(media: op.media, entry: e, statusAt: op.at, progressAt: op.at, scoreAt: op.at,
                              changedAt: op.at, rev: rev)
            entries[key] = s
            removed[key] = nil
            return WriteResult(requestId: op.requestId, applied: true, media: op.media, id: op.id, entry: s)
        }
        return WriteAnswer(results: results, cursor: "demo.\(rev)", serverTime: Millis.of(Clock.now))
    }
}

/// The demo server's settings: each write's answer starts as its recorded fixture and keeps what was sent, so
/// "Private" stays private after the save (the settings pages compare the answer with what they sent).
final class DemoSettings: @unchecked Sendable {
    static let writes = [("PATCH", "settings/prefs"), ("PATCH", "settings/profile"),
                         ("PUT", "settings/privacy/visibility"), ("PUT", "settings/privacy/comments"),
                         ("PUT", "settings/messages")]

    private let lock = NSLock()
    private var answers: [String: JSONValue] = [:]

    /// what the last write of this kind answered (nil before any)
    func written(_ method: String, _ path: String) -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        return answers[method + " " + path]
    }

    private func current(_ method: String, _ path: String) -> JSONValue? {
        if let a = answers[method + " " + path] { return a }
        return Demo.data(Demo.file(path, method: method)).flatMap { try? APIClient.decoder.decode(JSONValue.self, from: $0) }
    }

    /// GET settings/privacy: the visibility and comments answers together
    func privacy() -> JSONValue? {
        lock.lock(); defer { lock.unlock() }
        guard answers["PUT settings/privacy/visibility"] != nil || answers["PUT settings/privacy/comments"] != nil,
              let base = Demo.data(Demo.file("settings/privacy")).flatMap({ try? APIClient.decoder.decode(JSONValue.self, from: $0) })
        else { return nil }
        var out = base.merged(with: answers["PUT settings/privacy/visibility"])
        if let c = answers["PUT settings/privacy/comments"]?["setting"] { out = out.merged(with: .object(["comments": c])) }
        return out
    }

    /// a write: the body laid over the current answer (prefs and profile sit under their own key)
    func write(_ method: String, _ path: String, _ body: Data?) -> JSONValue? {
        guard let body, let sent = try? APIClient.decoder.decode(JSONValue.self, from: body) else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let now = current(method, path) else { return nil }
        let next: JSONValue
        switch path {
        case "settings/prefs": next = now.merged(with: .object(["prefs": sent]))
        case "settings/profile": next = now.merged(with: .object(["profile": sent]))
        case "settings/privacy/visibility":
            // {visibility, media?}: the profile's, or one list's
            guard let v = sent["visibility"] else { return nil }
            if case .string(let media)? = sent["media"] {
                next = now.merged(with: .object(["lists": .object([media: v])]))
            } else {
                next = now.merged(with: .object(["visibility": v]))
            }
        default: next = now.merged(with: sent)
        }
        answers[method + " " + path] = next
        return next
    }
}

/// Answers app API calls from the fixtures in mobile/fixtures/demo/api, so the demo runs the app's real decoding:
///   GET  <path>?<k>=<v>   api/<path>/<v>.json, else api/<path>.json
///   POST <path>           api/<path>.post.json, else {"ok":true}
/// The library (GET library/changes, POST library/write) is a small in-memory server, DemoLibrary.
final class DemoTransport: Transport, @unchecked Sendable {
    typealias Handler = @Sendable (APIRequest) -> (Data, Int)?

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var _requests: [APIRequest] = []
    var offline: Bool
    /// pretend network time (seconds); 0 in tests and screenshots
    var delay: Double
    let library = DemoLibrary()

    init(offline: Bool = false, delay: Double = 0) {
        self.offline = offline
        self.delay = delay
        let library = self.library
        handle("GET", "library/changes") { r in
            let since = r.query.first { $0.name == "since" }?.value
            let limit = r.query.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 200
            guard let feed = library.changes(since: since, limit: limit) else {
                return Self.error(409, "cursor_expired", "That cursor is from before a reset. Read the library again.")
            }
            return Self.json(feed)
        }
        handle("POST", "library/write") { r in
            guard let body = r.body, let batch = try? APIClient.decoder.decode(WriteBatch.self, from: body),
                  (1...100).contains(batch.ops.count) else {
                return Self.error(400, "bad_request", "Send 1 to 100 ops.")
            }
            return Self.json(library.write(batch))
        }
        // settings keep what's written, so an edit sticks for the session like on a server
        let settings = DemoSettings()
        for (method, path) in DemoSettings.writes {
            handle(method, path) { r in settings.write(method, path, r.body).map(Self.json) }
        }
        handle("GET", "settings/privacy") { _ in settings.privacy().map(Self.json) }
        handle("GET", "settings/messages") { _ in settings.written("PUT", "settings/messages").map(Self.json) }
    }

    /// answer one call yourself (tests, special cases)
    func handle(_ method: String, _ path: String, _ h: @escaping Handler) {
        lock.lock(); defer { lock.unlock() }
        handlers[method + " " + path] = h
    }

    /// every call made so far, oldest first
    var requests: [APIRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func send(_ r: APIRequest) async throws -> APIResponse {
        let (data, status) = try await answer(r)
        return APIResponse(data, status)
    }

    private func answer(_ r: APIRequest) async throws -> (Data, Int) {
        let h: Handler? = {
            lock.lock(); defer { lock.unlock() }
            _requests.append(r)
            return handlers[r.method + " " + r.path]
        }()
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        if offline { throw APIError.unreachable("This iPhone is offline.") }
        if let h, let answer = h(r) { return answer }
        if r.method == "GET" {
            if let v = r.query.first?.value, let d = Demo.data(Demo.file(r.path, variant: v)) { return (d, 200) }
            if let d = Demo.data(Demo.file(r.path)) { return (d, 200) }
            return Self.error(404, "not_found", "Nothing here in the demo.")
        }
        if let d = Demo.data(Demo.file(r.path, method: r.method)) { return (d, 200) }
        return (Data(#"{"ok":true}"#.utf8), 200)
    }

    static func json<T: Encodable>(_ v: T) -> (Data, Int) {
        ((try? APIClient.encoder.encode(v)) ?? Data("{}".utf8), 200)
    }

    /// an error answer as the server writes it (§3)
    static func error(_ status: Int, _ code: String, _ message: String) -> (Data, Int) {
        let body = ["error": JSONValue.string(code), "message": .string(message),
                    "serverTime": .number(Double(Millis.of(Clock.now)))]
        return ((try? APIClient.encoder.encode(body)) ?? Data("{}".utf8), status)
    }
}
