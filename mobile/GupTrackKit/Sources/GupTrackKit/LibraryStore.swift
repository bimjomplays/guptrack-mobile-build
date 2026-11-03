import Foundation
import GRDB

/// The offline library (docs/app-api.md §7): the server's copy of your lists and custom lists, read through the
/// change feed, plus the writes made on this iPhone that haven't been answered yet (the outbox). What the app shows
/// is the server copy with the waiting ops on top, in order, so a change shows at once, offline too, and survives
/// a relaunch until the server answers it.
///
/// Tables: `entry` (the server's SyncEntry per title, with its place on the change counter), `list` (your custom
/// lists, whole), `outbox` (waiting ops, oldest first, each with its own request id) and `meta` (the feed cursor).
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
        m.registerMigration("app-api-v1") { db in
            try db.create(table: "entry") { t in
                t.primaryKey("id", .text)           // "anime:5114"
                t.column("rev", .integer).notNull()
                t.column("json", .blob).notNull()   // SyncEntry
            }
            try db.create(table: "list") { t in
                t.primaryKey("id", .integer)
                t.column("rev", .integer).notNull()
                t.column("position", .integer).notNull()
                t.column("json", .blob).notNull()   // FeedList
            }
            try db.create(table: "outbox") { t in
                t.autoIncrementedPrimaryKey("seq")
                t.column("requestId", .text).notNull().unique()
                t.column("titleId", .text).notNull()
                t.column("op", .blob).notNull()     // WriteOp
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

    /// every entry as the app shows it (server copy + waiting ops), most recently changed first
    func entries() throws -> [LibraryEntry] {
        try db.read { db in
            var out: [String: (entry: ListEntry, media: APIMedia, at: Int64)] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT json FROM entry") {
                let s = try Self.decode(SyncEntry.self, row["json"])
                out[s.titleId] = (s.entry, s.media, s.changedAt)
            }
            for item in try Self.outbox(db) {
                let id = item.titleId
                if let e = item.op.applied(to: out[id]?.entry) {
                    out[id] = (e, item.op.media, max(out[id]?.at ?? 0, item.op.at))
                } else {
                    out[id] = nil
                }
            }
            return out.values.map { $0.entry.library($0.media, updatedAt: Millis.date($0.at)) }
                .sorted { ($0.updatedAt, $0.id) > ($1.updatedAt, $1.id) }
        }
    }

    func entry(_ titleId: String) throws -> LibraryEntry? {
        guard let key = TitleKey(titleId: titleId) else { return nil }
        return try db.read { db in
            let base = try Self.base(db, key.titleId)
            var e = base?.entry
            var at = base?.changedAt ?? 0
            for item in try Self.outbox(db, titleId: key.titleId) {
                e = item.op.applied(to: e)
                at = max(at, item.op.at)
            }
            return e?.library(key.media, updatedAt: Millis.date(at))
        }
    }

    /// the entry in the API's shape as it shows now (server copy + waiting ops)
    func listEntry(_ titleId: String) throws -> ListEntry? {
        guard let key = TitleKey(titleId: titleId) else { return nil }
        return try db.read { db in
            var e = try Self.base(db, key.titleId)?.entry
            for item in try Self.outbox(db, titleId: key.titleId) { e = item.op.applied(to: e) }
            return e
        }
    }

    /// the server's copy alone (no waiting ops)
    func serverEntry(_ titleId: String) throws -> SyncEntry? {
        guard let key = TitleKey(titleId: titleId) else { return nil }
        return try db.read { try Self.base($0, key.titleId) }
    }

    /// your custom lists, in your order
    func lists() throws -> [FeedList] {
        try db.read { db in
            try Data.fetchAll(db, sql: "SELECT json FROM list ORDER BY position, id").map { try Self.decode(FeedList.self, $0) }
        }
    }

    /// the last cursor read to (nil: never synced, or the copy was thrown away)
    var cursor: String? {
        get throws { try db.read { try String.fetchOne($0, sql: "SELECT value FROM meta WHERE key = 'cursor'") } }
    }

    // MARK: the outbox

    struct Pending: Equatable, Sendable {
        var seq: Int64
        var op: WriteOp
        var createdAt: Date
        var attempts: Int
        var lastError: String?
        /// the title's name, for messages about it
        var name: String?

        var requestId: String { op.requestId }
        var titleId: String { op.titleId }
    }

    /// Records an edit made on this iPhone as outbox ops and returns the entry as it now shows (nil when it isn't
    /// on the list). `title` is needed when the title isn't on the list yet.
    @discardableResult
    func change(_ titleId: String, _ patch: LibraryPatch, title: Title? = nil, at now: Date = Clock.now,
                newId: () -> String = { UUID().uuidString }) throws -> LibraryEntry? {
        guard !patch.isEmpty, let key = TitleKey(titleId: titleId) else { return try entry(titleId) }
        let ops = WriteOp.ops(for: patch, key: key, current: try listEntry(key.titleId), title: title,
                              at: Millis.of(now), newId: newId)
        try enqueue(ops)
        return try entry(key.titleId)
    }

    /// adds ops to the outbox, in order
    func enqueue(_ ops: [WriteOp]) throws {
        guard !ops.isEmpty else { return }
        try db.write { db in
            for op in ops {
                try db.execute(sql: "INSERT INTO outbox (requestId, titleId, op, createdAt) VALUES (?, ?, ?, ?)",
                               arguments: [op.requestId, op.titleId, try Self.encode(op),
                                           Millis.date(op.at).timeIntervalSince1970])
            }
        }
    }

    func pending() throws -> [Pending] { try db.read { try Self.outbox($0) } }

    var pendingCount: Int {
        get throws { try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") ?? 0 } }
    }

    /// a send that got no usable answer: the ops stay, with the reason
    func noteFailure(_ requestIds: [String], _ why: String) throws {
        try db.write { db in
            for id in requestIds {
                try db.execute(sql: "UPDATE outbox SET attempts = attempts + 1, lastError = ? WHERE requestId = ?",
                               arguments: [why, id])
            }
        }
    }

    /// What came back for sent ops.
    struct Answered: Equatable, Sendable {
        /// applied, or not applied for a reason the server decided (stale and the rest)
        var settled: [Pending] = []
        /// not applied for a reason the user may want to hear (not_on_list, not_completed, already_rewatching)
        var refused: [(Pending, String)] = []
        /// the op was wrong (`error`, `message`): dropped, nothing written
        var rejected: [Pending] = []

        static func == (a: Self, b: Self) -> Bool {
            a.settled == b.settled && a.rejected == b.rejected
                && a.refused.map(\.0) == b.refused.map(\.0) && a.refused.map(\.1) == b.refused.map(\.1)
        }
    }

    /// The server's results for sent ops (§7.2). An op leaves the outbox only once its result is here. The result's
    /// entry becomes the server copy (unless the feed already brought a newer one); none means it isn't on the list.
    @discardableResult
    func acknowledge(_ results: [WriteResult]) throws -> Answered {
        try db.write { db in
            var out = Answered()
            for r in results {
                guard var item = try Self.outbox(db, requestId: r.requestId) else { continue }
                try db.execute(sql: "DELETE FROM outbox WHERE requestId = ?", arguments: [r.requestId])
                if let error = r.error {
                    item.lastError = r.message ?? error
                    out.rejected.append(item)
                    continue
                }
                if let e = r.entry {
                    try Self.upsert(db, e)
                } else {
                    // removed, or never on the list (a stale op on a removed title too)
                    try db.execute(sql: "DELETE FROM entry WHERE id = ?", arguments: [item.titleId])
                }
                if !r.applied, let reason = r.reason, reason != "stale" {
                    out.refused.append((item, reason))
                } else {
                    out.settled.append(item)
                }
            }
            return out
        }
    }

    // MARK: the change feed

    /// Writes one page of the change feed (§7.1): upserts entries by title (an older place on the counter than the
    /// one kept is ignored), deletes removed titles, replaces changed lists whole, deletes removed lists, and keeps
    /// the new cursor after the page is in.
    func applyFeed(_ page: ChangeFeed) throws {
        try db.write { db in
            for r in page.removed {
                try db.execute(sql: "DELETE FROM entry WHERE id = ?", arguments: [r.titleId])
            }
            for e in page.entries { try Self.upsert(db, e) }
            for l in page.lists.removed {
                try db.execute(sql: "DELETE FROM list WHERE id = ?", arguments: [l.id])
            }
            for l in page.lists.changed {
                try db.execute(sql: """
                    INSERT INTO list (id, rev, position, json) VALUES (?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET rev = excluded.rev, position = excluded.position, json = excluded.json
                    WHERE excluded.rev >= list.rev
                    """, arguments: [l.list.id, l.rev, l.position, try Self.encode(l)])
            }
            try Self.setMeta(db, "cursor", page.cursor)
        }
    }

    /// 409 cursor_expired: the server's database was replaced. Throw the server copy away and keep the outbox; the
    /// next read starts from the beginning.
    func forgetServerCopy() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM entry; DELETE FROM list; DELETE FROM meta WHERE key = 'cursor'")
        }
    }

    /// forget everything (signing out)
    func wipe() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM entry; DELETE FROM list; DELETE FROM outbox; DELETE FROM meta")
        }
    }

    // MARK: helpers

    private static func outbox(_ db: Database, titleId: String? = nil) throws -> [Pending] {
        let rows = try titleId.map {
            try Row.fetchAll(db, sql: "SELECT * FROM outbox WHERE titleId = ? ORDER BY seq", arguments: [$0])
        } ?? Row.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY seq")
        return try rows.map { try pending(db, $0) }
    }

    private static func outbox(_ db: Database, requestId: String) throws -> Pending? {
        try Row.fetchOne(db, sql: "SELECT * FROM outbox WHERE requestId = ?", arguments: [requestId]).map { try pending(db, $0) }
    }

    private static func pending(_ db: Database, _ row: Row) throws -> Pending {
        let op = try decode(WriteOp.self, row["op"])
        let name = try op.meta?.title ?? base(db, op.titleId)?.entry.title ?? op.entry?["title"]?.string
        return Pending(seq: row["seq"], op: op, createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                       attempts: row["attempts"], lastError: row["lastError"], name: name)
    }

    private static func base(_ db: Database, _ id: String) throws -> SyncEntry? {
        try Data.fetchOne(db, sql: "SELECT json FROM entry WHERE id = ?", arguments: [id]).map { try decode(SyncEntry.self, $0) }
    }

    private static func upsert(_ db: Database, _ e: SyncEntry) throws {
        try db.execute(sql: """
            INSERT INTO entry (id, rev, json) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET rev = excluded.rev, json = excluded.json WHERE excluded.rev >= entry.rev
            """, arguments: [e.titleId, e.rev, try encode(e)])
    }

    private static func setMeta(_ db: Database, _ key: String, _ value: String) throws {
        try db.execute(sql: "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       arguments: [key, value])
    }

    private static func encode<T: Encodable>(_ v: T) throws -> Data { try APIClient.encoder.encode(v) }
    private static func decode<T: Decodable>(_ t: T.Type, _ d: Data) throws -> T { try APIClient.decoder.decode(t, from: d) }
}

/// Brings the offline library and the server together: sends the outbox (oldest first, up to 100 ops a call), then
/// reads the change feed until it's caught up. A 409 cursor_expired throws the server copy away (the outbox stays)
/// and reads from the start.
final class LibrarySync: @unchecked Sendable {
    let api: APIClient
    let store: LibraryStore
    let batch: Int

    init(api: APIClient, store: LibraryStore, batch: Int = 100) {
        self.api = api
        self.store = store
        self.batch = min(100, max(1, batch))
    }

    struct Report: Equatable, Sendable {
        var sent = 0
        var answered = LibraryStore.Answered()
        var received = 0
        var pages = 0
        var restarted = false

        var rejected: [LibraryStore.Pending] { answered.rejected }
    }

    func run() async throws -> Report {
        var report = Report()
        try await send(&report)
        try await receive(&report)
        return report
    }

    private func send(_ report: inout Report) async throws {
        while true {
            let items = Array(try store.pending().prefix(batch))
            guard !items.isEmpty else { return }
            do {
                let answer = try await api.writeLibrary(WriteBatch(ops: items.map(\.op)))
                let got = Set(answer.results.map(\.requestId))
                let a = try store.acknowledge(answer.results)
                report.answered.settled += a.settled
                report.answered.refused += a.refused
                report.answered.rejected += a.rejected
                report.sent += answer.results.count
                // an op the server didn't answer stays; stop rather than loop on it
                let missing = items.map(\.requestId).filter { !got.contains($0) }
                if !missing.isEmpty {
                    try store.noteFailure(missing, "GupTrack didn't answer this change.")
                    return
                }
            } catch let e as APIError {
                // 401, 429, 5xx, no answer, or a 400 for the whole call: the ops stay and go again later
                try store.noteFailure(items.map(\.requestId), e.message)
                throw e
            }
        }
    }

    private func receive(_ report: inout Report) async throws {
        var cursor = try store.cursor
        for _ in 0..<10_000 {
            let page: ChangeFeed
            do {
                page = try await api.libraryChanges(since: cursor)
            } catch let e as APIError where e.code == "cursor_expired" && !report.restarted {
                try store.forgetServerCopy()
                report.restarted = true
                cursor = nil
                continue
            }
            try store.applyFeed(page)
            report.received += page.entries.count + page.removed.count
            report.pages += 1
            cursor = page.cursor
            if !page.more { break }
        }
    }
}
