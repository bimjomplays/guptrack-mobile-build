import Foundation

// Browse (11-15): the shelves, the filters, the season chart and search (docs/app-api.md §8.1, §8.2). The wire
// shapes are the website's own, field for field (src/catalog/types.ts, src/catalog/detail.ts,
// src/components/browse/search.ts); the screens show them as the app's `Title`. Filtering, grouping and captions
// live here so they're tested on Linux; the views only draw them.

// MARK: the catalogue's shapes

/// `CatalogStatus`
enum CatalogStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case releasing, finished, upcoming
}

/// `Season` (anime)
enum CatalogSeason: String, Codable, CaseIterable, Hashable, Sendable {
    case winter, spring, summer, fall

    /// "Fall"
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// `CatalogTitle`: one title in the Browse catalogue. What `count` and `by` mean depends on the media.
struct CatalogTitle: Codable, Hashable, Sendable {
    /// "anilist:16498", "tmdb:1399", "ol:OL45804W" (unique within its media)
    var id: String
    /// "anilist", "tmdb", "openlibrary"
    var source: String
    /// AniList "154587", TMDB "tv/1399" or "movie/693134", Open Library "OL45804W"
    var sourceId: String
    var title: String
    var alt: [String]?
    /// a picture as the answer has it (https, or a GupTrack "/" address the image loader resolves)
    var cover: URL?
    /// one of the media's formats: "TV", "Film", "Manhwa", "Novel"
    var format: String
    var year: Int?
    var season: CatalogSeason?
    /// "2026-10-04", "2026-10" or "2026"
    var start: String?
    var status: CatalogStatus
    var genres: [String]
    var tags: [String]
    /// 0–100
    var score: Double?
    var popularity: Double
    var trending: Double
    /// episodes (anime, TV), chapters (manga), minutes (movies), pages (books)
    var count: Int?
    /// studio (anime), author (manga, books), creator (TV), director (movies)
    var by: String

    init(id: String, source: String, sourceId: String, title: String, alt: [String]? = nil, cover: URL? = nil,
         format: String, year: Int? = nil, season: CatalogSeason? = nil, start: String? = nil,
         status: CatalogStatus = .finished, genres: [String] = [], tags: [String] = [], score: Double? = nil,
         popularity: Double = 0, trending: Double = 0, count: Int? = nil, by: String = "") {
        self.id = id
        self.source = source
        self.sourceId = sourceId
        self.title = title
        self.alt = alt
        self.cover = cover
        self.format = format
        self.year = year
        self.season = season
        self.start = start
        self.status = status
        self.genres = genres
        self.tags = tags
        self.score = score
        self.popularity = popularity
        self.trending = trending
        self.count = count
        self.by = by
    }

    /// the title page it opens (`titleRefOf`: TMDB's "tv/1399" is 1399)
    func ref(_ media: APIMedia) -> TitleRef {
        let id = sourceId.firstIndex(of: "/").map { String(sourceId[sourceId.index(after: $0)...]) } ?? sourceId
        return TitleRef(kind: media.kind, id: id)
    }

    /// the title as the app's cards and rows show it
    func title(_ media: APIMedia, next: Airing? = nil) -> Title {
        let kind = media.kind
        return Title(id: ref(media).titleId, media: kind, name: title, subtitle: alt?.first, cover: cover,
                     format: format, year: year, season: season.flatMap { s in year.map { "\(s.label) \($0)" } },
                     total: kind == .movie ? nil : count, score: score.map { $0 / 10 },
                     genres: genres, studio: by.isEmpty ? nil : by, next: next,
                     runtime: kind == .movie ? count.flatMap { ListEntry.runtime($0, .movie) } : nil,
                     state: Catalog.state(status))
    }
}

// `TitleRef` (a title page, by its kind and source id) lives in WidgetSnapshot.swift: the widget compiles only that file.

/// `Ref`: any page a name can link to, told apart by `to`.
enum CatalogRef: Codable, Hashable, Sendable {
    case title(TitleRef)
    case character(String)
    /// source "anilist" or "tmdb"
    case person(source: String, id: String)
    /// an Open Library author ("OL7234434A")
    case author(String)
    /// to "studio", "network" or "company"
    case company(to: String, id: String)
    /// a kind of page this app doesn't know yet
    case other(String)

    private enum Keys: String, CodingKey { case to, kind, id, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let to = try c.decode(String.self, forKey: .to)
        func id() throws -> String { try c.decode(String.self, forKey: .id) }
        switch to {
        case "title": self = .title(TitleRef(kind: try c.decode(MediaKind.self, forKey: .kind), id: try id()))
        case "character": self = .character(try id())
        case "person": self = .person(source: try c.decode(String.self, forKey: .source), id: try id())
        case "author": self = .author(try id())
        case "studio", "network", "company": self = .company(to: to, id: try id())
        default: self = .other(to)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .title(let r):
            try c.encode("title", forKey: .to)
            try c.encode(r.kind, forKey: .kind)
            try c.encode(r.id, forKey: .id)
        case .character(let id):
            try c.encode("character", forKey: .to)
            try c.encode(id, forKey: .id)
        case .person(let source, let id):
            try c.encode("person", forKey: .to)
            try c.encode(source, forKey: .source)
            try c.encode(id, forKey: .id)
        case .author(let id):
            try c.encode("author", forKey: .to)
            try c.encode(id, forKey: .id)
        case .company(let to, let id):
            try c.encode(to, forKey: .to)
            try c.encode(id, forKey: .id)
        case .other(let to):
            try c.encode(to, forKey: .to)
        }
    }

    /// the page it opens in the app
    var route: Route? {
        switch self {
        case .title(let r): return .title(r.titleId)
        case .character(let id): return .character(id)
        case .person(let s, let id): return .person("\(s):\(id)")
        case .author(let id): return .author(id)
        case .company(let to, let id): return .studio("\(to):\(id)")
        case .other: return nil
        }
    }

    /// the title it is, when it's one
    var titleRef: TitleRef? {
        if case .title(let r) = self { return r }
        return nil
    }
}

/// Small helpers every catalogue page shares.
enum Catalog {
    /// the app's state words for a title ("Releasing", "Finished", "Not yet released")
    static func state(_ s: CatalogStatus) -> String {
        switch s {
        case .releasing: return "Releasing"
        case .finished: return "Finished"
        case .upcoming: return "Not yet released"
        }
    }

    /// the website's words for a status, per media (catalog/config.ts)
    static func statusLabel(_ s: CatalogStatus, _ m: MediaKind) -> String {
        switch (m, s) {
        case (.anime, .releasing), (.tv, .releasing): return "Airing"
        case (.anime, .upcoming): return "Not yet aired"
        case (.tv, .finished): return "Not airing"
        case (.tv, .upcoming), (.movie, .upcoming): return "Upcoming"
        case (.movie, .finished): return "Released"
        case (.book, .finished): return "Published"
        case (_, .releasing): return "Releasing"
        case (_, .finished): return "Finished"
        case (_, .upcoming): return "Not yet released"
        }
    }

    /// the formats a media's titles come in (catalog/config.ts)
    static func formats(_ m: MediaKind) -> [String] {
        switch m {
        case .anime: return ["TV", "Film", "OVA", "ONA", "Special"]
        case .manga: return ["Manga", "Manhwa", "Manhua", "Light Novel", "One-shot"]
        case .tv: return ["Series", "Miniseries"]
        case .movie: return ["Film", "Documentary"]
        case .book: return ["Novel", "Nonfiction", "Graphic novel"]
        }
    }

    /// the statuses a media's filter offers (catalog/config.ts)
    static func statuses(_ m: MediaKind) -> [CatalogStatus] {
        switch m {
        case .anime, .manga, .tv: return [.releasing, .finished, .upcoming]
        case .movie: return [.finished, .upcoming]
        case .book: return [.finished]
        }
    }

    /// `plain`: lower case, no accents or punctuation, so "steins gate" finds "Steins;Gate"
    static func plain(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var out = "", gap = false
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                if gap && !out.isEmpty { out.append(" ") }
                out.append(ch)
                gap = false
            } else {
                gap = true
            }
        }
        return out
    }
}

// MARK: the Browse page (§8.1)

/// `GET browse/:media/shelves`
struct BrowseShelves: Codable, Equatable, Sendable {
    var shelves: [Shelf]

    /// `{ spec, titles }`
    struct Shelf: Codable, Equatable, Sendable {
        var spec: ShelfSpec
        var titles: [CatalogTitle]
    }
}

/// `ShelfSpec`: a shelf on the Browse page; See all opens its filter (or the season chart).
struct ShelfSpec: Codable, Hashable, Sendable {
    var title: String
    /// "Fall 2026", "All time"
    var note: String?
    var filter: BrowseFilters
    var chart: Bool?
    var min: Int
    var fresh: Bool?
}

/// `GET browse/:media/filters`: what the Genres and Tags filters offer
struct Facets: Codable, Equatable, Sendable {
    var genres: [String]
    var tags: [String]
}

/// `GET browse/:media/results`: one page of the catalogue with filters
struct BrowseResults: Codable, Equatable, Sendable {
    var titles: [CatalogTitle]
    /// how many match in all (nil: not known; `more`: at least this many)
    var total: Int?
    var more: Bool
    /// the page to ask for next, nil at the end
    var next: Int?
}

/// The Browse page of one media, as the screen shows it: the shelves as titles, and for TV and films the first
/// title of the first shelf as the big card on top (labelled with that shelf).
struct BrowsePage: Equatable, Sendable {
    var media: MediaKind
    var feature: Feature?
    var shelves: [Shelf]

    struct Shelf: Equatable, Sendable, Identifiable {
        var title: String
        var note: String?
        var filter: BrowseFilters
        /// See all opens the season chart
        var chart: Bool
        var titles: [Title]

        var id: String { title }
    }

    /// the big card on top of TV and Movies
    struct Feature: Equatable, Sendable {
        var label: String
        var title: Title

        /// "2025 · Drama · ★ 7.9"
        var line: String {
            var parts: [String] = []
            if let y = title.year { parts.append(String(y)) }
            if let g = title.genres?.first { parts.append(BrowseCaption.shortGenre(g)) }
            if let s = title.score { parts.append("★ " + Format.average(s)) }
            return parts.joined(separator: " · ")
        }
    }

    init(media: MediaKind, feature: Feature? = nil, shelves: [Shelf]) {
        self.media = media
        self.feature = feature
        self.shelves = shelves
    }

    init(_ media: MediaKind, _ answer: BrowseShelves) {
        var shelves = answer.shelves.filter { !$0.titles.isEmpty }.map { s in
            Shelf(title: s.spec.title, note: s.spec.note, filter: s.spec.filter, chart: s.spec.chart == true,
                  titles: s.titles.map { $0.title(media.api) })
        }
        var feature: Feature?
        if media == .tv || media == .movie, let first = shelves.first, let t = first.titles.first {
            feature = Feature(label: first.title, title: t)
            shelves[0].titles.removeFirst()
            if shelves[0].titles.isEmpty { shelves.removeFirst() }
        }
        self.init(media: media, feature: feature, shelves: shelves)
    }
}

/// What a card or row shows under its title: your status when it's on your list, else the score (and year), else
/// what it is.
enum BrowseCaption: Equatable, Sendable {
    case status(ListStatus, MediaKind)
    case score(String, year: Int?)
    case text(String)

    static func of(_ t: Title, entry: LibraryEntry?, withYear: Bool = false) -> BrowseCaption {
        if let e = entry { return .status(e.status, e.media) }
        if let s = t.score { return .score(Format.average(s), year: withYear ? t.year : nil) }
        if t.media == .anime && t.format == "Film" { return .text("Film") }
        if let n = t.next { return .text("Starts \(Format.shortDay(n.at))") }
        if t.state == "Not yet released", let y = t.year { return .text(String(y)) }
        return .text(t.format ?? t.media.singular)
    }

    /// TMDB's "Sci-Fi & Fantasy" reads as "Sci-Fi" in a short line
    static func shortGenre(_ g: String) -> String {
        g.components(separatedBy: " & ").first ?? g
    }
}

/// "Plan to Watch" / "Plan to Read": the button that adds a title not yet on your list
enum BrowseAdd {
    static func label(_ media: MediaKind) -> String { ListStatus.planned.label(media) }
    static var patch: LibraryPatch { LibraryPatch(status: .planned) }
}

// MARK: filters

/// `BrowseSearch` without its media: the filters sheet (13), the chips under the media switch and a shelf's filter.
/// Sent as the results' query; the app applies the same rules again (the website's `filterTitles`), so the demo's
/// recorded catalogue and the sheet's count agree.
struct BrowseFilters: Codable, Equatable, Hashable, Sendable {
    /// `SortKey`
    enum Sort: String, Codable, CaseIterable, Identifiable, Sendable {
        case popular, top, new, trending

        var id: String { rawValue }

        var label: String {
            switch self {
            case .popular: return "Popularity"
            case .top: return "Top rated"
            case .new: return "Newest"
            case .trending: return "Trending"
            }
        }
    }

    var q: String?
    /// comma list on the wire; every one must match
    var genres: [String] = []
    var tags: [String] = []
    var from: Int?
    var to: Int?
    var season: CatalogSeason?
    var format: String?
    var status: CatalogStatus?
    /// the least score, on the 10-point scale (8, 8.5)
    var score: Double?
    /// nil: the catalogue's own order (popularity)
    var sort: Sort?

    init(q: String? = nil, genres: [String] = [], tags: [String] = [], from: Int? = nil, to: Int? = nil,
         season: CatalogSeason? = nil, format: String? = nil, status: CatalogStatus? = nil, score: Double? = nil,
         sort: Sort? = nil) {
        self.q = q
        self.genres = genres
        self.tags = tags
        self.from = from
        self.to = to
        self.season = season
        self.format = format
        self.status = status
        self.score = score
        self.sort = sort
    }

    private enum Keys: String, CodingKey { case q, genres, tags, from, to, season, format, status, score, sort }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func list(_ k: Keys) throws -> [String] { Self.list(try c.decodeIfPresent(String.self, forKey: k)) }
        q = try c.decodeIfPresent(String.self, forKey: .q)
        genres = try list(.genres)
        tags = try list(.tags)
        from = try c.decodeIfPresent(Int.self, forKey: .from)
        to = try c.decodeIfPresent(Int.self, forKey: .to)
        season = (try? c.decodeIfPresent(CatalogSeason.self, forKey: .season)) ?? nil
        format = try c.decodeIfPresent(String.self, forKey: .format)
        status = (try? c.decodeIfPresent(CatalogStatus.self, forKey: .status)) ?? nil
        score = try c.decodeIfPresent(Double.self, forKey: .score)
        sort = (try? c.decodeIfPresent(Sort.self, forKey: .sort)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(q, forKey: .q)
        try c.encodeIfPresent(genres.isEmpty ? nil : genres.joined(separator: ","), forKey: .genres)
        try c.encodeIfPresent(tags.isEmpty ? nil : tags.joined(separator: ","), forKey: .tags)
        try c.encodeIfPresent(from, forKey: .from)
        try c.encodeIfPresent(to, forKey: .to)
        try c.encodeIfPresent(season, forKey: .season)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encodeIfPresent(sort, forKey: .sort)
    }

    /// `listOf`
    static func list(_ s: String?) -> [String] {
        (s ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    /// nothing narrows the catalogue (the sort alone doesn't count)
    var isEmpty: Bool {
        (q ?? "").isEmpty && genres.isEmpty && tags.isEmpty && from == nil && to == nil && season == nil
            && format == nil && status == nil && score == nil
    }

    /// how many filters are on (genres count once, tags once, the years once)
    var count: Int {
        [!genres.isEmpty, !tags.isEmpty, from != nil || to != nil, season != nil, format != nil, status != nil,
         score != nil].filter { $0 }.count
    }

    // the choices, per media

    static let scoreSteps: [Double] = [6, 7, 8]

    static func hasSeason(_ m: MediaKind) -> Bool { m == .anime }

    /// the year slider's ends: the left end means "any year before", the right end "up to now and coming"
    static let firstYear = 2010
    static var lastYear: Int { Clock.calendar.component(.year, from: Clock.now) }

    /// "2020 – 2026" (to now), "Up to 2015", "Any year"
    var yearLabel: String {
        switch (from, to) {
        case (nil, nil): return "Any year"
        case (nil, let b?): return "Up to \(b)"
        default:
            let r = yearRange
            return r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound) – \(r.upperBound)"
        }
    }

    /// what the year slider shows: the limits, or its ends
    var yearRange: ClosedRange<Int> {
        let lo = from ?? Self.firstYear, hi = to ?? Self.lastYear
        return min(lo, hi)...max(lo, hi)
    }

    /// the slider moved: an end at the slider's end means no limit
    mutating func setYears(_ r: ClosedRange<Int>) {
        from = r.lowerBound <= Self.firstYear ? nil : r.lowerBound
        to = r.upperBound >= Self.lastYear ? nil : r.upperBound
    }

    mutating func toggleGenre(_ g: String) { genres.browseToggle(g) }
    mutating func toggleTag(_ t: String) { tags.browseToggle(t) }

    /// "Genres", "Action", "Action +2": a chip's text
    static func chipText(_ name: String, _ picked: [String]) -> String {
        guard let first = picked.first else { return name }
        return picked.count == 1 ? first : "\(first) +\(picked.count - 1)"
    }

    /// "★ 8+", "★ 8.5+"
    static func scoreText(_ s: Double) -> String { "★ \(Format.trim(s))+" }

    // the query (sent to the server, and the saved form)

    /// the results' query: the sort first (the demo picks its answer by the first value), the page only past 1
    func query(page: Int = 1) -> [URLQueryItem] {
        var q: [URLQueryItem] = []
        func add(_ name: String, _ v: String?) { if let v, !v.isEmpty { q.append(URLQueryItem(name: name, value: v)) } }
        add("sort", sort?.rawValue)
        add("q", self.q?.trimmingCharacters(in: .whitespaces))
        add("genres", genres.isEmpty ? nil : genres.joined(separator: ","))
        add("tags", tags.isEmpty ? nil : tags.joined(separator: ","))
        add("format", format)
        add("from", from.map(String.init))
        add("to", to.map(String.init))
        add("season", season?.rawValue)
        add("status", status?.rawValue)
        add("score", score.map(Format.trim))
        if page > 1 { add("page", String(page)) }
        return q
    }

    /// "sort=top&genres=Action,Drama&from=2020&season=fall": the saved form, as the website's address has it
    var encoded: String {
        query().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    /// back from `encoded`, keeping only values that make sense (`validateBrowse`)
    init(encoded s: String) {
        self.init()
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let v = kv[1].trimmingCharacters(in: .whitespaces)
            func year() -> Int? { Int(v).flatMap { $0 > 1800 && $0 < 2100 ? $0 : nil } }
            switch kv[0] {
            case "q": q = v.isEmpty ? nil : v
            case "genres": genres = Self.list(v)
            case "tags": tags = Self.list(v)
            case "from": from = year()
            case "to": to = year()
            case "season": season = CatalogSeason(rawValue: v)
            case "format": format = v.isEmpty ? nil : v
            case "status": status = CatalogStatus(rawValue: v)
            case "score": score = Double(v).flatMap { $0 > 0 && $0 <= 10 ? $0 : nil }
            case "sort": sort = Sort(rawValue: v)
            default: break
            }
        }
    }

    // applying them

    /// `filterTitles`: the titles a search keeps (all genres and tags must match)
    func matches(_ t: CatalogTitle) -> Bool {
        let q = Catalog.plain(self.q ?? "")
        if !q.isEmpty {
            let names = [t.title] + (t.alt ?? []) + [t.by]
            if !names.contains(where: { Catalog.plain($0).contains(q) }) { return false }
        }
        if !genres.allSatisfy(t.genres.contains) { return false }
        if !tags.allSatisfy(t.tags.contains) { return false }
        if let from { guard let y = t.year, y >= from else { return false } }
        if let to { guard let y = t.year, y <= to else { return false } }
        if let season, t.season != season { return false }
        if let format, t.format != format { return false }
        if let status, t.status != status { return false }
        if let score { guard let s = t.score, s >= score * 10 else { return false } }
        return true
    }

    /// the titles kept, in the sort's order (ties keep the server's order)
    func apply(_ titles: [CatalogTitle]) -> [CatalogTitle] {
        let kept = titles.filter(matches)
        func by(_ key: (CatalogTitle) -> Double) -> [CatalogTitle] {
            kept.enumerated().sorted { a, b in
                let x = key(a.element), y = key(b.element)
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
        switch sort {
        case nil: return kept
        case .popular: return by(\.popularity)
        case .top: return by { $0.score ?? -1 }
        case .trending: return by(\.trending)
        case .new:
            return kept.enumerated().sorted { a, b in
                let x = a.element.start ?? "", y = b.element.start ?? ""
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
    }
}

fileprivate extension Array where Element == String {
    /// add it if it's missing, take it out if it's there
    mutating func browseToggle(_ s: String) {
        if let i = firstIndex(of: s) { remove(at: i) } else { append(s) }
    }
}

/// The filters for every media, kept in one string (UserDefaults, through @AppStorage) so Browse and the filters
/// sheet share them: "anime:genres=Action,Drama&season=fall|tv:sort=top".
enum BrowseFilterStore {
    static let key = "browse.filters"

    /// what's saved before anything is: nothing, or the demo's -browse-filters flag (the screen tests' preset)
    static var initial: String { Demo.isOn ? (Demo.value("-browse-filters") ?? "") : "" }

    static func decode(_ s: String) -> [MediaKind: BrowseFilters] {
        var out: [MediaKind: BrowseFilters] = [:]
        for part in s.split(separator: "|") {
            let kv = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard let m = kv.first.flatMap(MediaKind.init(rawValue:)) else { continue }
            out[m] = BrowseFilters(encoded: kv.count > 1 ? kv[1] : "")
        }
        return out
    }

    static func encode(_ all: [MediaKind: BrowseFilters]) -> String {
        MediaKind.allCases.compactMap { m in
            guard let f = all[m], f != BrowseFilters() else { return nil }
            return "\(m.rawValue):\(f.encoded)"
        }.joined(separator: "|")
    }

    static func get(_ s: String, _ m: MediaKind) -> BrowseFilters { decode(s)[m] ?? BrowseFilters() }

    static func set(_ s: String, _ m: MediaKind, _ f: BrowseFilters) -> String {
        var all = decode(s)
        all[m] = f
        return encode(all)
    }
}

/// One page of results as the screen shows them, and how many there are.
struct BrowseResultsPage: Equatable, Sendable {
    var titles: [Title]
    /// the server's count, or what's here when it's all here
    var total: Int?
    var more: Bool
    var next: Int?

    init(titles: [Title], total: Int?, more: Bool, next: Int?) {
        self.titles = titles
        self.total = total
        self.more = more
        self.next = next
    }

    /// the answer with the filters applied again (a no-op on a real server; the demo's catalogue isn't filtered)
    init(_ media: MediaKind, _ answer: BrowseResults, _ f: BrowseFilters) {
        let kept = f.apply(answer.titles)
        let filtered = kept.count != answer.titles.count
        titles = kept.map { $0.title(media.api) }
        more = filtered ? false : answer.more
        next = filtered ? nil : answer.next
        if filtered { total = kept.count } else { total = answer.total ?? (answer.more ? nil : kept.count) }
    }

    /// "Show 120 results", "Show 50+ results"
    var showText: String {
        if let total { return "Show \(Format.grouped(total)) \(total == 1 ? "result" : "results")" }
        return "Show \(Format.grouped(titles.count))\(more ? "+" : "") results"
    }
}

// MARK: the season chart

/// `SeasonEntry`: a season chart anime, its catalogue card plus its next episode
struct SeasonEntry: Codable, Hashable, Sendable {
    var title: CatalogTitle
    var next: Next?
    /// started in an earlier season and still airing
    var carried: Bool

    struct Next: Codable, Hashable, Sendable {
        var episode: Int
        /// unix seconds (not ms)
        var at: Double
    }

    private enum Keys: String, CodingKey { case next, carried }

    init(title: CatalogTitle, next: Next? = nil, carried: Bool = false) {
        self.title = title
        self.next = next
        self.carried = carried
    }

    init(from decoder: Decoder) throws {
        title = try CatalogTitle(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        next = try c.decodeIfPresent(Next.self, forKey: .next)
        carried = try c.decodeIfPresent(Bool.self, forKey: .carried) ?? false
    }

    func encode(to encoder: Encoder) throws {
        try title.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(next, forKey: .next)
        try c.encode(carried, forKey: .carried)
    }

    var app: Title {
        title.title(.anime, next: next.map { Airing(episode: $0.episode, at: Date(timeIntervalSince1970: $0.at)) })
    }
}

/// `GET season-chart?season=fall&year=2026`: every anime of one season (14), most popular first.
struct SeasonChart: Codable, Equatable, Sendable {
    var season: CatalogSeason
    var year: Int
    var titles: [SeasonEntry]

    /// "Fall 2026"
    var label: String { "\(season.label) \(year)" }

    /// one season: Fall 2026
    struct Ref: Hashable, Sendable {
        var season: CatalogSeason
        var year: Int

        var label: String { "\(season.label) \(year)" }
        /// "fall-2026", the page's id
        var slug: String { "\(season.rawValue)-\(year)" }

        private var index: Int { CatalogSeason.allCases.firstIndex(of: season) ?? 0 }

        var previous: Ref {
            index == 0 ? Ref(season: .fall, year: year - 1) : Ref(season: CatalogSeason.allCases[index - 1], year: year)
        }

        var next: Ref {
            index == 3 ? Ref(season: .winter, year: year + 1) : Ref(season: CatalogSeason.allCases[index + 1], year: year)
        }

        /// the website's `currentSeason`: January–March is Winter, and so on
        static func of(_ d: Date) -> Ref {
            let c = Clock.calendar
            let m = c.component(.month, from: d), y = c.component(.year, from: d)
            return Ref(season: CatalogSeason.allCases[(m - 1) / 3], year: y)
        }

        static var current: Ref { of(Clock.now) }
    }

    /// the format switch: All, then the website's groups (TV, ONA, Film, OVA & Special)
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all, tv, ona, film, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .tv: return "TV"
            case .ona: return "ONA"
            case .film: return "Film"
            case .other: return "OVA & Special"
            }
        }

        /// the switch's shorter word
        var short: String { self == .other ? "Other" : label }

        static func of(_ t: Title) -> Kind {
            switch t.format {
            case "TV": return .tv
            case "ONA": return .ona
            case "Film": return .film
            default: return .other
            }
        }
    }

    enum Order: String, CaseIterable, Identifiable, Sendable {
        case popularity, score, airing, title

        var id: String { rawValue }

        var label: String {
            switch self {
            case .popularity: return "Popularity"
            case .score: return "Score"
            case .airing: return "Next episode"
            case .title: return "Title"
            }
        }
    }

    struct Group: Identifiable, Equatable, Sendable {
        var kind: Kind
        var titles: [Title]

        var id: Kind { kind }
        var label: String { kind.label }
    }

    /// the rows as the app's titles
    var rows: [Title] { titles.map(\.app) }

    func count(_ k: Kind) -> Int { k == .all ? titles.count : rows.filter { Kind.of($0) == k }.count }

    /// the switch's segments with counts ("All 50", "TV 31"); empty kinds are left out
    var kinds: [(Kind, Int)] {
        Kind.allCases.map { ($0, count($0)) }.filter { $0.0 == .all || $0.1 > 0 }
    }

    /// "Anime season · 50 anime"
    var subtitle: String { "Anime season · \(titles.count) anime" }

    /// the rows under their format, in the switch's order; `hide` leaves out what's on your list
    func groups(_ k: Kind, order: Order = .popularity, hide: Set<String> = [], now: Date = Clock.now) -> [Group] {
        let kept = rows.filter { !hide.contains($0.id) }
        let kinds = k == .all ? Kind.allCases.filter { $0 != .all } : [k]
        return kinds.compactMap { kind in
            let rows = Self.ordered(kept.filter { Kind.of($0) == kind }, order, now: now)
            return rows.isEmpty ? nil : Group(kind: kind, titles: rows)
        }
    }

    static func ordered(_ ts: [Title], _ o: Order, now: Date) -> [Title] {
        let indexed = Array(ts.enumerated())
        func by(_ key: (Title) -> Double) -> [Title] {
            indexed.sorted { a, b in
                let x = key(a.element), y = key(b.element)
                return x != y ? x < y : a.offset < b.offset
            }.map(\.element)
        }
        switch o {
        case .popularity: return ts
        case .score: return by { -($0.score ?? -1) }
        case .airing: return by { $0.next.map { $0.at.timeIntervalSince(now) } ?? .greatestFiniteMagnitude }
        case .title: return ts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// "OLM · 12 episodes" (the genres follow in a lighter colour)
    static func facts(_ t: Title) -> String {
        var parts: [String] = []
        if let s = t.studio { parts.append(s) }
        if t.format == "Film" {
            parts.append(t.runtime ?? "Film")
        } else {
            parts.append(t.total.map { t.media.units($0) } ?? "? episodes")
        }
        return parts.joined(separator: " · ")
    }

    static func genres(_ t: Title) -> String { (t.genres ?? []).prefix(2).joined(separator: ", ") }

    /// the line with the calendar: "Ep 6 · Fri 9:00 AM · in 3 days", "All 10 out", or nil
    static func airing(_ t: Title, now: Date = Clock.now) -> (symbol: String, text: String)? {
        if let n = t.next {
            if t.state == "Not yet released" && n.episode <= 1 {
                return ("calendar", "Starts \(Format.weekday(n.at)) \(Format.shortDay(n.at)) · \(Format.until(n.at, now: now))")
            }
            return ("calendar.badge.clock", Format.airing(n, media: t.media, now: now))
        }
        if t.state == "Finished" {
            if t.format == "Film" { return ("checkmark", "Out now") }
            if let total = t.total { return ("checkmark", "All \(total) out") }
            return ("checkmark", "Finished")
        }
        return nil
    }
}

// MARK: search (§8.2)

/// `GET search?q=`: `{ groups }`, each group's best few hits (titles, characters, people)
struct SearchAnswer: Codable, Equatable, Sendable {
    var groups: [SearchGroup]
}

/// `SearchGroup`: "Anime", "Manga", "TV", "Movies", "Books", "Characters", "People"
struct SearchGroup: Codable, Hashable, Sendable {
    var title: String
    var hits: [SearchHit]
}

/// `SearchHit`
struct SearchHit: Codable, Hashable, Sendable {
    var ref: CatalogRef
    var name: String
    var image: URL?
    /// "Anime · TV · 2013", "Voice actor", "Character · Attack on Titan"
    var note: String

    /// a title hit as the app's title (only what the hit carries)
    var title: Title? {
        guard let r = ref.titleRef else { return nil }
        return Title(id: r.titleId, media: r.kind, name: name, cover: image)
    }

    var route: Route? { ref.route }
}

/// One search as the screen shows it (15): chips per group, the top hit, then the groups.
struct SearchResults: Equatable, Sendable {
    var query: String
    var groups: [SearchGroup]

    init(query: String, groups: [SearchGroup]) {
        self.query = query
        self.groups = groups.filter { !$0.hits.isEmpty }
    }

    /// the first title of the first group
    var top: SearchHit? { groups.first?.hits.first { $0.title != nil } }

    var isEmpty: Bool { groups.isEmpty }

    /// the chips: All, then each group with how many hits it has
    var scopes: [(String, Int?)] {
        [("All", nil)] + groups.map { ($0.title, $0.hits.count) }
    }

    /// the groups a chip shows: All has every group (without the top hit), a group's chip that group
    func shown(_ scope: String) -> [SearchGroup] {
        if scope == "All" {
            return groups.compactMap { g in
                var g = g
                g.hits = g.hits.filter { $0 != top }
                return g.hits.isEmpty ? nil : g
            }
        }
        return groups.filter { $0.title == scope }
    }

    /// "Top hit · Anime · TV · 2013": the hit's own note after it
    static func topLine(_ h: SearchHit) -> String {
        h.note.isEmpty ? "Top hit" : "Top hit · " + h.note
    }
}

// MARK: calls

extension APIClient {
    /// GET browse/:media/shelves
    func browseShelves(_ media: MediaKind) async throws -> BrowseShelves {
        try await get("browse/\(media.api.rawValue)/shelves")
    }

    /// the shelves as the Browse page shows them
    func browsePage(_ media: MediaKind) async throws -> BrowsePage {
        BrowsePage(media, try await browseShelves(media))
    }

    /// GET browse/:media/filters
    func browseFacets(_ media: MediaKind) async throws -> Facets {
        try await get("browse/\(media.api.rawValue)/filters")
    }

    /// GET browse/:media/results?sort=…&genres=…&page=…
    func browseResults(_ media: MediaKind, _ f: BrowseFilters, page: Int = 1) async throws -> BrowseResults {
        try await get("browse/\(media.api.rawValue)/results", query: f.query(page: page))
    }

    /// one page of results, filtered as the website does
    func browseTitles(_ media: MediaKind, _ f: BrowseFilters, page: Int = 1) async throws -> BrowseResultsPage {
        BrowseResultsPage(media, try await browseResults(media, f, page: page), f)
    }

    /// GET season-chart?season=fall&year=2026 (the season first: the demo picks its answer by it)
    func seasonChart(_ s: SeasonChart.Ref) async throws -> SeasonChart {
        try await get("season-chart", query: [URLQueryItem(name: "season", value: s.season.rawValue),
                                              URLQueryItem(name: "year", value: String(s.year))])
    }

    /// GET search?q= (1–80 characters)
    func search(_ q: String) async throws -> SearchResults {
        let q = String(q.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let answer: SearchAnswer = try await get("search", query: [URLQueryItem(name: "q", value: q)])
        return SearchResults(query: q, groups: answer.groups)
    }
}
