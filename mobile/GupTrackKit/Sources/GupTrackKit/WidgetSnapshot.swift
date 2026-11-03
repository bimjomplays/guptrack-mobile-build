import Foundation

// What the Home Screen and Lock Screen widgets show (65, 65b), worked out from the library. Plain Foundation: the
// widget extension compiles this file (with Models, Format and Route), and so do the app and the Linux tests. The
// extension has no AppModel or APIClient: it gets the library as a list of entries.
//
// Demo: the extensions bundle api/library/changes.json and api/extensions.json (with home/live's `upcoming`) and build
// the snapshot themselves; a widget's
// +1 is kept in the extension's own WidgetOutbox. The real app would write the library (or this snapshot) into an
// App Group the widgets read, and the +1s into the App Group's outbox for the app to sync.

/// A picture address from an answer, kept as the server wrote it: catalogue covers are https URLs, GupTrack's own
/// ("/media/…") are relative and the app's image loader resolves them on the signed-in server. "" = none.
@propertyWrapper
struct Picture: Codable, Hashable, Sendable {
    var wrappedValue: URL?

    init(wrappedValue: URL?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { wrappedValue = nil; return }
        let s = try c.decode(String.self)
        wrappedValue = s.isEmpty ? nil : URL(string: s)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue?.absoluteString ?? "")
    }
}

/// A title, as the catalogue pages name it (`TitleRef`, src/catalog/detail.ts): `{ kind, id }`.
struct TitleRef: Codable, Hashable, Sendable {
    var kind: MediaKind
    var id: String

    /// the app's title id ("anime:210482")
    var titleId: String { TitleKey(media: kind.api, id: id).titleId }

    init(kind: MediaKind, id: String) {
        self.kind = kind
        self.id = id
    }

    init?(titleId: String) {
        guard let k = TitleKey(titleId: titleId) else { return nil }
        self.init(kind: k.media.kind, id: k.id)
    }
}

/// The next episode of a title on your list (`NextEpisode`, src/home/types.ts): home/live's Upcoming, and the Up
/// Next widget's spotlight. Lives here so the widget extension (which compiles this file, not Home.swift) has it.
struct NextEpisode: Codable, Hashable, Sendable, Identifiable {
    var ref: TitleRef
    /// the list it's on
    var media: APIMedia
    var id: String
    var title: String
    @Picture var cover: URL?
    /// the episode; TV counts across seasons
    var number: Int
    /// ms; with `dateOnly` only the day is known (TMDB)
    var at: Int64
    var dateOnly: Bool

    var titleId: String { ref.titleId }
    var date: Date { Millis.date(at) }

    /// "Ep 7 · Fri 3:00 AM" this week, "Ep 1181 · Jan 3" later; a day-only one has no time ("Ep 4 · Wed")
    func caption(now: Date = Clock.now) -> String {
        let d = date
        let offset = Format.dayOffset(d, now: now)
        let when: String
        if offset >= 7 { when = Format.shortDay(d) }
        else if !dateOnly { when = Format.weekdayTime(d) }
        else if offset == 0 { when = "Today" }
        else if offset == 1 { when = "Tomorrow" }
        else { when = Format.weekday(d) }
        return "\(ref.kind.unitShort) \(Format.grouped(number)) · \(when)"
    }
}

/// What the extensions know beyond the library (api/extensions.json in the demo): titles the share extension can
/// match that aren't on the list, TV season lengths, MyAnimeList ids to AniList title ids.
struct ExtensionCatalog: Codable, Equatable, Sendable {
    var titles: [Title]
    /// title id -> episodes in each season ("tv:95396": [9, 10])
    var seasons: [String: [Int]]
    /// "anime/61469" -> "anime:210482"
    var malIds: [String: String]
    /// the next episodes of what you watch, as GET home/live answers `upcoming` (the real app writes the last answer
    /// into the App Group); none when it isn't known
    var upcoming: [NextEpisode]

    init(titles: [Title] = [], seasons: [String: [Int]] = [:], malIds: [String: String] = [:],
         upcoming: [NextEpisode] = []) {
        self.titles = titles
        self.seasons = seasons
        self.malIds = malIds
        self.upcoming = upcoming
    }

    private enum CodingKeys: String, CodingKey { case titles, seasons, malIds, upcoming }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titles = try c.decodeIfPresent([Title].self, forKey: .titles) ?? []
        seasons = try c.decodeIfPresent([String: [Int]].self, forKey: .seasons) ?? [:]
        malIds = try c.decodeIfPresent([String: String].self, forKey: .malIds) ?? [:]
        upcoming = try c.decodeIfPresent([NextEpisode].self, forKey: .upcoming) ?? []
    }
}

/// JSON for the extensions (they don't have APIClient): the app API's dates, ISO 8601 with or without milliseconds.
enum ExtensionsJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let n = try? c.decode(Double.self) { return Date(timeIntervalSince1970: n > 1e11 ? n / 1000 : n) }
            let s = try c.decode(String.self)
            if let d = parse(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a date: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    /// the demo's library, bundled as GET library/changes answers it (changes.json), as the screens show it
    static func bundledLibrary(bundle: Bundle = .main) -> [LibraryEntry] {
        bundled(ChangeFeed.self, "changes", bundle: bundle)?.entries.map(\.library) ?? []
    }

    /// a JSON file bundled into an extension (the demo's changes.json and extensions.json); nil when it isn't there
    static func bundled<T: Decodable>(_ type: T.Type, _ name: String, bundle: Bundle = .main) -> T? {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Where a TV show's progress is: GupTrack counts every episode watched, so with the seasons' lengths 15 episodes
/// of Severance (9 + 10) is season 2, episode 6 of 10.
struct SeasonPosition: Equatable, Sendable {
    var season: Int
    var episode: Int
    var total: Int

    /// nil without season lengths
    static func of(progress: Int, lengths: [Int]?) -> SeasonPosition? {
        guard let lengths, !lengths.isEmpty else { return nil }
        var left = max(0, progress)
        for (i, n) in lengths.enumerated() {
            if left < n || i == lengths.count - 1 {
                return SeasonPosition(season: i + 1, episode: min(left, n), total: n)
            }
            left -= n
        }
        return nil
    }

    /// the whole-show progress for an episode of this season
    static func progress(season: Int, episode: Int, lengths: [Int]) -> Int {
        lengths.prefix(max(0, season - 1)).reduce(0, +) + episode
    }
}

struct WidgetSnapshot: Codable, Equatable, Sendable {
    /// a title in Continue (the medium widget's rows, the Lock Screen's rings)
    struct Item: Codable, Equatable, Identifiable, Sendable {
        var id: String
        var media: MediaKind
        var name: String
        var cover: URL?
        /// what you're on in its own count (the episode of the season for TV)
        var progress: Int
        var total: Int?
        /// "Ep 6 of 11", "S2 · Ep 6 of 10", "Ch 97 of 232", "p. 212 of 496"
        var caption: String
        /// 0...1, nil when the total isn't known
        var fraction: Double?
        /// the +1 button shows (not for films or a finished season's last episode)
        var canStep: Bool
        /// the ring's small line under the number: "of 11", or "ep" when the total isn't known
        var ringCaption: String

        var url: URL { Route.title(id).url }
    }

    /// the small widget and the Lock Screen's rectangle: the next episode of something you watch, or else the first
    /// title in Continue
    struct Spotlight: Codable, Equatable, Sendable {
        var id: String
        var name: String
        var cover: URL?
        /// "Next episode" or "Up next" (the widget shows it in small capitals, as the mockup)
        var label: String
        /// "Ep 7 · Fri 3:00 AM", "Ep 7"
        var caption: String
        /// one line for accessoryInline: "Ep 7 · Fri 3:00 AM · STEEL BALL RUN…"
        var inline: String
        /// when it airs (the timeline moves on after it)
        var at: Date?

        var url: URL { Route.title(id).url }
    }

    var made: Date
    var items: [Item]
    var spotlight: Spotlight?

    /// most titles the widgets ever show (the large sizes aren't offered; the medium shows 2)
    static let maxItems = 4
    /// a current title with no progress for this long is left out (Home's Stalled rule)
    static let stallDays = 30

    static let empty = WidgetSnapshot(made: Date(timeIntervalSince1970: 0), items: [], spotlight: nil)

    /// the snapshot for a library at `now`; `upcoming` is home/live's next episodes (else the catalog's)
    static func make(library: [LibraryEntry], catalog: ExtensionCatalog = ExtensionCatalog(),
                     upcoming next: [NextEpisode]? = nil, now: Date = Clock.now) -> WidgetSnapshot {
        let cont = continuing(library, now: now)
        let items = cont.prefix(maxItems).map { item($0, seasons: catalog.seasons[$0.id]) }
        let lib = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let spot = upcoming(next ?? catalog.upcoming, library: library, now: now).first
            .map { spotlight(airing: $0, entry: lib[$0.titleId], now: now) }
            ?? cont.first.map { spotlight(upNext: $0, seasons: catalog.seasons[$0.id]) }
        return WidgetSnapshot(made: now, items: Array(items), spotlight: spot)
    }

    /// Continue: what you're on and touched in the last 30 days, last touched first
    static func continuing(_ lib: [LibraryEntry], now: Date) -> [LibraryEntry] {
        lib.filter { $0.status.isActive && now.timeIntervalSince($0.updatedAt) <= Double(stallDays) * 86_400 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// next episodes of what you watch (watching or rewatching it) still to air, soonest first
    static func upcoming(_ next: [NextEpisode], library: [LibraryEntry], now: Date) -> [NextEpisode] {
        let active = Set(library.filter { $0.status.isActive }.map(\.id))
        return next.filter { n in
            active.contains(n.titleId) && (n.dateOnly ? Format.dayOffset(n.date, now: now) >= 0 : n.date > now)
        }.sorted { $0.at < $1.at }
    }

    static func item(_ e: LibraryEntry, seasons: [Int]? = nil) -> Item {
        let pos = e.media == .tv ? SeasonPosition.of(progress: e.progress, lengths: seasons) : nil
        let progress = pos?.episode ?? e.progress
        let total = pos?.total ?? e.title.total
        var caption: String
        switch e.media {
        case .movie:
            caption = "Film"
        default:
            caption = "\(e.media.unitShort) \(Format.grouped(progress))"
            if let total { caption += " of \(Format.grouped(total))" }
            if let pos { caption = "S\(pos.season) · " + caption }
        }
        let fraction = total.flatMap { $0 > 0 ? min(1, Double(progress) / Double($0)) : nil }
        let unit = e.media == .book ? "p." : e.media.unitShort.lowercased()
        return Item(id: e.id, media: e.media, name: e.title.name, cover: e.title.cover,
                    progress: progress, total: total, caption: caption, fraction: fraction,
                    canStep: plusOne(e) != nil, ringCaption: total.map { "of \(Format.grouped($0))" } ?? unit)
    }

    /// the next episode's spotlight; the library's copy names it (its cover is the one the widget already shows)
    static func spotlight(airing n: NextEpisode, entry: LibraryEntry? = nil, now: Date) -> Spotlight {
        let caption = n.caption(now: now)
        let name = entry?.title.name ?? n.title
        return Spotlight(id: n.titleId, name: name, cover: entry?.title.cover ?? n.cover,
                         label: "Next episode", caption: caption, inline: caption + " · " + name, at: n.date)
    }

    static func spotlight(upNext e: LibraryEntry, seasons: [Int]? = nil) -> Spotlight {
        let it = item(e, seasons: seasons)
        let caption: String
        if e.media == .movie {
            caption = it.caption
        } else if e.media == .tv, let pos = SeasonPosition.of(progress: e.progress + 1, lengths: seasons) {
            caption = "S\(pos.season) · Ep \(pos.episode)"
        } else {
            caption = "\(e.media.unitShort) \(Format.grouped(e.progress + e.media.step))"
        }
        return Spotlight(id: e.id, name: e.title.name, cover: e.title.cover,
                         label: "Up next", caption: caption, inline: caption + " · " + e.title.name, at: nil)
    }

    /// what a widget's +1 changes (books go by 10 pages, clamped to the end); nil when there's nothing to add
    static func plusOne(_ e: LibraryEntry) -> LibraryPatch? {
        guard e.media != .movie else { return nil }
        if let total = e.title.total, e.progress >= total { return nil }
        let next = e.progress + e.media.step
        return LibraryPatch(progress: e.title.total.map { min(next, $0) } ?? next)
    }
}

/// The +1s made on a widget, kept until the app takes them. Demo: in the widget extension's own UserDefaults, and
/// the widgets show the library with them applied. Real app: the App Group's outbox, which the app sends to the
/// server like any offline change.
struct WidgetOutbox: Codable, Equatable, Sendable {
    struct Change: Codable, Equatable, Sendable {
        var id: String
        var patch: LibraryPatch
        var at: Date
    }

    var changes: [Change] = []

    static let key = "widget-outbox"

    /// the library with every change applied, in order
    func apply(to library: [LibraryEntry]) -> [LibraryEntry] {
        var lib = library
        for c in changes {
            guard let i = lib.firstIndex(where: { $0.id == c.id }) else { continue }
            lib[i] = lib[i].applying(c.patch, at: c.at)
        }
        return lib
    }

    /// +1 on a title as it stands with the changes so far; returns the entry after it (nil when nothing changed)
    @discardableResult
    mutating func step(_ id: String, in library: [LibraryEntry], now: Date) -> LibraryEntry? {
        guard let e = apply(to: library).first(where: { $0.id == id }), let patch = WidgetSnapshot.plusOne(e) else {
            return nil
        }
        changes.append(Change(id: id, patch: patch, at: now))
        return e.applying(patch, at: now)
    }

    /// the share extension keeps its demo Adds under "share-outbox"
    static func load(_ defaults: UserDefaults, key: String = WidgetOutbox.key) -> WidgetOutbox {
        guard let data = defaults.data(forKey: key),
              let box = try? ExtensionsJSON.decoder.decode(WidgetOutbox.self, from: data) else { return WidgetOutbox() }
        return box
    }

    func save(_ defaults: UserDefaults, key: String = WidgetOutbox.key) {
        if let data = try? ExtensionsJSON.encoder.encode(self) { defaults.set(data, forKey: key) }
    }
}
