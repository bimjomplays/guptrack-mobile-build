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
        guard let d = data(relative) else { throw APIError.server(404, "No demo data at \(relative).") }
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

    /// the demo user, signed in
    static func account() -> ServerAccount {
        let me = (try? load(UserRef.self, "api/me.json"))
            ?? UserRef(username: "demo", name: "Demo", avatar: nil)
        return ServerAccount(baseURL: server, token: "demo-token", deviceId: "demo-device", user: me,
                             signedInAt: Clock.demoNow)
    }
}

/// Answers app API calls from the fixtures in mobile/fixtures/demo/api, so the demo runs the app's real decoding:
///   GET  <path>?<k>=<v>   api/<path>/<v>.json, else api/<path>.json
///   POST <path>           api/<path>.post.json, else {"ok":true}
/// The library sync is answered from api/library.json (a full copy on the first pull, then nothing new), and sent
/// changes are all accepted.
final class DemoTransport: Transport, @unchecked Sendable {
    typealias Handler = @Sendable (APIRequest) -> (Data, Int)?

    private let lock = NSLock()
    private var handlers: [String: Handler] = [:]
    private var _requests: [APIRequest] = []
    var offline: Bool
    /// pretend network time (seconds); 0 in tests and screenshots
    var delay: Double

    init(offline: Bool = false, delay: Double = 0) {
        self.offline = offline
        self.delay = delay
        handle("GET", "library/changes") { r in
            let since = r.query.first { $0.name == "since" }?.value
            if since == DemoTransport.cursor { return Self.json(ChangePage(changes: [], cursor: DemoTransport.cursor, more: false, reset: false)) }
            let entries = (try? Demo.load([LibraryEntry].self, "api/library.json")) ?? []
            let changes = entries.map { FeedChange(titleId: $0.id, revision: 1, entry: $0) }
            return Self.json(ChangePage(changes: changes, cursor: DemoTransport.cursor, more: false, reset: true))
        }
        handle("POST", "library/changes") { r in
            guard let body = r.body, let batch = try? APIClient.decoder.decode(ChangeBatch.self, from: body) else {
                return (Data(#"{"error":"Not a change batch."}"#.utf8), 400)
            }
            return Self.json(ChangeBatchReply(results: batch.changes.map {
                ChangeResult(requestId: $0.requestId, ok: true, revision: 2, entry: nil, error: nil)
            }))
        }
    }

    static let cursor = "demo-1"

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

    func send(_ r: APIRequest) async throws -> (Data, Int) {
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
            return (Data(#"{"error":"Nothing here in the demo."}"#.utf8), 404)
        }
        if let d = Demo.data(Demo.file(r.path, method: r.method)) { return (d, 200) }
        return (Data(#"{"ok":true}"#.utf8), 200)
    }

    static func json<T: Encodable>(_ v: T) -> (Data, Int) {
        ((try? APIClient.encoder.encode(v)) ?? Data("{}".utf8), 200)
    }
}
