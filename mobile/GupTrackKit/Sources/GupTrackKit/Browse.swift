import Foundation

// Browse (11-15): the media switch's shelves, the filters, the season chart and search. The decoding, filtering,
// grouping, counting and captions live here so they're tested on Linux; the views only draw them.

// MARK: the Browse page

/// GET browse?media=anime: one media's shelves, and a feature card for TMDB media (TV and films).
struct BrowsePage: Codable, Equatable, Sendable {
    var media: MediaKind
    var feature: Feature?
    var shelves: [Shelf]

    struct Shelf: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var sub: String?
        /// a page the header opens ("season-chart")
        var link: String?
        /// or: the whole catalogue in this order (the header shows it as results)
        var sort: BrowseFilters.Sort?
        var titles: [Title]

        var route: Route? { link.flatMap(Route.init(path:)) }
        var opens: Bool { route != nil || sort != nil }
    }

    /// the big card on top of TV and Movies ("Most added this week")
    struct Feature: Codable, Equatable, Sendable {
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
        if t.media == .anime && t.format == "Movie" { return .text("Film") }
        if let n = t.next { return .text("Starts \(Format.shortDay(n.at))") }
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

/// The filters sheet (13) and the chips under the media switch. Applied on top of the catalogue
/// (GET browse/titles?media=…&sort=…): the server filters, and the app applies the same filters again so the
/// demo's recorded catalogue and the sheet's live count agree.
struct BrowseFilters: Codable, Equatable, Hashable, Sendable {
    enum Sort: String, Codable, CaseIterable, Identifiable, Sendable {
        case popularity, score, newest, title

        var id: String { rawValue }

        var label: String {
            switch self {
            case .popularity: return "Popularity"
            case .score: return "Score"
            case .newest: return "Newest"
            case .title: return "Title"
            }
        }
    }

    var sort: Sort = .popularity
    var genres: [String] = []
    /// nil: no limit that side
    var yearFrom: Int?
    var yearTo: Int?
    /// "Winter", "Spring", "Summer", "Fall"; anime only
    var season: String?
    var formats: [String] = []
    var statuses: [String] = []
    /// out of 10; TV, films and books
    var minScore: Double?

    init(sort: Sort = .popularity, genres: [String] = [], yearFrom: Int? = nil, yearTo: Int? = nil,
         season: String? = nil, formats: [String] = [], statuses: [String] = [], minScore: Double? = nil) {
        self.sort = sort
        self.genres = genres
        self.yearFrom = yearFrom
        self.yearTo = yearTo
        self.season = season
        self.formats = formats
        self.statuses = statuses
        self.minScore = minScore
    }

    /// nothing narrows the catalogue (the sort alone doesn't count)
    var isEmpty: Bool {
        genres.isEmpty && yearFrom == nil && yearTo == nil && season == nil && formats.isEmpty && statuses.isEmpty
            && minScore == nil
    }

    /// how many filters are on (genres count once)
    var count: Int {
        [!genres.isEmpty, yearFrom != nil || yearTo != nil, season != nil, !formats.isEmpty, !statuses.isEmpty,
         minScore != nil].filter { $0 }.count
    }

    // the choices, per media

    static let seasons = ["Winter", "Spring", "Summer", "Fall"]
    static let scoreSteps: [Double] = [6, 7, 8]

    static func genreChoices(_ m: MediaKind) -> [String] {
        switch m {
        case .anime, .manga:
            return ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Psychological",
                    "Romance", "Sci-Fi", "Slice of Life", "Sports"]
        case .tv:
            return ["Action & Adventure", "Comedy", "Crime", "Drama", "Mystery", "Sci-Fi & Fantasy", "War & Politics"]
        case .movie:
            return ["Action", "Adventure", "Animation", "Comedy", "Crime", "Drama", "Horror", "Mystery", "Romance",
                    "Science Fiction", "Thriller", "War"]
        case .book:
            return ["Fantasy", "Science fiction", "Literature", "Thriller", "Adventure"]
        }
    }

    static func formatChoices(_ m: MediaKind) -> [String] {
        switch m {
        case .anime: return ["TV", "TV Short", "Movie", "Special", "OVA", "ONA"]
        case .manga: return ["Manga", "Light Novel", "One Shot"]
        default: return []
        }
    }

    static func statusChoices(_ m: MediaKind) -> [String] {
        switch m {
        case .anime, .tv: return ["Airing", "Finished", "Not yet aired", "Cancelled"]
        case .manga: return ["Releasing", "Finished", "Not yet released", "Hiatus"]
        case .movie: return ["Released", "Upcoming"]
        case .book: return []
        }
    }

    static func hasSeason(_ m: MediaKind) -> Bool { m == .anime }
    static func hasScore(_ m: MediaKind) -> Bool { m == .tv || m == .movie || m == .book }

    /// the year slider's ends: the left end means "any year before", the right end "up to now and coming"
    static let firstYear = 2010
    static var lastYear: Int { Clock.calendar.component(.year, from: Clock.now) }

    /// "2020 – 2026" (to now), "Up to 2015", "Any year"
    var yearLabel: String {
        switch (yearFrom, yearTo) {
        case (nil, nil): return "Any year"
        case (nil, let b?): return "Up to \(b)"
        default:
            let r = yearRange
            return r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound) – \(r.upperBound)"
        }
    }

    /// what the year slider shows: the limits, or its ends
    var yearRange: ClosedRange<Int> {
        let lo = yearFrom ?? Self.firstYear, hi = yearTo ?? Self.lastYear
        return min(lo, hi)...max(lo, hi)
    }

    /// the slider moved: an end at the slider's end means no limit
    mutating func setYears(_ r: ClosedRange<Int>) {
        yearFrom = r.lowerBound <= Self.firstYear ? nil : r.lowerBound
        yearTo = r.upperBound >= Self.lastYear ? nil : r.upperBound
    }

    mutating func toggleGenre(_ g: String) { genres.browseToggle(g) }
    mutating func toggleFormat(_ f: String) { formats.browseToggle(f) }
    mutating func toggleStatus(_ s: String) { statuses.browseToggle(s) }

    /// "Genres", "Action", "Action +2": a chip's text
    static func chipText(_ name: String, _ picked: [String]) -> String {
        guard let first = picked.first else { return name }
        return picked.count == 1 ? first : "\(first) +\(picked.count - 1)"
    }

    // the query (sent to the server, and the demo's saved form)

    func query(_ media: MediaKind) -> [URLQueryItem] {
        var q = [URLQueryItem(name: "media", value: media.rawValue)]
        if sort != .popularity { q.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        if !genres.isEmpty { q.append(URLQueryItem(name: "genres", value: genres.joined(separator: ","))) }
        if yearFrom != nil || yearTo != nil {
            q.append(URLQueryItem(name: "years", value: "\(yearFrom.map(String.init) ?? "")-\(yearTo.map(String.init) ?? "")"))
        }
        if let season { q.append(URLQueryItem(name: "season", value: season)) }
        if !formats.isEmpty { q.append(URLQueryItem(name: "formats", value: formats.joined(separator: ","))) }
        if !statuses.isEmpty { q.append(URLQueryItem(name: "statuses", value: statuses.joined(separator: ","))) }
        if let minScore { q.append(URLQueryItem(name: "minScore", value: Format.trim(minScore))) }
        return q
    }

    /// "sort=score&genres=Action,Drama&years=2020-2026&season=Fall" (the media is left out)
    var encoded: String {
        query(.anime).dropFirst().map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    init(encoded s: String) {
        self.init()
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            let list = kv[1].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            switch kv[0] {
            case "sort": sort = Sort(rawValue: kv[1]) ?? .popularity
            case "genres": genres = list
            case "years":
                let ends = kv[1].split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
                if ends.count == 2 { yearFrom = ends[0]; yearTo = ends[1] }
            case "season": season = Self.seasons.contains(kv[1]) ? kv[1] : nil
            case "formats": formats = list
            case "statuses": statuses = list
            case "minScore": minScore = Double(kv[1])
            default: break
            }
        }
    }

    // applying them

    func matches(_ t: Title) -> Bool {
        if !genres.isEmpty {
            let have = (t.genres ?? []).map { $0.lowercased() }
            // every picked genre, as AniList's genre filter does; books match a subject that contains it
            for g in genres where !have.contains(where: { $0 == g.lowercased() || (t.media == .book && $0.contains(g.lowercased())) }) {
                return false
            }
        }
        if yearFrom != nil || yearTo != nil {
            guard let y = t.year else { return false }
            if let a = yearFrom, y < a { return false }
            if let b = yearTo, y > b { return false }
        }
        if let season {
            guard let s = t.season, s.hasPrefix(season + " ") else { return false }
        }
        if !formats.isEmpty {
            guard let f = t.format, formats.contains(f) else { return false }
        }
        if !statuses.isEmpty, let state = Self.statusWord(t) {
            // a title whose state isn't known (TMDB's catalogue doesn't say) isn't left out
            if !statuses.contains(state) { return false }
        }
        if let minScore {
            guard let s = t.score, s >= minScore else { return false }
        }
        return true
    }

    /// the catalogue filtered and sorted (popularity keeps the server's order)
    func apply(_ titles: [Title]) -> [Title] {
        let kept = titles.filter(matches)
        switch sort {
        case .popularity: return kept
        case .score: return kept.enumerated().sorted { a, b in
            let x = a.element.score ?? -1, y = b.element.score ?? -1
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
        case .newest: return kept.enumerated().sorted { a, b in
            let x = a.element.year ?? 0, y = b.element.year ?? 0
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
        case .title: return kept.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    /// a title's state in the status filter's words ("Releasing" is "Airing" for anime and TV)
    static func statusWord(_ t: Title) -> String? {
        guard let s = t.state else { return nil }
        switch (t.media, s) {
        case (.anime, "Releasing"), (.tv, "Releasing"), (.tv, "Returning Series"): return "Airing"
        case (.anime, "Not yet released"), (.tv, "Not yet released"): return "Not yet aired"
        case (.tv, "Ended"): return "Finished"
        case (.movie, "Not yet released"): return "Upcoming"
        default: return s
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
/// sheet share them: "anime:genres=Action,Drama&season=Fall|tv:sort=score".
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

// MARK: the season chart

/// GET season-chart?season=fall-2026: every anime of one season (14), most popular first.
struct SeasonChart: Codable, Equatable, Sendable {
    /// "Fall 2026"
    var season: String
    var titles: [Title]

    /// one season: Fall 2026
    struct Ref: Hashable, Sendable {
        var name: String     // "Winter", "Spring", "Summer", "Fall"
        var year: Int

        var label: String { "\(name) \(year)" }
        /// "fall-2026", the API's form
        var slug: String { "\(name.lowercased())-\(year)" }

        private var index: Int { BrowseFilters.seasons.firstIndex(of: name) ?? 0 }

        var previous: Ref {
            index == 0 ? Ref(name: "Fall", year: year - 1) : Ref(name: BrowseFilters.seasons[index - 1], year: year)
        }

        var next: Ref {
            index == 3 ? Ref(name: "Winter", year: year + 1) : Ref(name: BrowseFilters.seasons[index + 1], year: year)
        }

        /// the anime season a day falls in (AniList's: Winter is Dec–Feb, counted in the new year)
        static func of(_ d: Date) -> Ref {
            let c = Clock.calendar
            let m = c.component(.month, from: d), y = c.component(.year, from: d)
            switch m {
            case 12: return Ref(name: "Winter", year: y + 1)
            case 1, 2: return Ref(name: "Winter", year: y)
            case 3...5: return Ref(name: "Spring", year: y)
            case 6...8: return Ref(name: "Summer", year: y)
            default: return Ref(name: "Fall", year: y)
            }
        }

        static var current: Ref { of(Clock.now) }
    }

    /// the format switch: All, TV, ONA, Movies, Other
    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case all, tv, ona, movies, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .tv: return "TV"
            case .ona: return "ONA"
            case .movies: return "Movies"
            case .other: return "Other"
            }
        }

        static func of(_ t: Title) -> Kind {
            switch t.format {
            case "TV": return .tv
            case "ONA": return .ona
            case "Movie": return .movies
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

    func count(_ k: Kind) -> Int { k == .all ? titles.count : titles.filter { Kind.of($0) == k }.count }

    /// the switch's segments with counts ("All 50", "TV 31"); empty kinds are left out
    var kinds: [(Kind, Int)] {
        Kind.allCases.map { ($0, count($0)) }.filter { $0.0 == .all || $0.1 > 0 }
    }

    /// "Anime season · 50 anime"
    var subtitle: String { "Anime season · \(titles.count) anime" }

    /// the rows under their format, in the switch's order; `notListed` keeps only what isn't on your list
    func groups(_ k: Kind, order: Order = .popularity, hide: Set<String> = [], now: Date = Clock.now) -> [Group] {
        let kept = titles.filter { !hide.contains($0.id) }
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
        if t.format == "Movie" {
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
            if t.format == "Movie" { return ("checkmark", "Out now") }
            if let total = t.total { return ("checkmark", "All \(total) out") }
            return ("checkmark", "Finished")
        }
        return nil
    }
}

extension APIClient {
    func browsePage(_ media: MediaKind) async throws -> BrowsePage {
        try await get("browse", query: [URLQueryItem(name: "media", value: media.rawValue)])
    }

    /// the catalogue with filters (the media first: the demo picks its answer by it)
    func browseTitles(_ media: MediaKind, _ f: BrowseFilters) async throws -> [Title] {
        f.apply(try await get("browse/titles", query: f.query(media)))
    }

    func seasonChart(_ s: SeasonChart.Ref) async throws -> SeasonChart {
        try await get("season-chart", query: [URLQueryItem(name: "season", value: s.slug)])
    }

    func search(_ q: String) async throws -> SearchResults {
        try await get("search", query: [URLQueryItem(name: "q", value: q)])
    }
}

// MARK: search

/// GET search?q=chain: one search across every media and people (15).
struct SearchResults: Codable, Equatable, Sendable {
    var query: String
    var top: Title?
    var groups: [Group]

    enum Scope: String, Codable, CaseIterable, Identifiable, Sendable {
        case all, anime, manga, tv, movie, book, people

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .anime: return "Anime"
            case .manga: return "Manga"
            case .tv: return "TV"
            case .movie: return "Movies"
            case .book: return "Books"
            case .people: return "People"
            }
        }
    }

    struct Group: Codable, Equatable, Sendable, Identifiable {
        var scope: Scope
        /// how many the server found (it may send fewer)
        var total: Int
        var titles: [Title]
        var people: [Person]

        var id: Scope { scope }
        var isEmpty: Bool { titles.isEmpty && people.isEmpty }
    }

    /// someone in the results: staff, an actor, an author
    struct Person: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var image: URL?
        /// "Mangaka · Chainsaw Man, Fire Punch"
        var caption: String
        /// the page it opens ("person/person:119917")
        var link: String

        var route: Route? { Route(path: link) }
    }

    var isEmpty: Bool { top == nil && groups.allSatisfy(\.isEmpty) }

    /// the scope chips: All, then each group with its count
    var scopes: [(Scope, Int?)] {
        [(.all, nil)] + groups.filter { !$0.isEmpty }.map { ($0.scope, $0.total) }
    }

    /// the groups a scope shows: All has every group (without the top hit, a few rows each), a scope its own, whole
    func shown(_ scope: Scope, perGroup: Int = 3) -> [Group] {
        if scope == .all {
            return groups.compactMap { g in
                var g = g
                g.titles = Array(g.titles.filter { $0.id != top?.id }.prefix(perGroup))
                g.people = Array(g.people.prefix(perGroup))
                return g.isEmpty ? nil : g
            }
        }
        return groups.filter { $0.scope == scope && !$0.isEmpty }
    }

    /// "Top hit · Anime · 2022"
    static func topLine(_ t: Title) -> String {
        var parts = ["Top hit", kindWord(t)]
        if let y = t.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    /// "MAPPA · 12 episodes" under the top hit (its score follows)
    static func topFacts(_ t: Title) -> String {
        var parts: [String] = []
        if let s = t.studio { parts.append(s) }
        if let n = t.total, t.media.unit != nil, t.format != "Movie" { parts.append(t.media.units(n)) }
        else if let r = t.runtime, t.media == .movie || t.format == "Movie" { parts.append(r) }
        return parts.joined(separator: " · ")
    }

    /// a result row's caption: "Film · 2025 · MAPPA", "Manga · 2018 · 232 chapters", "Anime · Not yet aired · MAPPA"
    static func caption(_ t: Title) -> String {
        var parts = [kindWord(t)]
        if t.state == "Not yet released" {
            parts.append(t.media == .anime || t.media == .tv ? "Not yet aired" : "Not yet released")
        } else if let y = t.year {
            parts.append(String(y))
        }
        switch t.media {
        case .manga: if let n = t.total { parts.append(t.media.units(n)) }
        case .movie: if let r = t.runtime { parts.append(r) }
        case .tv: if let n = t.total { parts.append(t.media.units(n)) } else if let s = t.studio { parts.append(s) }
        case .anime, .book: if let s = t.studio { parts.append(s) }
        }
        return parts.joined(separator: " · ")
    }

    /// what a title is, in a word: anime films are "Film" (they stay under Anime)
    static func kindWord(_ t: Title) -> String {
        if t.media == .anime && t.format == "Movie" { return "Film" }
        if t.media == .manga, let f = t.format, f != "Manga" { return f }
        return t.media.singular
    }
}
