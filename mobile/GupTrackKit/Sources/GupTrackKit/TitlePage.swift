import Foundation

// A title's own page (16-25) and a TV season (22), docs/app-api.md §8.3. The wire shapes are the website's
// (src/catalog/detail.ts) field for field; `TitlePage` adds the words and numbers the screen shows. "Your list"
// (status, progress, score) is the offline library's copy (§7), not the page's, so it works and edits offline.
//
// The people around a title open with these route ids (CatalogRef.route):
//   .character("40")                    GET characters/40
//   .person("anilist:95075")            GET people/anilist/95075 (also "tmdb:1190668")
//   .author("OL7234434A")               GET authors/OL7234434A
//   .studio("studio:569")               GET companies/studio/569 (also "network:49", "company:41077")

// MARK: - the wire shapes

/// `NameCard`: a person or character as a small card
struct NameCard: Codable, Hashable, Sendable {
    var ref: CatalogRef
    var name: String
    var image: URL?

    var route: Route? { ref.route }
}

/// `NameLink`: a link inside running text or a fact
struct NameLink: Codable, Hashable, Sendable {
    var text: String
    var ref: CatalogRef?

    var route: Route? { ref?.route }
}

/// `Fact`: a row in a page's facts ("Studio  Wit Studio")
struct Fact: Codable, Hashable, Sendable {
    var label: String
    var value: String
    var links: [NameLink]?

    /// the one page the fact opens (several links show as a menu)
    var routes: [(text: String, route: Route)] {
        (links ?? []).compactMap { l in l.route.map { (l.text, $0) } }
    }
}

/// `RichSpan`
struct RichSpan: Codable, Hashable, Sendable {
    var text: String
    var bold: Bool?
    var italic: Bool?
    var spoiler: Bool?
    var ref: CatalogRef?
}

/// `Rich`: one array of spans per paragraph
typealias Rich = [[RichSpan]]

/// Rich text as the app shows it: plain paragraphs, spoilers left out until asked for.
enum RichText {
    /// the paragraphs joined by a blank line; `spoilers` false leaves spoiler spans out (and paragraphs left empty)
    static func plain(_ r: Rich, spoilers: Bool = false) -> String {
        r.map { p in
            p.filter { spoilers || $0.spoiler != true }.map(\.text).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    static func hasSpoilers(_ r: Rich) -> Bool { r.contains { $0.contains { $0.spoiler == true } } }
}

/// `TitleCard`: a title as a small card (relations, recommendations, credits)
struct TitleCard: Codable, Hashable, Sendable {
    var ref: TitleRef
    var title: String
    var cover: URL?
    /// "TV", "Film", "Manga", "Novel"
    var format: String
    var year: Int?
    /// 0–100, when the card shows one
    var score: Double?

    /// the card as the app's title
    var app: Title {
        Title(id: ref.titleId, media: ref.kind, name: title, cover: cover, format: format, year: year,
              score: score.map { $0 / 10 })
    }
}

/// `CharacterCredit`
struct CharacterCredit: Codable, Hashable, Sendable {
    var character: NameCard
    /// "Main", "Supporting", "Background"
    var role: String
    var voices: [Voice]

    struct Voice: Codable, Hashable, Sendable {
        var person: NameCard
        var language: String
    }

    /// the voice the page shows: Japanese first, as the website does
    var voice: Voice? { voices.first { $0.language == "Japanese" } ?? voices.first }
}

/// `Credit`: an actor and who they play, or a person and their job
struct Credit: Codable, Hashable, Sendable {
    var person: NameCard
    var role: String
    /// "62 episodes"
    var note: String?
}

/// `SeasonSummary`: one season of a show
struct SeasonSummary: Codable, Hashable, Sendable, Identifiable {
    var number: Int
    var name: String
    var episodes: Int
    var year: Int?
    /// "2025-01-17"
    var air: String?
    var poster: URL?
    var overview: String

    init(number: Int, name: String, episodes: Int, year: Int? = nil, air: String? = nil, poster: URL? = nil,
         overview: String = "") {
        self.number = number
        self.name = name
        self.episodes = episodes
        self.year = year
        self.air = air
        self.poster = poster
        self.overview = overview
    }

    var id: Int { number }
    /// episodes in the season
    var count: Int { episodes }
}

/// `Episode`
struct Episode: Codable, Hashable, Sendable, Identifiable {
    var number: Int
    var name: String
    /// "2025-01-17"
    var air: String?
    var minutes: Int?
    var overview: String
    var still: URL?
    /// 0–100
    var score: Double?

    var id: Int { number }

    /// "Jan 17, 2025 · 57m"
    var line: String {
        var parts: [String] = []
        if let a = air, let d = Format.parseDay(a) { parts.append(Format.longDay(d)) }
        if let m = minutes, let r = ListEntry.runtime(m, .movie) { parts.append(r) }
        return parts.joined(separator: " · ")
    }
}

/// `Trailer`: a YouTube video id
struct Trailer: Codable, Hashable, Sendable {
    var youtube: String

    var url: URL? { URL(string: "https://www.youtube.com/watch?v=" + youtube) }
}

/// `TitleDetail`
struct TitleDetail: Codable, Hashable, Sendable {
    var ref: TitleRef
    /// the list it belongs on (plural; anime films stay under Anime)
    var media: APIMedia
    var title: String
    var alt: [String]
    var cover: URL?
    var banner: URL?
    var synopsis: Rich
    var format: String
    var status: CatalogStatus
    /// "Finished", "Returning series"
    var statusText: String
    var year: Int?
    /// "TV · 2013 · 25 episodes"
    var headline: [String]
    var makers: [NameLink]
    var facts: [Fact]
    var genres: [String]
    var tags: [String]
    /// 0–100
    var score: Double?
    var scoreNote: String?
    /// episodes, chapters or pages: your list's total
    var count: Int?
    /// minutes per episode, or a film's runtime
    var minutes: Int
    var trailer: Trailer?
    var volumes: Int?
    var idMal: Int?
    var relations: [Relation]
    var characters: [CharacterCredit]
    var cast: [Credit]
    var staff: [Credit]
    var seasons: [SeasonSummary]
    var recommendations: [TitleCard]
    var more: [More]

    struct Relation: Codable, Hashable, Sendable {
        var relation: String
        var title: TitleCard
    }

    /// an extra shelf, "More by Andy Weir"
    struct More: Codable, Hashable, Sendable {
        var title: String
        var ref: CatalogRef?
        var titles: [TitleCard]
    }
}

/// `GET titles/:kind/:id`
struct TitleAnswer: Codable, Equatable, Sendable { var title: TitleDetail }

/// `GET titles/tv/:id/seasons/:season`
struct SeasonAnswer: Codable, Equatable, Sendable { var episodes: [Episode] }

// MARK: - the page

/// A title page as the screen shows it: the answer, and the title as the app's cards and the library know it.
struct TitlePage: Equatable, Sendable {
    var detail: TitleDetail?
    var title: Title

    init(_ d: TitleDetail) {
        detail = d
        let kind = d.ref.kind
        let season = d.facts.first { $0.label == "Season" }?.value
        title = Title(id: d.ref.titleId, media: kind, name: d.title, subtitle: d.alt.first, cover: d.cover,
                      banner: d.banner, format: d.format, year: d.year, season: season, total: d.count,
                      volumes: d.volumes, score: d.score.map { $0 / 10 }, genres: d.genres,
                      studio: d.makers.first?.text, runtime: ListEntry.runtime(d.minutes, kind),
                      state: Catalog.state(d.status))
    }

    /// a page from only a Title (the library's copy while the page can't load)
    init(basic t: Title) {
        detail = nil
        title = t
    }

    static func basic(_ t: Title) -> TitlePage { TitlePage(basic: t) }

    var seasons: [SeasonSummary] { detail?.seasons ?? [] }
    var makers: [NameLink] { detail?.makers ?? [] }

    /// a format as the page writes it
    static func formatLabel(_ t: Title) -> String? { t.format }

    /// the hero's line under the name: the answer's headline ("TV · Fall 2026 · 11 episodes")
    var metaLine: String {
        if let h = detail?.headline, !h.isEmpty { return h.joined(separator: " · ") }
        return [title.format, title.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    /// the maker on the hero's second line (before the score)
    var creatorName: String? {
        let names = makers.prefix(2).map(\.text)
        return names.isEmpty ? title.studio : names.joined(separator: ", ")
    }

    /// the page the maker's name opens
    var creatorRoute: Route? { makers.first?.route }

    /// another name (romaji, native) under the name, for anime and manga
    var nativeLine: String? {
        guard title.media == .anime || title.media == .manga, let s = title.subtitle, !s.isEmpty, s != title.name
        else { return nil }
        return s
    }

    /// the average as shown: "8.6" (0–100 shown out of 10)
    var averageText: String? {
        guard let s = title.score, s > 0 else { return nil }
        return Format.average(s)
    }

    /// "48,869 members", "1,204 ratings"
    var scoreNote: String? { detail?.scoreNote }

    /// "Story", or "About the book"
    var storyHeading: String { title.media == .book ? "About the book" : "Story" }

    /// the story, spoilers left out unless asked for
    func story(spoilers: Bool = false) -> String? {
        guard let r = detail?.synopsis else { return nil }
        let s = RichText.plain(r, spoilers: spoilers)
        return s.isEmpty ? nil : s
    }

    var storyHasSpoilers: Bool { detail.map { RichText.hasSpoilers($0.synopsis) } ?? false }

    /// the genres, then the tags (no repeats)
    var tags: [String] {
        var seen = Set<String>(), out: [String] = []
        for t in (detail?.genres ?? title.genres ?? []) + (detail?.tags ?? []) where seen.insert(t.lowercased()).inserted {
            out.append(t)
        }
        return out
    }

    /// the line "Next episode  Ep 7, Nov 6, 2026" from the facts
    var nextEpisode: String? { detail?.facts.first { $0.label == "Next episode" }?.value }

    /// the trailer on YouTube
    var trailer: URL? { detail?.trailer?.url }

    /// the facts, as the answer orders them
    var details: [Fact] { detail?.facts ?? [] }

    var relations: [TitleDetail.Relation] { detail?.relations ?? [] }
    var characters: [CharacterCredit] { detail?.characters ?? [] }
    var cast: [Credit] { detail?.cast ?? [] }
    var staff: [Credit] { detail?.staff ?? [] }
    var recommendations: [Title] { (detail?.recommendations ?? []).map(\.app) }
    var more: [TitleDetail.More] { (detail?.more ?? []).filter { !$0.titles.isEmpty } }

    /// "Prequel", "Source · Manga" (the media when it differs from this title's)
    func relationLabel(_ r: TitleDetail.Relation) -> String {
        r.title.ref.kind != title.media ? "\(r.relation) · \(r.title.ref.kind.singular)" : r.relation
    }

    /// "ONA · 2026", "Manga" (the status after it is the library's)
    static func relationLine(_ t: Title) -> String {
        var parts: [String] = []
        if let f = t.format, !f.isEmpty { parts.append(f) } else { parts.append(t.media.singular) }
        if let y = t.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    /// "Sep 25, 2026" from "2026-09-25" (a bare year passes through)
    static func dateText(_ s: String?) -> String? {
        guard let s, !s.isEmpty else { return nil }
        if let d = Format.parseDay(s) { return Format.longDay(d) }
        return s
    }

    struct Link: Equatable, Hashable, Sendable {
        /// "AniList", "MyAnimeList", "TMDB", "Open Library"
        var label: String
        var url: URL
    }

    /// the ••• menu's "Open on AniList": the source's own page from the title's id (and MyAnimeList's id)
    var openLinks: [Link] {
        guard let r = TitleRef(titleId: title.id) else { return [] }
        var out: [Link] = []
        func add(_ label: String, _ s: String) { if let u = URL(string: s) { out.append(Link(label: label, url: u)) } }
        switch r.kind {
        case .anime, .manga:
            add("AniList", "https://anilist.co/\(r.kind.rawValue)/\(r.id)")
            if let mal = detail?.idMal { add("MyAnimeList", "https://myanimelist.net/\(r.kind.rawValue)/\(mal)") }
        case .tv, .movie:
            add("TMDB", "https://www.themoviedb.org/\(r.kind.rawValue)/\(r.id)")
        case .book:
            add("Open Library", "https://openlibrary.org/works/\(r.id)")
        }
        return out
    }
}

/// A season in full (22): the show's page (for its seasons and the library's progress) and the season's episodes.
struct TVSeasonPage: Equatable, Sendable {
    var show: TitlePage
    var number: Int
    var episodes: [Episode]

    var seasons: [SeasonSummary] { show.seasons }
    var season: SeasonSummary {
        seasons.first { $0.number == number } ?? SeasonSummary(number: number, name: "Season \(number)",
                                                                 episodes: episodes.count)
    }
}

extension APIClient {
    /// GET titles/:kind/:id (`id` is the app's "anime:210482")
    func titleDetail(_ id: String) async throws -> TitleDetail {
        guard let r = TitleRef(titleId: id) else { throw APIError.server(404, "not_found", "That title isn't one GupTrack knows.") }
        let a: TitleAnswer = try await get("titles/\(r.kind.rawValue)/\(r.id)")
        return a.title
    }

    func titlePage(_ id: String) async throws -> TitlePage { TitlePage(try await titleDetail(id)) }

    /// GET titles/tv/:id/seasons/:season
    func seasonEpisodes(_ id: String, _ number: Int) async throws -> [Episode] {
        guard let r = TitleRef(titleId: id), r.kind == .tv else {
            throw APIError.server(404, "not_found", "Only TV shows have seasons.")
        }
        let a: SeasonAnswer = try await get("titles/tv/\(r.id)/seasons/\(number)")
        return a.episodes
    }

    /// the season page: the show and the season's episodes
    func tvSeason(_ id: String, _ number: Int) async throws -> TVSeasonPage {
        async let show = titlePage(id)
        async let episodes = seasonEpisodes(id, number)
        return TVSeasonPage(show: try await show, number: number, episodes: try await episodes)
    }
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
    static func label(_ e: LibraryEntry, seasons: [SeasonSummary]) -> String {
        if e.media == .tv, TVProgress.regular(seasons).count > 1, let p = TVProgress.position(e.progress, seasons) {
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

    /// the seasons that count (no specials, none empty), in order
    static func regular(_ seasons: [SeasonSummary]) -> [SeasonSummary] {
        seasons.filter { $0.number > 0 && $0.count > 0 }.sorted { $0.number < $1.number }
    }

    /// where `progress` episodes leave you; nil without seasons
    static func position(_ progress: Int, _ seasons: [SeasonSummary]) -> TVProgress? {
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
    static func offset(_ season: Int, _ seasons: [SeasonSummary]) -> Int {
        regular(seasons).filter { $0.number < season }.reduce(0) { $0 + $1.count }
    }

    static func total(_ seasons: [SeasonSummary]) -> Int { regular(seasons).reduce(0) { $0 + $1.count } }

    /// how many of a season's episodes are watched
    static func watched(in season: SeasonSummary, progress: Int, _ seasons: [SeasonSummary]) -> Int {
        min(season.count, max(0, progress - offset(season.number, seasons)))
    }

    /// The patch for tapping an episode's circle: an unwatched one marks it and everything before it watched; a
    /// watched one goes back to just before it.
    static func mark(episode n: Int, season: Int, progress: Int, _ seasons: [SeasonSummary]) -> LibraryPatch {
        let off = offset(season, seasons)
        let isWatched = progress >= off + n
        let p = isWatched ? off + n - 1 : off + n
        return patch(p, seasons)
    }

    /// the patch for all of a season watched
    static func markAll(season: Int, _ seasons: [SeasonSummary]) -> LibraryPatch {
        let count = regular(seasons).first { $0.number == season }?.count ?? 0
        return patch(offset(season, seasons) + count, seasons)
    }

    /// +1 / −1 on the season's stepper
    static func step(_ progress: Int, by n: Int, _ seasons: [SeasonSummary]) -> LibraryPatch {
        patch(min(total(seasons), max(0, progress + n)), seasons)
    }

    /// progress and the season it puts you in; finishing the last episode completes the show
    static func patch(_ progress: Int, _ seasons: [SeasonSummary]) -> LibraryPatch {
        let p = max(0, progress)
        var patch = LibraryPatch(progress: p, season: position(p, seasons)?.season)
        let all = total(seasons)
        if all > 0 && p >= all { patch.status = .completed }
        return patch
    }
}
