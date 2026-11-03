import Foundation

// The pages around titles (28-31), docs/app-api.md §8.3: characters, people (AniList staff and voice actors, TMDB
// people), studios / networks / companies, and authors. The wire shapes are the website's (src/catalog/detail.ts);
// the page types add what the screens show. Route ids (see CatalogRef.route):
//   .character("40")            GET characters/40
//   .person("anilist:95075")    GET people/anilist/95075   ("tmdb:1190668" -> people/tmdb/1190668)
//   .studio("studio:569")       GET companies/studio/569   ("network:49", "company:41077")
//   .author("OL7234434A")       GET authors/OL7234434A
// "Your status" on these pages always comes from the offline library, never from the page.

// MARK: - the wire shapes

/// `CharacterDetail`
struct CharacterDetail: Codable, Hashable, Sendable {
    var id: String
    var name: String
    var native: String?
    var alt: [String]
    var altSpoiler: [String]
    var image: URL?
    var facts: [Fact]
    var description: Rich
    var favourites: Int
    var appearances: [Appearance]
    /// voice actors by language, Japanese first
    var voices: [Voices]

    struct Appearance: Codable, Hashable, Sendable {
        var title: TitleCard
        /// "Main", "Supporting", "Background"
        var role: String
    }

    struct Voices: Codable, Hashable, Sendable {
        var language: String
        var people: [NameCard]
    }
}

/// `RoleItem`: a title someone worked on, as what (and, for a voice role, the character)
struct RoleItem: Codable, Hashable, Sendable {
    var title: TitleCard
    var role: String
    var character: NameCard?
}

/// `PersonDetail` (people and authors)
struct PersonDetail: Codable, Hashable, Sendable {
    var ref: CatalogRef
    var name: String
    var native: String?
    var alt: [String]
    var image: URL?
    /// "Voice Actor · Vocalist", "Acting", "Author"
    var known: String
    var facts: [Fact]
    var bio: Rich
    var groups: [Group]

    struct Group: Codable, Hashable, Sendable {
        var title: String
        var items: [RoleItem]
    }
}

/// `CompanyDetail`
struct CompanyDetail: Codable, Hashable, Sendable {
    var ref: CatalogRef
    var name: String
    /// "Animation studio", "TV network", "Production company"
    var kind: String
    var image: URL?
    var facts: [Fact]
    var description: Rich
    var groups: [Group]

    struct Group: Codable, Hashable, Sendable {
        var title: String
        var titles: [TitleCard]
    }
}

struct CharacterAnswer: Codable, Equatable, Sendable { var character: CharacterDetail }
struct PersonAnswer: Codable, Equatable, Sendable { var person: PersonDetail }
struct CompanyAnswer: Codable, Equatable, Sendable { var company: CompanyDetail }

extension APIClient {
    /// GET characters/:id (`id` is the route's "40")
    func characterPage(_ id: String) async throws -> CharacterPage {
        let a: CharacterAnswer = try await get("characters/" + Self.segment(id))
        return CharacterPage(a.character)
    }

    /// GET people/:source/:id (`id` is the route's "anilist:95075" or "tmdb:1190668")
    func personPage(_ id: String) async throws -> PersonPage {
        let p = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2, p[0] == "anilist" || p[0] == "tmdb" else { throw Self.unknown }
        let a: PersonAnswer = try await get("people/\(p[0])/" + Self.segment(p[1]))
        return PersonPage(a.person)
    }

    /// GET companies/:to/:id (`id` is the route's "studio:569", "network:49" or "company:41077")
    func studioPage(_ id: String) async throws -> StudioPage {
        let p = id.split(separator: ":", maxSplits: 1).map(String.init)
        guard p.count == 2, ["studio", "network", "company"].contains(p[0]) else { throw Self.unknown }
        let a: CompanyAnswer = try await get("companies/\(p[0])/" + Self.segment(p[1]))
        return StudioPage(a.company)
    }

    /// GET authors/:id (`id` is the route's "OL7234434A")
    func authorPage(_ id: String) async throws -> AuthorPage {
        let a: PersonAnswer = try await get("authors/" + Self.segment(id))
        return AuthorPage(a.person, id: id)
    }

    private static var unknown: APIError { .server(404, "not_found", "GupTrack doesn't know that.") }
}

// MARK: - shared bits

/// How the people pages name a title's format: films are "Film" (anime films stay under Anime, marked Film).
enum PeopleCaption {
    static func format(_ t: Title) -> String {
        guard let f = t.format, !f.isEmpty else {
            return t.media == .movie ? "Film" : t.media.singular
        }
        return f == "Movie" ? "Film" : f
    }

    /// "TV · 1999 · Main"
    static func line(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Born" and the place, from the facts: "Born Jun 16, 1972 · Davis, California"
    static func born(_ facts: [Fact]) -> String? {
        func v(_ l: String) -> String? { facts.first { $0.label == l }?.value }
        let born = v("Born").map { "Born " + $0 }
        let place = v("Birthplace") ?? v("Hometown")
        guard born != nil || place != nil else { return nil }
        return line([born, place])
    }
}

/// About text with its spoilers kept apart, so the page can hide them until asked.
struct PeopleProse: Hashable, Sendable {
    /// the text with spoilers left out
    var text: String
    /// the text with spoilers in
    var full: String

    init(_ r: Rich) {
        text = RichText.plain(r)
        full = RichText.plain(r, spoilers: true)
    }

    var hasSpoilers: Bool { text != full }
    var isEmpty: Bool { full.isEmpty }
}

// MARK: 28 character

/// A character's page.
struct CharacterPage: Hashable, Sendable {
    struct Voice: Hashable, Identifiable, Sendable {
        var person: NameCard
        var language: String

        var id: String { (person.route?.path ?? person.name) + "|" + language }
        var name: String { person.name }
        var image: URL? { person.image }
        var route: Route? { person.route }
        /// "Japanese"
        var line: String { language }
    }

    struct Appearance: Hashable, Identifiable, Sendable {
        var title: Title
        /// "Main", "Supporting", "Background"
        var role: String

        var id: String { title.id }

        /// "TV · 1999 · Main"
        var line: String {
            PeopleCaption.line([PeopleCaption.format(title), title.year.map(String.init), role])
        }
    }

    var detail: CharacterDetail

    init(_ d: CharacterDetail) { detail = d }

    var id: String { detail.id }
    var name: String { detail.name }
    var native: String? { detail.native }
    var image: URL? { detail.image }
    var favourites: Int? { detail.favourites > 0 ? detail.favourites : nil }
    var prose: PeopleProse { PeopleProse(detail.description) }

    var appearances: [Appearance] { detail.appearances.map { Appearance(title: $0.title.app, role: $0.role) } }
    var total: Int { detail.appearances.count }

    /// every voice, language by language (Japanese first, as the answer orders them)
    var voices: [Voice] { detail.voices.flatMap { g in g.people.map { Voice(person: $0, language: g.language) } } }

    /// "Main character · ONE PIECE"
    var headline: String? {
        guard let first = detail.appearances.first else { return nil }
        return "\(first.role) character · \(first.title.title)"
    }

    /// the columns under the head: Height, Birthday, Age, Gender first, at most four, short values only
    var facts: [Fact] {
        let order = ["Height", "Birthday", "Age", "Gender"]
        let short = detail.facts.filter { $0.value.count <= 16 }
        let known = order.compactMap { l in short.first { $0.label == l } }
        let rest = short.filter { !order.contains($0.label) }
        return Array((known + rest).prefix(4)).map {
            Fact(label: $0.label, value: $0.label == "Age" ? $0.value.replacingOccurrences(of: "-", with: "–") : $0.value)
        }
    }
}

// MARK: 29 person

/// A person's page: an actor, voice actor or staff member (AniList staff or a TMDB person).
struct PersonPage: Hashable, Sendable {
    struct Credit: Hashable, Identifiable, Sendable {
        var item: RoleItem
        /// the group it's listed in ("Acting", "Voice roles")
        var group: String

        var title: Title { item.title.app }
        var character: NameCard? { item.character }
        var id: String { item.title.ref.titleId + "|" + (item.character?.name ?? item.role) }
        var year: Int? { item.title.year }

        /// "ONE PIECE · Main", "as Paul Atreides", "Original Creator"
        var line: String {
            if character != nil { return PeopleCaption.line([item.title.title, item.role]) }
            guard !item.role.isEmpty else { return PeopleCaption.format(title) }
            return group == "Acting" ? "as " + item.role : item.role
        }

        /// a voice role opens the character, everything else the title
        var route: Route { character?.route ?? .title(item.title.ref.titleId) }
    }

    var detail: PersonDetail

    init(_ d: PersonDetail) { detail = d }

    /// the route id: "anilist:95075", "tmdb:1190668"
    var id: String {
        if case .person(let s, let i) = detail.ref { return "\(s):\(i)" }
        return detail.name
    }

    var name: String { detail.name }
    var native: String? { detail.native }
    var image: URL? { detail.image }
    var prose: PeopleProse { PeopleProse(detail.bio) }

    /// "Voice Actor · Vocalist", "Acting"
    var headline: String? { detail.known.isEmpty ? nil : detail.known }
    var bornLine: String? { PeopleCaption.born(detail.facts) }

    /// TMDB's "Known for" shelf
    var knownFor: [Title] { (detail.groups.first { $0.title == "Known for" }?.items ?? []).map(\.title.app) }

    /// the credit lists ("Voice roles", "Anime staff"; "Acting", "Directing"), in the answer's order
    var groups: [String] { detail.groups.filter { $0.title != "Known for" && !$0.items.isEmpty }.map(\.title) }

    /// one group's credits, newest first (unknown years, i.e. not out yet, first)
    func credits(_ group: String?) -> [Credit] {
        guard let g = detail.groups.first(where: { $0.title == (group ?? groups.first) }) else { return [] }
        return g.items.enumerated().sorted { a, b in
            let ya = a.element.title.year ?? Int.max, yb = b.element.title.year ?? Int.max
            return ya != yb ? ya > yb : a.offset < b.offset
        }.map { Credit(item: $0.element, group: g.title) }
    }

    /// "Voice roles  412"
    func count(_ group: String) -> Int { detail.groups.first { $0.title == group }?.items.count ?? 0 }
}

// MARK: 30 studio

/// A studio, TV network or film company, with its titles.
struct StudioPage: Hashable, Sendable {
    enum Filter: String, CaseIterable, Identifiable, Hashable, Sendable {
        case all, tv, film, ona, ova, special, other

        var id: String { rawValue }

        var label: String {
            switch self {
            case .all: return "All"
            case .tv: return "TV"
            case .film: return "Films"
            case .ona: return "ONA"
            case .ova: return "OVA"
            case .special: return "Special"
            case .other: return "Other"
            }
        }

        static func of(_ t: Title) -> Filter {
            switch t.format {
            case "TV", "TV Short", "Series": return .tv
            case "Movie", "Film", "Documentary": return .film
            case "ONA": return .ona
            case "OVA": return .ova
            case "Special", "Music": return .special
            default:
                if t.media == .tv { return .tv }
                if t.media == .movie { return .film }
                return .other
            }
        }

        fileprivate var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    /// one year's titles (nil year: not dated yet, last as "TBA")
    struct YearGroup: Hashable, Identifiable, Sendable {
        var year: Int?
        var titles: [Title]

        var id: Int { year ?? Int.min }
        var label: String { year.map(String.init) ?? "TBA" }
    }

    var detail: CompanyDetail

    init(_ d: CompanyDetail) { detail = d }

    /// the route id: "studio:569"
    var id: String {
        if case .company(let to, let i) = detail.ref { return "\(to):\(i)" }
        return detail.name
    }

    var name: String { detail.name }

    /// every title in its groups (main studio first), once each
    var titles: [Title] {
        var seen = Set<String>()
        return detail.groups.flatMap(\.titles).filter { seen.insert($0.ref.titleId).inserted }.map(\.app)
    }

    /// "Favourites  35,992" as a number
    var favourites: Int? {
        detail.facts.first { $0.label == "Favourites" }.flatMap { Int($0.value.filter(\.isNumber)) }
    }

    /// "Animation studio", "TV network · United States"
    var headline: String {
        let place = detail.facts.first { $0.label == "Headquarters" || $0.label == "Country" }?.value
        return PeopleCaption.line([detail.kind, place])
    }

    var prose: PeopleProse { PeopleProse(detail.description) }

    /// "24 titles · 6 in your library"
    func countLine(inLibrary n: Int) -> String {
        let all = titles.count
        var s = "\(Format.grouped(all)) title\(all == 1 ? "" : "s")"
        if n > 0 { s += " · \(n) in your library" }
        return s
    }

    /// All, then up to three formats with the most titles, in a fixed order; no filter at all when there's one kind
    var filters: [Filter] {
        var counts: [Filter: Int] = [:]
        for t in titles { counts[Filter.of(t), default: 0] += 1 }
        counts[.other] = nil
        guard counts.count > 1 else { return [] }
        let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.order < $1.key.order }
            .prefix(3).map(\.key)
        return [.all] + Filter.allCases.filter { top.contains($0) }
    }

    /// the titles a filter keeps, by year, newest first; within a year, as the server listed them
    func years(_ filter: Filter = .all) -> [YearGroup] {
        let kept = filter == .all ? titles : titles.filter { Filter.of($0) == filter }
        var order: [Int?] = []
        var by: [Int?: [Title]] = [:]
        for t in kept {
            if by[t.year] == nil { order.append(t.year) }
            by[t.year, default: []].append(t)
        }
        return order.sorted { ($0 ?? Int.min) > ($1 ?? Int.min) }.map { YearGroup(year: $0, titles: by[$0] ?? []) }
    }

    /// how many of its titles are on your list
    func inLibrary(_ lib: [LibraryEntry]) -> Int {
        let ids = Set(lib.map(\.id))
        return titles.filter { ids.contains($0.id) }.count
    }
}

// MARK: 31 author

/// An author and their books (authors/:id answers a PersonDetail).
struct AuthorPage: Hashable, Sendable {
    struct Book: Hashable, Identifiable, Sendable {
        var card: TitleCard
        /// "Novel · 2021"
        var role: String

        var title: Title { card.app }
        var id: String { card.ref.titleId }
        /// the average out of 10, as everywhere in the app
        var rating: Double? { card.score.map { $0 / 10 } }

        /// "Novel · 2021"
        var line: String {
            role.isEmpty ? PeopleCaption.line([card.format, card.year.map(String.init)]) : role
        }
    }

    var detail: PersonDetail
    var id: String

    init(_ d: PersonDetail, id: String) {
        detail = d
        if case .author(let i) = d.ref { self.id = i } else { self.id = id }
    }

    var name: String { detail.name }
    var photo: URL? { detail.image }
    var prose: PeopleProse { PeopleProse(detail.bio) }

    /// "Author"
    var headline: String { detail.known.isEmpty ? "Author" : detail.known }
    var bornLine: String? { PeopleCaption.born(detail.facts) }

    /// every book, once ("Books" holds them all; "Most read" is its top)
    var books: [Book] {
        let g = detail.groups.first { $0.title == "Books" } ?? detail.groups.first
        var seen = Set<String>()
        return (g?.items ?? []).filter { seen.insert($0.title.ref.titleId).inserted }
            .map { Book(card: $0.title, role: $0.role) }
    }

    /// "Works  48": everything Open Library lists, which can be more than the books shown
    var works: Int? { detail.facts.first { $0.label == "Works" }.flatMap { Int($0.value.filter(\.isNumber)) } }

    /// the mean of the rated books, "8.4"
    var averageRating: String? {
        let r = books.compactMap(\.rating)
        guard !r.isEmpty else { return nil }
        return Format.average(r.reduce(0, +) / Double(r.count))
    }

    /// newest first, or oldest first
    func sorted(newestFirst: Bool = true) -> [Book] {
        books.enumerated().sorted { a, b in
            let ya = a.element.card.year ?? 0, yb = b.element.card.year ?? 0
            if ya == yb { return a.offset < b.offset }
            return newestFirst ? ya > yb : ya < yb
        }.map(\.element)
    }

    func inLibrary(_ lib: [LibraryEntry]) -> Int {
        let ids = Set(lib.map(\.id))
        return books.filter { ids.contains($0.id) }.count
    }

    /// "p. 212 of 496"
    static func pageLine(_ e: LibraryEntry) -> String {
        "p. \(Format.grouped(e.progress))" + (e.title.total.map { " of \(Format.grouped($0))" } ?? "")
    }
}
