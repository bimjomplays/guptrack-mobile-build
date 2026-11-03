import Foundation

// What the Home Screen and Lock Screen widgets show (65, 65b), worked out from the library. Plain Foundation: the
// widget extension compiles this file (with Models, Format and Route), and so do the app and the Linux tests. The
// extension has no AppModel or APIClient: it gets the library as a list of entries.
//
// Demo: the extensions bundle api/library.json and api/extensions.json and build the snapshot themselves; a widget's
// +1 is kept in the extension's own WidgetOutbox. The real app would write the library (or this snapshot) into an
// App Group the widgets read, and the +1s into the App Group's outbox for the app to sync.

/// What the extensions know beyond the library (api/extensions.json in the demo): titles the share extension can
/// match that aren't on the list, TV season lengths, MyAnimeList ids to AniList title ids.
struct ExtensionCatalog: Codable, Equatable, Sendable {
    var titles: [Title]
    /// title id -> episodes in each season ("tv:95396": [9, 10])
    var seasons: [String: [Int]]
    /// "anime/61469" -> "anime:210482"
    var malIds: [String: String]

    init(titles: [Title] = [], seasons: [String: [Int]] = [:], malIds: [String: String] = [:]) {
        self.titles = titles
        self.seasons = seasons
        self.malIds = malIds
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

    /// a JSON file bundled into an extension (the demo's library.json and extensions.json); nil when it isn't there
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
        var banner: URL?
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
        var banner: URL?
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

    /// the snapshot for a library at `now`
    static func make(library: [LibraryEntry], catalog: ExtensionCatalog = ExtensionCatalog(),
                     now: Date = Clock.now) -> WidgetSnapshot {
        let cont = continuing(library, now: now)
        let items = cont.prefix(maxItems).map { item($0, seasons: catalog.seasons[$0.id]) }
        let spot = upcoming(library, now: now).first.map { spotlight(airing: $0, now: now) }
            ?? cont.first.map { spotlight(upNext: $0, seasons: catalog.seasons[$0.id]) }
        return WidgetSnapshot(made: now, items: Array(items), spotlight: spot)
    }

    /// Continue: what you're on and touched in the last 30 days, last touched first
    static func continuing(_ lib: [LibraryEntry], now: Date) -> [LibraryEntry] {
        lib.filter { $0.status.isActive && now.timeIntervalSince($0.updatedAt) <= Double(stallDays) * 86_400 }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// what you watch with a next episode still to air, soonest first
    static func upcoming(_ lib: [LibraryEntry], now: Date) -> [LibraryEntry] {
        lib.filter { $0.status.isActive && ($0.title.next.map { $0.at > now } ?? false) }
            .sorted { $0.title.next!.at < $1.title.next!.at }
    }

    static func item(_ e: LibraryEntry, seasons: [Int]? = nil) -> Item {
        let pos = e.media == .tv ? SeasonPosition.of(progress: e.progress, lengths: seasons) : nil
        let progress = pos?.episode ?? e.progress
        let total = pos?.total ?? e.title.total
        var caption: String
        switch e.media {
        case .movie:
            caption = e.title.year.map { "Film · \($0)" } ?? "Film"
        default:
            caption = "\(e.media.unitShort) \(Format.grouped(progress))"
            if let total { caption += " of \(Format.grouped(total))" }
            if let pos { caption = "S\(pos.season) · " + caption }
        }
        let fraction = total.flatMap { $0 > 0 ? min(1, Double(progress) / Double($0)) : nil }
        let unit = e.media == .book ? "p." : e.media.unitShort.lowercased()
        return Item(id: e.id, media: e.media, name: e.title.name, cover: e.title.cover, banner: e.title.banner,
                    progress: progress, total: total, caption: caption, fraction: fraction,
                    canStep: plusOne(e) != nil, ringCaption: total.map { "of \(Format.grouped($0))" } ?? unit)
    }

    /// "Ep 7 · Fri 3:00 AM" this week, "Ep 1181 · Jan 3" later
    static func airingCaption(_ a: Airing, media: MediaKind, now: Date) -> String {
        let when = Format.dayOffset(a.at, now: now) < 7 ? Format.weekdayTime(a.at) : Format.shortDay(a.at)
        return "\(media.unitShort) \(a.episode) · \(when)"
    }

    static func spotlight(airing e: LibraryEntry, now: Date) -> Spotlight {
        let a = e.title.next!
        let caption = airingCaption(a, media: e.media, now: now)
        return Spotlight(id: e.id, name: e.title.name, cover: e.title.cover, banner: e.title.banner,
                         label: "Next episode", caption: caption, inline: caption + " · " + e.title.name, at: a.at)
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
        return Spotlight(id: e.id, name: e.title.name, cover: e.title.cover, banner: e.title.banner,
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
