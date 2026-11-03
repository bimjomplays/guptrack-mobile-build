import Foundation

// A title's own page (16-25): everything one layout needs for every media, and the words and numbers it shows.
// GET titles/<id> answers a TitlePage; GET titles/<id>/seasons/<n> a TVSeason with its episodes. "Your list" (status,
// progress, score) is the offline library's, not the page's, so the page works and edits offline.
//
// Ids of the people around a title (the routes they open):
//   character:<anilistId>                .character   (AniList characters)
//   person:<anilistStaffId>              .person      (AniList staff and voice actors)
//   person:tmdb-<tmdbPersonId>           .person      (TMDB cast and crew)
//   studio:<anilistStudioId>             .studio      (AniList studios)
//   studio:tmdb-<companyOrNetworkId>     .studio      (TMDB networks and companies)
//   author:<openLibraryAuthorKey>        .author      (Open Library authors)

/// GET titles/<id>
struct TitlePage: Codable, Equatable, Sendable {
    var title: Title
    /// the story (plain text, paragraphs split by blank lines)
    var description: String?
    /// a film's tagline ("Long live the fighters.")
    var tagline: String?
    var trailer: URL?
    /// who made it, on the hero's second line: the studio, the show's creator, the director, the author
    var creator: Credit?
    /// "2026-09-25"; endDate nil while it runs
    var startDate: String?
    var endDate: String?
    /// what it's adapted from ("Manga", "Original")
    var source: String?
    /// how many people have it on a list (the score average's "48,869 members")
    var members: Int?
    /// how the scores spread, 10...100
    var scores: [ScoreBar]?
    /// a book's subjects as Open Library has them (cleaned up for show by `subjectTags`)
    var subjects: [String]?
    var characters: [Character]?
    var cast: [Credit]?
    /// "Denis Villeneuve · Director", "Jon Spaihts, Denis Villeneuve · Screenplay"
    var crew: [Credit]?
    /// the makers shown as rows (a manga's "Tatsuki Fujimoto · Story & Art", a book's author)
    var staff: [Credit]?
    var studios: [Credit]?
    var relations: [Relation]?
    var recommendations: [Title]?
    /// a show's seasons (no specials), oldest first
    var seasons: [TVSeason]?
    /// the title on other sites (AniList, MyAnimeList, TMDB, Open Library), for the ••• menu
    var links: [Link]?
    /// how many reviews it has on GupTrack
    var reviews: Int?

    init(title: Title, description: String? = nil, tagline: String? = nil, trailer: URL? = nil, creator: Credit? = nil,
         startDate: String? = nil, endDate: String? = nil, source: String? = nil, members: Int? = nil,
         scores: [ScoreBar]? = nil, subjects: [String]? = nil, characters: [Character]? = nil, cast: [Credit]? = nil,
         crew: [Credit]? = nil, staff: [Credit]? = nil, studios: [Credit]? = nil, relations: [Relation]? = nil,
         recommendations: [Title]? = nil, seasons: [TVSeason]? = nil, links: [Link]? = nil, reviews: Int? = nil) {
        self.title = title
        self.description = description
        self.tagline = tagline
        self.trailer = trailer
        self.creator = creator
        self.startDate = startDate
        self.endDate = endDate
        self.source = source
        self.members = members
        self.scores = scores
        self.subjects = subjects
        self.characters = characters
        self.cast = cast
        self.crew = crew
        self.staff = staff
        self.studios = studios
        self.relations = relations
        self.recommendations = recommendations
        self.seasons = seasons
        self.links = links
        self.reviews = reviews
    }

    /// Someone (or a studio) credited on a title. `ref` is the page id it opens ("person:97619"); nil when there's
    /// no page for them.
    struct Credit: Codable, Equatable, Hashable, Sendable {
        var ref: String?
        var name: String
        var image: URL?
        /// the character played, the job ("Director"), "Story & Art"
        var role: String?

        var route: Route? { ref.flatMap(TitlePage.route(for:)) }
    }

    /// A character with the voice behind them.
    struct Character: Codable, Equatable, Hashable, Sendable {
        var ref: String
        var name: String
        var image: URL?
        /// "Main", "Supporting"
        var role: String?
        var voice: Credit?

        var route: Route? { TitlePage.route(for: ref) }
    }

    /// Another title it's tied to: "Prequel", "Sequel", "Source", "Side story"…
    struct Relation: Codable, Equatable, Hashable, Sendable {
        var relation: String
        var title: Title
    }

    /// How many gave a score (10, 20 … 100).
    struct ScoreBar: Codable, Equatable, Hashable, Sendable {
        var score: Int
        var amount: Int
    }

    struct Link: Codable, Equatable, Hashable, Sendable {
        /// "AniList", "MyAnimeList", "TMDB", "Open Library"
        var label: String
        var url: URL
    }

    /// a page from only a Title (the library's copy when the page can't load)
    static func basic(_ t: Title) -> TitlePage { TitlePage(title: t) }
}

/// One season of a show. On a title page `episodes` may be short (number, name, runtime); GET
/// titles/<id>/seasons/<n> gives them in full.
struct TVSeason: Codable, Equatable, Hashable, Sendable, Identifiable {
    var number: Int
    var name: String
    var poster: URL?
    var year: Int?
    /// episodes in the season (aired or announced)
    var count: Int
    var episodes: [Episode]?

    var id: Int { number }

    struct Episode: Codable, Equatable, Hashable, Sendable, Identifiable {
        var number: Int
        var name: String
        var still: URL?
        /// "2025-01-30"
        var aired: String?
        /// "57m"
        var runtime: String?
        var overview: String?

        var id: Int { number }

        /// "Jan 30, 2025 · 57m"
        var line: String {
            var parts: [String] = []
            if let a = aired, let d = Format.parseDay(a) { parts.append(Format.longDay(d)) }
            if let r = runtime, !r.isEmpty { parts.append(r) }
            return parts.joined(separator: " · ")
        }
    }
}

/// GET titles/<id>/seasons/<n>: a season in full, with the show and every season's size (to place progress).
struct TVSeasonPage: Codable, Equatable, Sendable {
    var show: Title
    var season: TVSeason
    var seasons: [TVSeason]
}

extension APIClient {
    func titlePage(_ id: String) async throws -> TitlePage { try await get("titles/" + id) }

    func tvSeason(_ id: String, _ number: Int) async throws -> TVSeasonPage {
        try await get("titles/\(id)/seasons/\(number)")
    }
}

// MARK: - the page's words

extension TitlePage {
    /// the page a credit's id opens: "person:97619" -> .person("person:97619")
    static func route(for ref: String) -> Route? {
        guard let kind = ref.split(separator: ":", maxSplits: 1).first, ref.count > kind.count + 1 else { return nil }
        switch kind {
        case "character": return .character(ref)
        case "person": return .person(ref)
        case "studio": return .studio(ref)
        case "author": return .author(ref)
        default: return nil
        }
    }

    /// a format as the page writes it: anime films are "Film", a TV show is a "Series"
    static func formatLabel(_ t: Title) -> String? {
        switch t.media {
        case .movie: return "Film"
        case .tv: return "Series"
        case .anime: return t.format == "Movie" ? "Film" : t.format
        case .manga, .book: return t.format
        }
    }

    /// the hero's line under the name: "ONA · Fall 2026 · 11 episodes", "Series · 2022 · 2 seasons",
    /// "Film · 2024 · 2h 47m", "Manga · 2018 · 232 ch · 24 vols", "Novel · 2021 · 496 pages"
    var metaLine: String {
        let t = title
        var parts: [String] = []
        if let f = Self.formatLabel(t), !f.isEmpty { parts.append(f) }
        switch t.media {
        case .anime:
            if let s = t.season { parts.append(s) } else if let y = t.year { parts.append(String(y)) }
            if t.format == "Movie" {
                if let r = t.runtime { parts.append(r) }
            } else if let n = t.total {
                parts.append(t.media.units(n))
            }
        case .tv:
            if let y = t.year { parts.append(String(y)) }
            let n = seasons?.count ?? 0
            if n > 0 { parts.append("\(n) season\(n == 1 ? "" : "s")") } else if let e = t.total { parts.append(t.media.units(e)) }
        case .movie:
            if let y = t.year { parts.append(String(y)) }
            if let r = t.runtime { parts.append(r) }
        case .manga:
            if let y = t.year { parts.append(String(y)) }
            if let n = t.total { parts.append("\(Format.grouped(n)) ch") }
            if let v = t.volumes { parts.append("\(v) vol\(v == 1 ? "" : "s")") }
        case .book:
            if let y = t.year { parts.append(String(y)) }
            if let n = t.total { parts.append("\(Format.grouped(n)) pages") }
        }
        return parts.joined(separator: " · ")
    }

    /// the maker on the hero's second line (before the score)
    var creatorName: String? { creator?.name ?? title.studio }

    /// the line under the name in the native script / other titles (anime and manga only; a book's subtitle is its
    /// author, shown on the next line)
    var nativeLine: String? {
        guard title.media == .anime || title.media == .manga, let s = title.subtitle, !s.isEmpty else { return nil }
        return s
    }

    /// the average as shown: "8.6" (out of 10), books "4.5" (out of 5, as readers rate them)
    var averageText: String? {
        guard let s = title.score, s > 0 else { return nil }
        return title.media == .book ? Format.average(s / 2) : Format.average(s)
    }

    /// books say "/ 5" after the score
    var averageOutOf: String? { title.media == .book ? "/ 5" : nil }

    /// "Story", or "About the book"
    var storyHeading: String { title.media == .book ? "About the book" : "Story" }

    /// the story's first paragraphs (the page shows a few lines with More)
    var story: String? {
        guard let d = description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty else { return nil }
        return d
    }

    /// the tags under the story: a book's cleaned-up subjects, else the genres
    var tags: [String] {
        if title.media == .book, let s = subjects, !s.isEmpty {
            let clean = Self.subjectTags(s)
            if !clean.isEmpty { return clean }
        }
        return title.genres ?? []
    }

    /// Open Library's subjects made readable: "hard science-fiction" -> "Hard science fiction", "sci-fi" ->
    /// "Science fiction", "New York Times bestseller" -> "NYT bestseller"; machine tags ("nyt:…"), long catalogue
    /// headings and repeats go.
    static func subjectTags(_ raw: [String], limit: Int = 6) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        for s in raw {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.contains(":") || t.contains(",") || t.count > 28 { continue }
            let lower = t.lowercased()
            if lower == "new york times reviewed" || lower.hasPrefix("accessible book") || lower.hasPrefix("protected daisy") { continue }
            if lower == "new york times bestseller" || lower == "nyt bestseller" { t = "NYT bestseller" }
            else {
                t = lower.replacingOccurrences(of: "sci-fi", with: "science fiction")
                    .replacingOccurrences(of: "science-fiction", with: "science fiction")
                    .replacingOccurrences(of: "-", with: " ")
                t = t.prefix(1).uppercased() + t.dropFirst()
            }
            let key = t.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(t)
            if out.count == limit { break }
        }
        return out
    }

    /// "8.6", "48,869 members", and the bars (only when the spread is known)
    var hasScoreAverage: Bool { title.score != nil && !(scores ?? []).isEmpty }

    var membersLine: String? { members.map { "\(Format.grouped($0)) members" } }

    /// each bar's height 0...1 of the tallest
    var scoreHeights: [(score: Int, height: Double)] {
        let bars = (scores ?? []).sorted { $0.score < $1.score }
        let top = Double(bars.map(\.amount).max() ?? 0)
        return bars.map { ($0.score, top > 0 ? Double($0.amount) / top : 0) }
    }

    /// "Sep 25, 2026" from "2026-09-25" (a bare year passes through)
    static func dateText(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if let d = Format.parseDay(s) { return Format.longDay(d) }
        return s
    }

    /// "Sep 25, 2026 – ongoing", "Dec 3, 2018 – Dec 14, 2020"
    var runLine: String? {
        guard let start = Self.dateText(startDate) else { return nil }
        if let end = Self.dateText(endDate) { return start == end ? start : "\(start) – \(end)" }
        if title.state == "Releasing" { return "\(start) – ongoing" }
        return start
    }

    /// One row of Details. `ref` makes it a link (a studio, an author).
    struct Detail: Equatable, Hashable, Sendable {
        var label: String
        var value: String
        var ref: String?
    }

    /// Details, per media (17, 23b). Your watch history is added by the page (it's the library's).
    var details: [Detail] {
        let t = title
        var out: [Detail] = []
        func add(_ label: String, _ value: String?, _ ref: String? = nil) {
            if let value, !value.isEmpty { out.append(Detail(label: label, value: value, ref: ref)) }
        }
        let studio = studios?.first
        switch t.media {
        case .anime:
            add("Format", Self.formatLabel(t))
            if t.format == "Movie" {
                add("Runtime", t.runtime)
            } else if let n = t.total {
                add("Episodes", t.runtime.map { "\(n) · \($0) each" } ?? String(n))
            }
            add(t.format == "Movie" ? "Released" : "Airing", runLine)
            add("Season", t.season)
            add("Studio", studio?.name ?? t.studio, studio?.ref)
            add("Source", source)
        case .manga:
            add("Format", t.format)
            add("Chapters", t.total.map { Format.grouped($0) })
            add("Volumes", t.volumes.map { String($0) })
            add("Published", runLine)
            add("Status", t.state)
            add("Source", source)
        case .tv:
            add("First aired", Self.dateText(startDate) ?? t.year.map { String($0) })
            if let s = seasons, !s.isEmpty {
                let eps = s.reduce(0) { $0 + $1.count }
                add("Seasons", "\(s.count) · \(t.media.units(eps))")
            }
            add("Network", studio?.name ?? t.studio, studio?.ref)
            add("Status", t.state)
            add("Genres", t.genres?.joined(separator: ", "))
        case .movie:
            add("Released", Self.dateText(startDate) ?? t.year.map { String($0) })
            add("Runtime", t.runtime)
            add("Genres", t.genres?.joined(separator: ", "))
            add("Studio", studio?.name, studio?.ref)
        case .book:
            add("Published", t.year.map { String($0) })
            add("Pages", t.total.map { Format.grouped($0) })
            add("Author", creator?.name ?? t.studio, creator?.ref)
        }
        return out
    }

    /// "Prequel", "Source · Manga" (the media when it differs from this title's)
    func relationLabel(_ r: Relation) -> String {
        r.title.media != title.media ? "\(r.relation) · \(r.title.media.singular)" : r.relation
    }

    /// "ONA · 2026", "Manga" (the status after it is the library's)
    static func relationLine(_ t: Title) -> String {
        var parts: [String] = []
        if let f = formatLabel(t), !f.isEmpty { parts.append(f) } else { parts.append(t.media.singular) }
        if let y = t.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    /// the ••• menu's "Open on AniList" links
    var openLinks: [Link] { links ?? [] }
}

// MARK: - the main button and "Your list"

/// The white button under the hero: Open in Harbor (anime, TV, films), mark the next chapter read (manga), update
/// progress (books).
enum TitlePrimary: Equatable {
    case harbor
    case markChapter(Int)
    case allRead
    case updateProgress
    case startReading

    static func of(_ t: Title, entry: LibraryEntry?) -> TitlePrimary {
        switch t.media {
        case .anime, .tv, .movie: return .harbor
        case .manga:
            let next = (entry?.progress ?? 0) + 1
            if let total = t.total, next > total { return .allRead }
            return .markChapter(next)
        case .book:
            return entry == nil ? .startReading : .updateProgress
        }
    }

    var label: String {
        switch self {
        case .harbor: return "Open in Harbor"
        case .markChapter(let n): return "Mark Ch \(Format.grouped(n)) read"
        case .allRead: return "All read"
        case .updateProgress: return "Update progress"
        case .startReading: return "Start reading"
        }
    }

    /// SF Symbol
    var symbol: String {
        switch self {
        case .harbor: return "play"
        case .markChapter, .allRead: return "checkmark"
        case .updateProgress, .startReading: return "bookmark"
        }
    }
}

enum TitleListText {
    /// "Your list", "Your list · Season 2"
    static func label(_ e: LibraryEntry, seasons: [TVSeason]?) -> String {
        if e.media == .tv, let p = TVProgress.position(e.progress, seasons ?? []), (seasons ?? []).count > 1 {
            return "Your list · Season \(p.season)"
        }
        return "Your list"
    }

    /// The line under the strip's controls: "Chapter 97 · Volume 11", "Page 212 of 496 · + and − move 10 pages",
    /// "Watched Mar 9, 2024 · seen twice"; nil when there's nothing to add.
    static func caption(_ e: LibraryEntry) -> String? {
        switch e.media {
        case .manga:
            guard e.progress > 0 else { return nil }
            var s = "Chapter \(Format.grouped(e.progress))"
            if let v = e.volume, v > 0 { s += " · Volume \(v)" }
            return s
        case .book:
            var s = "Page \(Format.grouped(e.progress))"
            if let t = e.title.total { s += " of \(Format.grouped(t))" }
            return s + " · + and − move 10 pages"
        case .movie:
            guard e.status == .completed || e.status == .repeating else { return nil }
            var parts: [String] = []
            if let f = e.finished.flatMap(TitlePage.dateText) { parts.append("Watched \(f)") }
            if e.repeats > 0 { parts.append(seen(e.repeats + 1)) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .anime, .tv:
            return nil
        }
    }

    /// 2 -> "seen twice", 3 -> "seen 3 times"
    static func seen(_ n: Int) -> String {
        n == 2 ? "seen twice" : n == 1 ? "seen once" : "seen \(n) times"
    }

    /// Details' "Your history" after the status: "★ 9 · 2 watches"
    static func history(_ e: LibraryEntry) -> String {
        var parts: [String] = []
        if let s = e.score10 { parts.append("★ \(s)") }
        if e.media == .movie {
            let n = e.status == .completed ? e.repeats + 1 : e.repeats
            if n > 0 { parts.append(n == 1 ? "1 watch" : "\(n) watches") }
        } else if e.repeats > 0 {
            parts.append(e.media.isReading ? "read \(e.repeats + 1) times" : "\(e.repeats + 1) watches")
        }
        return parts.joined(separator: " · ")
    }

    /// "Add it to track episodes, score and dates"
    static func addLine(_ media: MediaKind) -> String {
        if let unit = media.unit { return "Add it to track \(unit)s, score and dates" }
        return "Add it to track it, score it and log when you watched"
    }

    /// "Ep 7 · Fri 3:00 AM · in 3 days" split into the bold part and the rest
    static func airing(_ a: Airing, media: MediaKind) -> (String, String) {
        let all = Format.airing(a, media: media)
        let head = "\(media.unitShort) \(a.episode)"
        return (head, String(all.dropFirst(head.count)))
    }
}

// MARK: - TV progress by season

/// A show's progress is one count of episodes across its seasons (what the library keeps); the page shows it per
/// season: 15 watched of 9 + 10 is Season 2, 6 of 10.
struct TVProgress: Equatable, Sendable {
    var season: Int
    var watched: Int
    var count: Int

    /// the next episode's number in its season, nil when the show is all watched
    var next: Int? { watched < count ? watched + 1 : nil }

    static func regular(_ seasons: [TVSeason]) -> [TVSeason] {
        seasons.filter { $0.number > 0 && $0.count > 0 }.sorted { $0.number < $1.number }
    }

    /// where `progress` episodes leave you; nil without seasons
    static func position(_ progress: Int, _ seasons: [TVSeason]) -> TVProgress? {
        let list = regular(seasons)
        guard let last = list.last else { return nil }
        var left = max(0, progress)
        for s in list {
            if left < s.count { return TVProgress(season: s.number, watched: left, count: s.count) }
            left -= s.count
        }
        return TVProgress(season: last.number, watched: last.count, count: last.count)
    }

    /// episodes in the seasons before `season`
    static func offset(_ season: Int, _ seasons: [TVSeason]) -> Int {
        regular(seasons).filter { $0.number < season }.reduce(0) { $0 + $1.count }
    }

    static func total(_ seasons: [TVSeason]) -> Int { regular(seasons).reduce(0) { $0 + $1.count } }

    /// how many of a season's episodes are watched
    static func watched(in season: TVSeason, progress: Int, _ seasons: [TVSeason]) -> Int {
        min(season.count, max(0, progress - offset(season.number, seasons)))
    }

    /// The patch for tapping an episode's circle: an unwatched one marks it and everything before it watched; a
    /// watched one goes back to just before it.
    static func mark(episode n: Int, season: Int, progress: Int, _ seasons: [TVSeason]) -> LibraryPatch {
        let off = offset(season, seasons)
        let isWatched = progress >= off + n
        let p = isWatched ? off + n - 1 : off + n
        return patch(p, seasons)
    }

    /// the patch for all of a season watched
    static func markAll(season: Int, _ seasons: [TVSeason]) -> LibraryPatch {
        let count = regular(seasons).first { $0.number == season }?.count ?? 0
        return patch(offset(season, seasons) + count, seasons)
    }

    /// +1 / −1 on the season's stepper
    static func step(_ progress: Int, by n: Int, _ seasons: [TVSeason]) -> LibraryPatch {
        patch(min(total(seasons), max(0, progress + n)), seasons)
    }

    /// progress and the season it puts you in; finishing the last episode completes the show
    static func patch(_ progress: Int, _ seasons: [TVSeason]) -> LibraryPatch {
        let p = max(0, progress)
        var patch = LibraryPatch(progress: p, season: position(p, seasons)?.season)
        let all = total(seasons)
        if all > 0 && p >= all { patch.status = .completed }
        return patch
    }
}
