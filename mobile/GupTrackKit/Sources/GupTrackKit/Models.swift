import Foundation

// The shared models every screen uses: media kinds, list statuses, titles, library entries, users and lists. The
// app API (/api/app/v1, AppAPI.swift) sends these as JSON; the demo fixtures (mobile/fixtures/demo/api) are recorded
// answers in the same shape. Screen-specific answers (a title page, social, settings…) live in their own files.

/// The five kinds of media GupTrack tracks.
enum MediaKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case anime, manga, tv, movie, book

    var id: String { rawValue }

    /// "Anime", "Manga", "TV", "Movies", "Books": the media switch and the Library's lists
    var plural: String {
        switch self {
        case .anime: return "Anime"
        case .manga: return "Manga"
        case .tv: return "TV"
        case .movie: return "Movies"
        case .book: return "Books"
        }
    }

    /// "Anime", "Manga", "TV", "Movie", "Book": a title's caption ("Anime · ONA · 5 episodes left")
    var singular: String {
        switch self {
        case .anime: return "Anime"
        case .manga: return "Manga"
        case .tv: return "TV"
        case .movie: return "Movie"
        case .book: return "Book"
        }
    }

    /// what progress counts; nil for films (watched or not)
    var unit: String? {
        switch self {
        case .anime, .tv: return "episode"
        case .manga: return "chapter"
        case .book: return "page"
        case .movie: return nil
        }
    }

    /// "1 episode", "5 episodes", "12 chapters"
    func units(_ n: Int) -> String {
        guard let unit else { return "" }
        return "\(Format.grouped(n)) \(unit)\(n == 1 ? "" : "s")"
    }

    /// short unit for compact places: "Ep", "Ch", "p."
    var unitShort: String {
        switch self {
        case .anime, .tv: return "Ep"
        case .manga: return "Ch"
        case .book: return "p."
        case .movie: return ""
        }
    }

    var isReading: Bool { self == .manga || self == .book }

    /// SF Symbol for menus (the Library's media switch)
    var symbol: String {
        switch self {
        case .anime: return "sparkles.tv"
        case .manga: return "book.pages"
        case .tv: return "tv"
        case .movie: return "film"
        case .book: return "book.closed"
        }
    }

    /// how many a +1 adds: books go by 10 pages
    var step: Int { self == .book ? 10 : 1 }
}

/// A list status, as on the website. Its words depend on the media ("Watching" / "Reading").
enum ListStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case current, completed, hold, dropped, planned, repeating

    var id: String { rawValue }

    /// the order the website lists them in (filters, menus, the status bar)
    static let ordered: [ListStatus] = [.current, .completed, .hold, .dropped, .planned]

    func label(_ media: MediaKind) -> String {
        switch self {
        case .current: return media.isReading ? "Reading" : "Watching"
        case .completed: return "Completed"
        case .hold: return "On-Hold"
        case .dropped: return "Dropped"
        case .planned: return media.isReading ? "Plan to Read" : "Plan to Watch"
        case .repeating: return media.isReading ? "Rereading" : "Rewatching"
        }
    }

    /// the status colour's name in the app's theme (Theme.status in the app); hex for widgets and tests
    var hex: String {
        switch self {
        case .current, .repeating: return "#30d158"
        case .completed: return "#0a84ff"
        case .hold: return "#ffd60a"
        case .dropped: return "#ff453a"
        case .planned: return "#8e8e93"
        }
    }

    var isActive: Bool { self == .current || self == .repeating }
}

/// When a title's next episode airs.
struct Airing: Codable, Hashable, Sendable {
    var episode: Int
    var at: Date
}

/// A title as every list, shelf and row shows it. `id` is "<media>:<source id>" ("anime:210482", "tv:95396",
/// "book:OL21745884W").
struct Title: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var media: MediaKind
    var name: String
    /// the line under the name on a title page (alternative + native titles), or a book's author
    var subtitle: String?
    var cover: URL?
    var banner: URL?
    /// "TV", "ONA", "Movie", "Manga", "Novel", "Hardcover"…
    var format: String?
    var year: Int?
    /// "Fall 2026"
    var season: String?
    /// episodes, chapters or pages; nil while unknown (still airing)
    var total: Int?
    var volumes: Int?
    /// the average score out of 10 (8.6)
    var score: Double?
    var genres: [String]?
    /// studio, network or author
    var studio: String?
    var next: Airing?
    /// "2h 47m" for films, "24 min" per episode
    var runtime: String?
    /// "Releasing", "Finished", "Not yet released"
    var state: String?

    init(id: String, media: MediaKind, name: String, subtitle: String? = nil, cover: URL? = nil, banner: URL? = nil,
         format: String? = nil, year: Int? = nil, season: String? = nil, total: Int? = nil, volumes: Int? = nil,
         score: Double? = nil, genres: [String]? = nil, studio: String? = nil, next: Airing? = nil,
         runtime: String? = nil, state: String? = nil) {
        self.id = id
        self.media = media
        self.name = name
        self.subtitle = subtitle
        self.cover = cover
        self.banner = banner
        self.format = format
        self.year = year
        self.season = season
        self.total = total
        self.volumes = volumes
        self.score = score
        self.genres = genres
        self.studio = studio
        self.next = next
        self.runtime = runtime
        self.state = state
    }

    /// "Anime · ONA" (the format only when it says something the media doesn't: a TV series is the usual anime)
    var kindLine: String {
        var parts = [media.singular]
        if let format, !format.isEmpty, format.lowercased() != media.singular.lowercased(), format != "TV" {
            parts.append(format)
        }
        return parts.joined(separator: " · ")
    }
}

/// One title on your list. The offline library (LibraryStore) keeps these; the server's copy comes in through the
/// change feed.
struct LibraryEntry: Codable, Identifiable, Hashable, Sendable {
    var title: Title
    var status: ListStatus
    var progress: Int
    /// manga: the volume you're on; TV: the season you're on
    var volume: Int?
    var season: Int?
    /// out of 100 (the website keeps 0-100 and shows it in your score format)
    var score: Int?
    var repeats: Int
    var started: String?
    var finished: String?
    var notes: String
    var favourite: Bool
    var updatedAt: Date

    var id: String { title.id }
    var media: MediaKind { title.media }

    init(title: Title, status: ListStatus, progress: Int = 0, volume: Int? = nil, season: Int? = nil, score: Int? = nil,
         repeats: Int = 0, started: String? = nil, finished: String? = nil, notes: String = "", favourite: Bool = false,
         updatedAt: Date) {
        self.title = title
        self.status = status
        self.progress = progress
        self.volume = volume
        self.season = season
        self.score = score
        self.repeats = repeats
        self.started = started
        self.finished = finished
        self.notes = notes
        self.favourite = favourite
        self.updatedAt = updatedAt
    }

    /// 0...1 of the way through, nil when the total isn't known
    var fraction: Double? {
        guard let total = title.total, total > 0 else { return nil }
        return min(1, Double(progress) / Double(total))
    }

    /// how many are left ("5 episodes left"), nil when unknown
    var left: Int? {
        guard let total = title.total else { return nil }
        return max(0, total - progress)
    }

    /// the caption under a title in Continue: "Anime · ONA · 5 episodes left"
    var continueLine: String {
        var parts = [title.kindLine]
        if let left, left > 0 { parts.append("\(media.units(left)) left") }
        return parts.joined(separator: " · ")
    }

    /// the website's score out of 10 ("8.5"), nil when unscored
    var score10: String? { score.map { Format.score10($0) } }
}

/// A change to a library entry. Only what's set is changed (nil fields stay out of the JSON).
struct LibraryPatch: Codable, Hashable, Sendable {
    var status: ListStatus?
    var progress: Int?
    var volume: Int?
    var season: Int?
    /// -1 clears the score
    var score: Int?
    var repeats: Int?
    var started: String?
    var finished: String?
    var notes: String?
    var favourite: Bool?
    /// true takes the title off the list
    var remove: Bool?

    init(status: ListStatus? = nil, progress: Int? = nil, volume: Int? = nil, season: Int? = nil, score: Int? = nil,
         repeats: Int? = nil, started: String? = nil, finished: String? = nil, notes: String? = nil,
         favourite: Bool? = nil, remove: Bool? = nil) {
        self.status = status
        self.progress = progress
        self.volume = volume
        self.season = season
        self.score = score
        self.repeats = repeats
        self.started = started
        self.finished = finished
        self.notes = notes
        self.favourite = favourite
        self.remove = remove
    }

    var isEmpty: Bool { self == LibraryPatch() }

    /// this patch, then `later` on top (later fields win)
    func merged(_ later: LibraryPatch) -> LibraryPatch {
        LibraryPatch(status: later.status ?? status, progress: later.progress ?? progress,
                     volume: later.volume ?? volume, season: later.season ?? season, score: later.score ?? score,
                     repeats: later.repeats ?? repeats, started: later.started ?? started,
                     finished: later.finished ?? finished, notes: later.notes ?? notes,
                     favourite: later.favourite ?? favourite, remove: later.remove ?? remove)
    }
}

extension LibraryEntry {
    /// the entry with a patch applied, the way the server applies it (progress clamps to the total; finishing
    /// the last episode completes it)
    func applying(_ p: LibraryPatch, at now: Date) -> LibraryEntry {
        var e = self
        if let s = p.status { e.status = s }
        if let v = p.progress {
            e.progress = max(0, title.total.map { min(v, $0) } ?? v)
            if p.status == nil, let total = title.total, total > 0, e.progress == total, e.status.isActive {
                e.status = .completed
                if e.finished == nil { e.finished = Format.day(now) }
            }
            if p.status == nil, e.status == .planned, e.progress > 0 { e.status = .current }
        }
        if let v = p.volume { e.volume = v }
        if let v = p.season { e.season = v }
        if let v = p.score { e.score = v < 0 ? nil : min(100, v) }
        if let v = p.repeats { e.repeats = max(0, v) }
        if let v = p.started { e.started = v.isEmpty ? nil : v }
        if let v = p.finished { e.finished = v.isEmpty ? nil : v }
        if let v = p.notes { e.notes = v }
        if let v = p.favourite { e.favourite = v }
        e.updatedAt = now
        return e
    }

    /// a new entry for a title that wasn't on the list
    static func new(_ title: Title, _ p: LibraryPatch, at now: Date) -> LibraryEntry {
        LibraryEntry(title: title, status: p.status ?? .planned, updatedAt: now).applying(p, at: now)
    }
}

/// Someone on GupTrack, as rows, avatars and mentions show them.
struct UserRef: Codable, Identifiable, Hashable, Sendable {
    var username: String
    var name: String
    var avatar: URL?

    var id: String { username }
}

/// Who can see something (a list, a review, the profile).
enum Visibility: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case `public`, friends, `private`

    var id: String { rawValue }

    var label: String {
        switch self {
        case .public: return "Public"
        case .friends: return "Friends only"
        case .private: return "Private"
        }
    }

    var symbol: String {
        switch self {
        case .public: return "globe"
        case .friends: return "person.2"
        case .private: return "lock"
        }
    }
}

/// A custom list: its titles in your order, each with an optional note ("Why it's here").
struct CustomList: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var description: String?
    var visibility: Visibility
    var items: [CustomListItem]
    var updatedAt: Date

    var covers: [URL] { items.prefix(4).compactMap { $0.title.cover } }
}

struct CustomListItem: Codable, Identifiable, Hashable, Sendable {
    var title: Title
    var note: String?

    var id: String { title.id }
}
