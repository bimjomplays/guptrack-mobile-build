import Foundation

// The app API's own shapes for the library (docs/app-api.md §2, §7), field for field as the website's TypeScript
// types (src/library/types.ts, src/lists/types.ts). The screens use the app's models (Models.swift); these map to
// them. Times are ms since 1970 (Int64); the dates a user picks ("2026-10-04") stay strings.

/// A list's media as the API names it: plural (`movies`, `books`). A title page's `kind` is singular (MediaKind).
enum APIMedia: String, Codable, CaseIterable, Hashable, Sendable {
    case anime, manga, tv, movies, books

    init(_ kind: MediaKind) {
        switch kind {
        case .anime: self = .anime
        case .manga: self = .manga
        case .tv: self = .tv
        case .movie: self = .movies
        case .book: self = .books
        }
    }

    var kind: MediaKind {
        switch self {
        case .anime: return .anime
        case .manga: return .manga
        case .tv: return .tv
        case .movies: return .movie
        case .books: return .book
        }
    }
}

extension MediaKind {
    /// the API's plural name ("movies")
    var api: APIMedia { APIMedia(self) }
}

/// A list status as the website keeps it. Rewatching is `current` with `rewatch` set.
enum EntryStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case current, completed, hold, dropped, planned
}

/// The Completed state a rewatch started from (`Rewatch`, src/library/types.ts).
struct Rewatch: Codable, Hashable, Sendable {
    var progress: Int
    var started: String?
    var finished: String?
}

/// One entry on a list (`ListEntry`, src/library/types.ts).
struct ListEntry: Codable, Hashable, Sendable {
    /// the title's id at its source ("16498", "1399", "OL45804W")
    var id: String
    var title: String
    var alt: [String]
    /// "" = none
    var cover: String
    var format: String
    var status: EntryStatus
    var progress: Int
    var total: Int?
    /// 1–100
    var score: Int?
    /// one episode's length (a film's full length); 0 for reading lists
    var minutes: Int
    /// days since it last changed (fractions are hours)
    var updated: Double
    /// a film's place, seconds in
    var position: Double
    var volumes: Int?
    var readVolumes: Int
    var repeats: Int
    var rewatch: Rewatch?
    var started: String?
    var finished: String?
    var notes: String
    var favourite: Bool
    var idMal: Int?
    /// when it was added (ms); 0 = not saved yet
    var added: Int64

    init(id: String, title: String, alt: [String] = [], cover: String = "", format: String = "",
         status: EntryStatus, progress: Int = 0, total: Int? = nil, score: Int? = nil, minutes: Int = 0,
         updated: Double = 0, position: Double = 0, volumes: Int? = nil, readVolumes: Int = 0, repeats: Int = 0,
         rewatch: Rewatch? = nil, started: String? = nil, finished: String? = nil, notes: String = "",
         favourite: Bool = false, idMal: Int? = nil, added: Int64 = 0) {
        self.id = id
        self.title = title
        self.alt = alt
        self.cover = cover
        self.format = format
        self.status = status
        self.progress = progress
        self.total = total
        self.score = score
        self.minutes = minutes
        self.updated = updated
        self.position = position
        self.volumes = volumes
        self.readVolumes = readVolumes
        self.repeats = repeats
        self.rewatch = rewatch
        self.started = started
        self.finished = finished
        self.notes = notes
        self.favourite = favourite
        self.idMal = idMal
        self.added = added
    }

    // `started`, `finished`, `rewatch`, `total`, `score` and `idMal` are sent as null, as the website does
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(alt, forKey: .alt)
        try c.encode(cover, forKey: .cover)
        try c.encode(format, forKey: .format)
        try c.encode(status, forKey: .status)
        try c.encode(progress, forKey: .progress)
        try c.encode(total, forKey: .total)
        try c.encode(score, forKey: .score)
        try c.encode(minutes, forKey: .minutes)
        try c.encode(updated, forKey: .updated)
        try c.encode(position, forKey: .position)
        try c.encodeIfPresent(volumes, forKey: .volumes)
        try c.encode(readVolumes, forKey: .readVolumes)
        try c.encode(repeats, forKey: .repeats)
        try c.encode(rewatch, forKey: .rewatch)
        try c.encode(started, forKey: .started)
        try c.encode(finished, forKey: .finished)
        try c.encode(notes, forKey: .notes)
        try c.encode(favourite, forKey: .favourite)
        try c.encode(idMal, forKey: .idMal)
        try c.encode(added, forKey: .added)
    }
}

/// What Browse and calendars show on a cover that is on your list (`Mark`, src/library/types.ts).
struct Mark: Codable, Hashable, Sendable {
    var status: EntryStatus
    var score: Int?
    var rewatching: Bool?
}

/// One entry as the change feed and the outbox's results send it (`SyncEntry`, src/library/db.server.ts).
struct SyncEntry: Codable, Hashable, Sendable {
    var media: APIMedia
    var entry: ListEntry
    var statusAt: Int64
    var progressAt: Int64
    var scoreAt: Int64
    var changedAt: Int64
    var rev: Int

    /// the app's id for the title ("movie:603")
    var titleId: String { TitleKey(media: media, id: entry.id).titleId }
}

/// A title as the API names it (media + source id) and as the app does ("<kind>:<id>").
struct TitleKey: Hashable, Sendable {
    var media: APIMedia
    var id: String

    var titleId: String { "\(media.kind.rawValue):\(id)" }

    init(media: APIMedia, id: String) {
        self.media = media
        self.id = id
    }

    /// "anime:5114", "movie:603" (also "movies:603")
    init?(titleId: String) {
        guard let i = titleId.firstIndex(of: ":") else { return nil }
        let kind = String(titleId[..<i]), id = String(titleId[titleId.index(after: i)...])
        guard !id.isEmpty else { return nil }
        if let k = MediaKind(rawValue: kind) { media = k.api } else if let m = APIMedia(rawValue: kind) { media = m } else { return nil }
        self.id = id
    }
}

// MARK: the change feed (§7.1)

/// GET library/changes?since=<cursor>&limit=<1–500>: what changed after the cursor, oldest first.
struct ChangeFeed: Codable, Hashable, Sendable {
    struct Removed: Codable, Hashable, Sendable {
        var media: APIMedia
        var id: String
        var removedAt: Int64

        var titleId: String { TitleKey(media: media, id: id).titleId }
    }

    struct ListRemoved: Codable, Hashable, Sendable {
        var id: Int
        var removedAt: Int64
    }

    struct Lists: Codable, Hashable, Sendable {
        var changed: [FeedList]
        var removed: [ListRemoved]
    }

    var entries: [SyncEntry]
    var removed: [Removed]
    var lists: Lists
    /// "<epoch>.<n>"
    var cursor: String
    var more: Bool
    var serverTime: Int64
}

// MARK: custom lists (src/lists/types.ts), as the feed and §9 send them

/// Who may see something (`Visibility`, src/social/types.ts).
enum WireVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case `private`, friends, `public`

    var visibility: Visibility {
        switch self {
        case .private: return .private
        case .friends: return .friends
        case .public: return .public
        }
    }
}

/// A list's own setting and the profile's, which caps it (`ListLevel`).
struct ListLevel: Codable, Hashable, Sendable {
    var list: WireVisibility
    var profile: WireVisibility
}

/// A title on a custom list (`ListItem` = `ListTitle` + note, added, mine).
struct ListItem: Codable, Hashable, Sendable {
    var media: APIMedia
    var id: String
    var title: String
    var cover: String?
    var format: String
    var year: Int?
    var note: String
    var added: Int64
    /// the viewer's own status for it when read
    var mine: EntryStatus?

    var titleId: String { TitleKey(media: media, id: id).titleId }
}

/// One of your lists, whole (`MyList` = `MyListSummary` + items).
struct MyList: Codable, Hashable, Sendable {
    var id: Int
    var slug: String
    var name: String
    var description: String
    var count: Int
    var covers: [String?]
    var media: [APIMedia]
    var updated: Int64
    var level: ListLevel
    var items: [ListItem]
}

/// A list as the change feed sends it: MyList + its place among your lists + its place on the change counter.
struct FeedList: Codable, Hashable, Sendable {
    var list: MyList
    var position: Int
    var rev: Int

    init(list: MyList, position: Int, rev: Int) {
        self.list = list
        self.position = position
        self.rev = rev
    }

    private enum Extra: String, CodingKey { case position, rev }

    init(from decoder: Decoder) throws {
        list = try MyList(from: decoder)
        let c = try decoder.container(keyedBy: Extra.self)
        position = try c.decode(Int.self, forKey: .position)
        rev = try c.decode(Int.self, forKey: .rev)
    }

    func encode(to encoder: Encoder) throws {
        try list.encode(to: encoder)
        var c = encoder.container(keyedBy: Extra.self)
        try c.encode(position, forKey: .position)
        try c.encode(rev, forKey: .rev)
    }
}

// MARK: the outbox (§7.2)

/// What a title brings when an op adds it to a list (`meta`).
struct TitleMeta: Codable, Hashable, Sendable {
    var title: String
    var alt: [String]?
    /// https only
    var cover: String?
    var format: String?
    var total: Int?
    var volumes: Int?
    var minutes: Int?
    var idMal: Int?
}

/// One write made on the phone, kept until its result comes back. `requestId` is a UUID per op; `at` is when
/// the user made it (ms, the phone's clock).
struct WriteOp: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case status, progress, score, edit, favourite, rewatch, remove
    }

    var requestId: String
    var op: Kind
    var media: APIMedia
    var id: String
    var at: Int64
    var status: EntryStatus?
    var progress: Int?
    var position: Double?
    /// for `score`: 1–100, nil sends null (no score)
    var score: Int?
    /// for `edit`: the ListEntry fields to set (null clears)
    var entry: [String: JSONValue]?
    var favourite: Bool?
    var meta: TitleMeta?

    init(requestId: String = UUID().uuidString, op: Kind, media: APIMedia, id: String, at: Int64,
         status: EntryStatus? = nil, progress: Int? = nil, position: Double? = nil, score: Int? = nil,
         entry: [String: JSONValue]? = nil, favourite: Bool? = nil, meta: TitleMeta? = nil) {
        self.requestId = requestId
        self.op = op
        self.media = media
        self.id = id
        self.at = at
        self.status = status
        self.progress = progress
        self.position = position
        self.score = score
        self.entry = entry
        self.favourite = favourite
        self.meta = meta
    }

    var titleId: String { TitleKey(media: media, id: id).titleId }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(requestId, forKey: .requestId)
        try c.encode(op, forKey: .op)
        try c.encode(media, forKey: .media)
        try c.encode(id, forKey: .id)
        try c.encode(at, forKey: .at)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(progress, forKey: .progress)
        try c.encodeIfPresent(position, forKey: .position)
        if op == .score { try c.encode(score, forKey: .score) } else { try c.encodeIfPresent(score, forKey: .score) }
        try c.encodeIfPresent(entry, forKey: .entry)
        try c.encodeIfPresent(favourite, forKey: .favourite)
        try c.encodeIfPresent(meta, forKey: .meta)
    }
}

/// POST library/write
struct WriteBatch: Codable, Hashable, Sendable {
    var ops: [WriteOp]
}

/// One op's result: applied, not applied for a `reason` (final), or an `error` (that op was wrong).
struct WriteResult: Codable, Hashable, Sendable {
    var requestId: String
    var applied: Bool
    /// stale, not_on_list, not_completed, already_rewatching
    var reason: String?
    var media: APIMedia?
    var id: String?
    /// the entry now; nil when it isn't on the list
    var entry: SyncEntry?
    var removed: Bool?
    var error: String?
    var message: String?
}

struct WriteAnswer: Codable, Hashable, Sendable {
    var results: [WriteResult]
    var cursor: String
    var serverTime: Int64
}

// MARK: any JSON

/// A JSON value, for the few bodies whose fields vary (an edit op's `entry`).
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null } else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    static func int(_ v: Int?) -> JSONValue { v.map { .number(Double($0)) } ?? .null }
    static func text(_ v: String?) -> JSONValue { v.map { .string($0) } ?? .null }

    var int: Int? { if case .number(let n) = self { return Int(n) } else { return nil } }
    var double: Double? { if case .number(let n) = self { return n } else { return nil } }
    var string: String? { if case .string(let s) = self { return s } else { return nil } }
    var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var isNull: Bool { self == .null }
}

// MARK: times

enum Millis {
    static func of(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
    static func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }
}
