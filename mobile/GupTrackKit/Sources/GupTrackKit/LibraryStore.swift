import Foundation
import GRDB

/// The offline library: the server's copy of your list (from the change feed) plus the edits made on this iPhone
/// that haven't reached the server yet (the outbox). What the app shows is the server copy with the pending edits
/// applied in order, so a change shows at once, offline too, and survives a relaunch until the server takes it.
///
/// Tables: `entry` (the server's copy, one row per title, with its revision), `outbox` (pending edits, oldest
/// first, each with a request id the server applies once) and `meta` (the feed cursor).
final class LibraryStore: @unchecked Sendable {
    private let db: DatabaseQueue

    /// `path` nil keeps it in memory (the demo and tests).
    init(path: String? = nil) throws {
        if let path {
            db = try DatabaseQueue(path: path)
        } else {
            db = try DatabaseQueue()
        }
        try Self.migrator.migrate(db)
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "entry") { t in
                t.primaryKey("id", .text)
                t.column("revision", .integer).notNull()
                t.column("json", .blob).notNull()
                // which full copy (reset) last wrote it; rows an unfinished reset didn't touch are removed at its end
                t.column("gen", .integer).notNull().defaults(to: 0)
            }
            try db.create(table: "outbox") { t in
                t.autoIncrementedPrimaryKey("seq")
                t.column("requestId", .text).notNull().unique()
                t.column("titleId", .text).notNull()
                t.column("patch", .blob).notNull()
                t.column("title", .blob)
                t.column("createdAt", .double).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("lastError", .text)
            }
            try db.create(table: "meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        return m
    }

    // MARK: reading

    /// every entry as the app shows it (server copy + pending edits), most recently updated first
    func entries() throws -> [LibraryEntry] {
        try db.read { db in
            var out: [String: LibraryEntry] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, json FROM entry") {
                out[row["id"]] = try Self.decode(LibraryEntry.self, row["json"])
            }
            for item in try Self.outbox(db) {
                out[item.titleId] = Self.fold(out[item.titleId], item)
            }
            return out.values.sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
        }
    }

    func entry(_ titleId: String) throws -> LibraryEntry? {
        try db.read { db in
            var e = try Data.fetchOne(db, sql: "SELECT json FROM entry WHERE id = ?", arguments: [titleId])
                .map { try Self.decode(LibraryEntry.self, $0) }
            for item in try Self.outbox(db, titleId: titleId) { e = Self.fold(e, item) }
            return e
        }
    }

    /// the server's copy alone (no pending edits)
    func serverEntry(_ titleId: String) throws -> LibraryEntry? {
        try db.read { db in
            try Data.fetchOne(db, sql: "SELECT json FROM entry WHERE id = ?", arguments: [titleId])
                .map { try Self.decode(LibraryEntry.self, $0) }
        }
    }

    var cursor: String? {
        get throws { try db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'cursor'") } }
    }

    // MARK: the outbox

    struct Pending: Equatable, Sendable {
        var seq: Int64
        var requestId: String
        var titleId: String
        var patch: LibraryPatch
        var title: Title?
        var createdAt: Date
        var attempts: Int
        var lastError: String?

        var outgoing: OutgoingChange { OutgoingChange(requestId: requestId, titleId: titleId, patch: patch, title: title) }
    }

    /// Records an edit made on this iPhone and returns the entry as it now shows (nil when it left the list).
    /// `title` is needed when the title isn't on the list yet.
    @discardableResult
    func change(_ titleId: String, _ patch: LibraryPatch, title: Title? = nil, requestId: String = UUID().uuidString,
                at now: Date = Clock.now) throws -> LibraryEntry? {
        guard !patch.isEmpty else { return try entry(titleId) }
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO outbox (requestId, titleId, patch, title, createdAt) VALUES (?, ?, ?, ?, ?)
                """, arguments: [requestId, titleId, try Self.encode(patch), try title.map(Self.encode),
                                 now.timeIntervalSince1970])
        }
        return try entry(titleId)
    }

    func pending() throws -> [Pending] { try db.read { try Self.outbox($0) } }

    var pendingCount: Int {
        get throws { try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") ?? 0 } }
    }

    /// a send that didn't get an answer: the edits stay queued with the reason
    func noteFailure(_ requestIds: [String], _ why: String) throws {
        try db.write { db in
            for id in requestIds {
                try db.execute(sql: "UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE requestId = ?",
                               arguments: [why, id])
            }
        }
    }

    /// The server's answers to sent edits. An applied edit leaves the outbox and its result becomes the server
    /// copy (the entry the server sent, or the edit folded into the old copy when it sent none). A rejected edit
    /// is dropped (the server said no, retrying won't change that); those come back so the app can say so.
    @discardableResult
    func acknowledge(_ results: [ChangeResult], at now: Date = Clock.now) throws -> [Pending] {
        try db.write { db in
            var rejected: [Pending] = []
            for r in results {
                guard let item = try Self.outbox(db, requestId: r.requestId) else { continue }
                try db.execute(sql: "DELETE FROM outbox WHERE requestId = ?", arguments: [r.requestId])
                guard r.ok else {
                    var p = item
                    p.lastError = r.error
                    rejected.append(p)
                    continue
                }
                let old = try Self.base(db, item.titleId)
                let revision = r.revision ?? (old?.revision ?? 0)
                if let old, revision < old.revision { continue }   // the feed already brought something newer
                if let e = r.entry {
                    try Self.put(db, e, revision: revision)
                } else if let e = Self.fold(old?.entry, item, at: now) {
                    try Self.put(db, e, revision: revision)
                } else {
                    try db.execute(sql: "DELETE FROM entry WHERE id = ?", arguments: [item.titleId])
                }
            }
            return rejected
        }
    }

    // MARK: the change feed

    /// Writes a page of the server's change feed. A page with `reset` starts a full copy: when its last page
    /// (more == false) is in, titles the copy didn't include are removed. Older revisions than the stored one
    /// are ignored, so a page arriving late can't undo a newer acknowledgement.
    func applyFeed(_ page: ChangePage) throws {
        try db.write { db in
            var gen = Int(try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'gen'") ?? "0") ?? 0
            var resetting = try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'resetting'") == "1"
            if page.reset {
                gen += 1
                resetting = true
            }
            for c in page.changes {
                let old = try Self.base(db, c.titleId)
                if !page.reset && !resetting, let old, c.revision < old.revision { continue }
                if let e = c.entry {
                    try Self.put(db, e, revision: c.revision, gen: gen)
                } else {
                    try db.execute(sql: "DELETE FROM entry WHERE id = ?", arguments: [c.titleId])
                }
            }
            if resetting && !page.more {
                try db.execute(sql: "DELETE FROM entry WHERE gen < ?", arguments: [gen])
                resetting = false
            }
            try Self.setMeta(db, "gen", String(gen))
            try Self.setMeta(db, "resetting", resetting ? "1" : "0")
            try Self.setMeta(db, "cursor", page.cursor)
        }
    }

    /// forget everything (signing out)
    func wipe() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM entry; DELETE FROM outbox; DELETE FROM meta")
        }
    }

    // MARK: helpers

    private static func outbox(_ db: Database, titleId: String? = nil) throws -> [Pending] {
        let rows = try titleId.map {
            try Row.fetchAll(db, sql: "SELECT * FROM outbox WHERE titleId = ? ORDER BY seq", arguments: [$0])
        } ?? Row.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY seq")
        return try rows.map(pending)
    }

    private static func outbox(_ db: Database, requestId: String) throws -> Pending? {
        try Row.fetchOne(db, sql: "SELECT * FROM outbox WHERE requestId = ?", arguments: [requestId]).map(pending)
    }

    private static func pending(_ row: Row) throws -> Pending {
        Pending(seq: row["seq"], requestId: row["requestId"], titleId: row["titleId"],
                patch: try decode(LibraryPatch.self, row["patch"]),
                title: try (row["title"] as Data?).map { try decode(Title.self, $0) },
                createdAt: Date(timeIntervalSince1970: row["createdAt"]), attempts: row["attempts"],
                lastError: row["lastError"])
    }

    private static func base(_ db: Database, _ id: String) throws -> (entry: LibraryEntry, revision: Int)? {
        guard let row = try Row.fetchOne(db, sql: "SELECT json, revision FROM entry WHERE id = ?", arguments: [id])
        else { return nil }
        return (try decode(LibraryEntry.self, row["json"]), row["revision"])
    }

    private static func put(_ db: Database, _ e: LibraryEntry, revision: Int, gen: Int? = nil) throws {
        let g: Int
        if let gen { g = gen } else {
            g = Int(try String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'gen'") ?? "0") ?? 0
        }
        try db.execute(sql: """
            INSERT INTO entry (id, revision, json, gen) VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET revision = excluded.revision, json = excluded.json, gen = excluded.gen
            """, arguments: [e.id, revision, try encode(e), g])
    }

    private static func setMeta(_ db: Database, _ key: String, _ value: String) throws {
        try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       arguments: [key, value])
    }

    /// one pending edit on top of an entry (nil: not on the list)
    private static func fold(_ e: LibraryEntry?, _ item: Pending, at now: Date? = nil) -> LibraryEntry? {
        if item.patch.remove == true { return nil }
        let when = now ?? item.createdAt
        if let e { return e.applying(item.patch, at: when) }
        guard let title = item.title else { return nil }
        return LibraryEntry.new(title, item.patch, at: when)
    }

    private static func encode<T: Encodable>(_ v: T) throws -> Data { try APIClient.encoder.encode(v) }
    private static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { try APIClient.decoder.decode(t, from: d) }
}

/// Brings the offline library and the server together: sends the outbox (oldest first, in batches), then reads the
/// change feed until it's caught up.
final class LibrarySync: @unchecked Sendable {
    let api: APIClient
    let store: LibraryStore
    let batch: Int

    init(api: APIClient, store: LibraryStore, batch: Int = 50) {
        self.api = api
        self.store = store
        self.batch = batch
    }

    struct Report: Equatable, Sendable {
        var sent = 0
        var rejected: [LibraryStore.Pending] = []
        var received = 0
        var pages = 0
    }

    func run() async throws -> Report {
        var report = Report()
        // send
        while true {
            let items = Array(try store.pending().prefix(batch))
            guard !items.isEmpty else { break }
            do {
                let reply = try await api.pushChanges(ChangeBatch(changes: items.map(\.outgoing)))
                let answered = Set(reply.results.map(\.requestId))
                report.rejected += try store.acknowledge(reply.results)
                report.sent += reply.results.filter(\.ok).count
                // anything the server didn't answer stays queued; stop rather than loop on it
                if items.contains(where: { !answered.contains($0.requestId) }) {
                    try store.noteFailure(items.map(\.requestId).filter { !answered.contains($0) },
                                          "The server didn't answer this change.")
                    break
                }
            } catch let e as APIError {
                try store.noteFailure(items.map(\.requestId), e.message)
                throw e
            }
        }
        // receive
        var cursor = try store.cursor
        for _ in 0..<1000 {
            let page = try await api.libraryChanges(since: cursor)
            try store.applyFeed(page)
            report.received += page.changes.count
            report.pages += 1
            cursor = page.cursor
            if !page.more { break }
        }
        return report
    }
}
