import Foundation

// The people and companies around titles (28-31): characters, people (actors, voice actors, staff), studios
// (AniList studios, TMDB networks and companies) and authors. Ids: "character:40", "person:95075",
// "person:tmdb-1190668", "studio:569", "studio:tmdb-49", "author:OL7234434A". "Your status" on these pages always
// comes from the offline library, never from the page.

extension APIClient {
    func characterPage(_ id: String) async throws -> CharacterPage { try await get("characters/" + id) }
    func personPage(_ id: String) async throws -> PersonPage { try await get("people/" + id) }
    func studioPage(_ id: String) async throws -> StudioPage { try await get("studios/" + id) }
    func authorPage(_ id: String) async throws -> AuthorPage { try await get("authors/" + id) }
}

// MARK: shared bits

/// A birthday or birth date; the year is often unknown for characters.
struct PeopleDate: Codable, Hashable, Sendable {
    var year: Int?
    var month: Int
    var day: Int?

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "May 5", "Dec 27, 1995", "May 1955"
    var text: String {
        let m = Self.months[safe: month - 1] ?? ""
        var s = m
        if let day { s += " \(day)" }
        if let year { s += day == nil ? " \(year)" : ", \(year)" }
        return s
    }
}

/// AniList's descriptions in plain words: "__Height:__ 172 cm" lines become facts, ~!spoilers!~ are kept apart so
/// the page can hide them, [links](…) keep only their words, and a paragraph that was only a link goes.
struct PeopleProse: Hashable, Sendable {
    struct Fact: Hashable, Sendable {
        var label: String
        var value: String
    }

    var facts: [Fact]
    /// the text with spoilers left out
    var text: String
    /// the text with spoilers in
    var full: String

    var hasSpoilers: Bool { text != full }

    init(_ raw: String?) {
        let source = (raw ?? "").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "<br>", with: "\n")
        let hidden = Self.parse(Self.dropSpoilers(source))
        let shown = Self.parse(Self.showSpoilers(source))
        facts = hidden.facts
        text = hidden.text
        full = shown.text
    }

    /// facts and paragraphs of a text whose spoilers are already dropped or opened
    private static func parse(_ s: String) -> (facts: [Fact], text: String) {
        var facts: [Fact] = []
        var paragraphs: [String] = []
        for para in s.components(separatedBy: "\n\n") {
            if wasOnlyALink(para) { continue }
            var lines: [String] = []
            for line in para.components(separatedBy: "\n") {
                let plainLine = links(line).trimmingCharacters(in: .whitespaces)
                if plainLine.hasPrefix("__"), plainLine.contains(":__") {
                    if let f = factLine(plainLine) { facts.append(f) }
                    continue
                }
                lines.append(plainLine)
            }
            let t = tidy(lines.joined(separator: "\n"))
            if !t.isEmpty { paragraphs.append(t) }
        }
        return (facts, paragraphs.joined(separator: "\n\n"))
    }

    /// a fact's value by its label ("Height" -> "172 cm")
    func fact(_ label: String) -> String? {
        facts.first { $0.label.caseInsensitiveCompare(label) == .orderedSame }?.value
    }

    private static func factLine(_ line: String) -> Fact? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("__"), let close = t.range(of: ":__", range: t.index(t.startIndex, offsetBy: 2)..<t.endIndex)
        else { return nil }
        let label = String(t[t.index(t.startIndex, offsetBy: 2)..<close.lowerBound])
        let value = String(t[close.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty, !value.isEmpty else { return nil }
        return Fact(label: label, value: value)
    }

    private static func wasOnlyALink(_ para: String) -> Bool {
        let t = para.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("[") && t.hasSuffix(")") && !t.dropFirst().contains("[")
    }

    /// [words](url) -> words
    static func links(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "[", let close = s[i...].firstIndex(of: "]"), s.index(after: close) < s.endIndex,
               s[s.index(after: close)] == "(", let end = s[close...].firstIndex(of: ")") {
                out += s[s.index(after: i)..<close]
                i = s.index(after: end)
            } else {
                out.append(s[i])
                i = s.index(after: i)
            }
        }
        return out
    }

    private static func dropSpoilers(_ s: String) -> String {
        var out = ""
        var rest = Substring(s)
        while let open = rest.range(of: "~!") {
            out += rest[..<open.lowerBound]
            if let close = rest[open.upperBound...].range(of: "!~") {
                rest = rest[close.upperBound...]
            } else {
                rest = ""
            }
        }
        return out + rest
    }

    private static func showSpoilers(_ s: String) -> String {
        s.replacingOccurrences(of: "~!", with: "").replacingOccurrences(of: "!~", with: "")
    }

    private static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: "<br>", with: "\n")
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
}

// MARK: 28 character

/// GET characters/<id>: a character's page.
struct CharacterPage: Codable, Hashable, Sendable {
    struct Voice: Codable, Hashable, Identifiable, Sendable {
        /// "person:95075"; nil when we don't have their page
        var id: String?
        var name: String
        var native: String?
        var image: URL?
        var language: String?

        /// "Japanese · 田中真弓"
        var line: String { PeopleCaption.line([language, native]) }
    }

    struct Appearance: Codable, Hashable, Identifiable, Sendable {
        var title: Title
        /// "main", "supporting", "background"
        var role: String

        var id: String { title.id }
        var roleLabel: String { role.prefix(1).uppercased() + role.dropFirst() }

        /// "TV · 1999 · Main"
        var line: String {
            PeopleCaption.line([PeopleCaption.format(title), title.year.map(String.init), roleLabel])
        }
    }

    var id: String
    var name: String
    var native: String?
    var image: URL?
    var favourites: Int?
    var gender: String?
    var age: String?
    var birthday: PeopleDate?
    /// AniList markdown (facts, spoilers, links): read it through `prose`
    var description: String?
    var voices: [Voice]
    var appearances: [Appearance]
    /// every title they're in (the list may be shorter)
    var appearancesTotal: Int?

    var prose: PeopleProse { PeopleProse(description) }

    /// "Main character · ONE PIECE"
    var headline: String? {
        guard let first = appearances.first else { return nil }
        return "\(first.roleLabel) character · \(first.title.name)"
    }

    /// the columns under the head: Height, Birthday, Age, Gender (only the known ones)
    var facts: [PeopleProse.Fact] {
        var out: [PeopleProse.Fact] = []
        if let h = prose.fact("Height") { out.append(.init(label: "Height", value: h)) }
        if let b = birthday { out.append(.init(label: "Birthday", value: b.text)) }
        if let a = age, !a.isEmpty { out.append(.init(label: "Age", value: a.replacingOccurrences(of: "-", with: "–"))) }
        if let g = gender, !g.isEmpty { out.append(.init(label: "Gender", value: g)) }
        return Array(out.prefix(4))
    }

    var total: Int { appearancesTotal ?? appearances.count }
}

// MARK: 29 person

/// GET people/<id>: an actor, voice actor or staff member (AniList staff or a TMDB person).
struct PersonPage: Codable, Hashable, Sendable {
    struct CharacterRef: Codable, Hashable, Sendable {
        var id: String?
        var name: String
        var image: URL?
    }

    struct Credit: Codable, Hashable, Identifiable, Sendable {
        var title: Title
        /// "Paul Atreides" (an actor's part) or "Original Creator" (a staff job)
        var role: String?
        /// a voice role
        var character: CharacterRef?
        var main: Bool?

        var id: String { title.id + "|" + (character?.name ?? role ?? "") }
        var year: Int? { title.year }

        /// "as Paul Atreides", "Original Creator", "ONE PIECE · Main"
        var line: String {
            if character != nil {
                return PeopleCaption.line([title.name, main == true ? "Main" : "Supporting"])
            }
            guard let role, !role.isEmpty else { return PeopleCaption.format(title) }
            return title.media == .movie || title.media == .tv ? "as " + role : role
        }
    }

    /// one tab of the filmography: Movies 52, TV 14
    struct Group: Hashable, Identifiable, Sendable {
        var media: MediaKind
        var count: Int

        var id: MediaKind { media }
        var label: String { "\(media.plural) \(Format.grouped(count))" }
    }

    var id: String
    var name: String
    var native: String?
    var image: URL?
    /// "Actor", "Voice actor", "Original Creator"
    var occupation: String?
    var creditCount: Int?
    var favourites: Int?
    var born: PeopleDate?
    var birthplace: String?
    /// AniList markdown or TMDB's plain text: read it through `prose`
    var bio: String?
    var knownFor: [Title]
    var credits: [Credit]
    /// how many credits each media has in all ("movie": 52), when the list is shorter
    var totals: [String: Int]?

    var prose: PeopleProse { PeopleProse(bio) }

    /// voice actors list characters (Roles); actors and staff list titles (Filmography)
    var isVoice: Bool { credits.contains { $0.character != nil } }

    var creditsTitle: String { isVoice ? "Roles" : "Filmography" }

    /// "Actor · 66 credits", "Voice actor · 12 roles"
    var headline: String {
        let n = creditCount ?? credits.count
        let noun = isVoice ? "role" : "credit"
        return PeopleCaption.line([occupation, "\(Format.grouped(n)) \(noun)\(n == 1 ? "" : "s")"])
    }

    /// "Born Dec 27, 1995 · New York City"
    var bornLine: String? {
        guard born != nil || birthplace != nil else { return nil }
        return PeopleCaption.line([born.map { "Born " + $0.text }, birthplace])
    }

    /// the tabs, in a fixed order (Movies, TV, Anime, Manga, Books), only those with credits
    var groups: [Group] {
        let order: [MediaKind] = [.movie, .tv, .anime, .manga, .book]
        return order.compactMap { m in
            let listed = credits.filter { $0.title.media == m }.count
            guard listed > 0 else { return nil }
            return Group(media: m, count: max(listed, totals?[m.rawValue] ?? 0))
        }
    }

    /// one media's credits, newest first (unknown years, i.e. not out yet, first)
    func credits(_ media: MediaKind?) -> [Credit] {
        let list = media.map { m in credits.filter { $0.title.media == m } } ?? credits
        return list.enumerated().sorted { a, b in
            let ya = a.element.year ?? Int.max, yb = b.element.year ?? Int.max
            return ya != yb ? ya > yb : a.offset < b.offset
        }.map(\.element)
    }
}

// MARK: 30 studio

/// GET studios/<id>: an animation studio, a TV network or a film company, with its titles.
struct StudioPage: Codable, Hashable, Sendable {
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
            case "TV", "TV Short": return .tv
            case "Movie": return .film
            case "ONA": return .ona
            case "OVA": return .ova
            case "Special", "Music": return .special
            default:
                if t.media == .tv { return .tv }
                if t.media == .movie { return .film }
                return .other
            }
        }
    }

    /// one year's titles (nil year: not dated yet, last as "TBA")
    struct YearGroup: Hashable, Identifiable, Sendable {
        var year: Int?
        var titles: [Title]

        var id: Int { year ?? Int.min }
        var label: String { year.map(String.init) ?? "TBA" }
    }

    var id: String
    var name: String
    /// "Animation studio", "Network", "Production company"
    var kind: String?
    var place: String?
    var favourites: Int?
    var titles: [Title]
    /// every title (the list may be shorter)
    var total: Int?

    /// "Animation studio · Tokyo, Japan"
    var headline: String { PeopleCaption.line([kind, place]) }

    /// "24 titles · 6 in your library"
    func countLine(inLibrary n: Int) -> String {
        let all = total ?? titles.count
        var s = "\(Format.grouped(all)) title\(all == 1 ? "" : "s")"
        if n > 0 { s += " · \(n) in your library" }
        return s
    }

    /// All, then up to three formats with the most titles, in a fixed order; no filter at all when there's one kind
    var filters: [Filter] {
        var counts: [Filter: Int] = [:]
        for t in titles { counts[Self.Filter.of(t), default: 0] += 1 }
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

private extension StudioPage.Filter {
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: 31 author

/// GET authors/<id>: an author and their books.
struct AuthorPage: Codable, Hashable, Sendable {
    struct Book: Codable, Hashable, Identifiable, Sendable {
        var title: Title
        /// the average rating out of 5 (Open Library)
        var rating: Double?

        var id: String { title.id }

        /// "2021 · 496 pages"
        var line: String {
            PeopleCaption.line([title.year.map(String.init), title.total.map { "\(Format.grouped($0)) pages" }])
        }
    }

    var id: String
    var name: String
    var photo: URL?
    /// "Science fiction"
    var genre: String?
    var born: PeopleDate?
    var birthplace: String?
    var bio: String?
    var books: [Book]

    var prose: PeopleProse { PeopleProse(bio) }

    /// "Author · Science fiction"
    var headline: String { PeopleCaption.line(["Author", genre]) }

    /// "Born Jun 16, 1972 · Davis, California"
    var bornLine: String? {
        guard born != nil || birthplace != nil else { return nil }
        return PeopleCaption.line([born.map { "Born " + $0.text }, birthplace])
    }

    var pages: Int { books.reduce(0) { $0 + ($1.title.total ?? 0) } }

    /// the mean of the rated books, "4.2"
    var averageRating: String? {
        let r = books.compactMap(\.rating)
        guard !r.isEmpty else { return nil }
        return Format.average(r.reduce(0, +) / Double(r.count))
    }

    /// newest first, or oldest first
    func sorted(newestFirst: Bool = true) -> [Book] {
        books.enumerated().sorted { a, b in
            let ya = a.element.title.year ?? 0, yb = b.element.title.year ?? 0
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
