import Foundation

// Share to GupTrack (66): a link or some text shared from any app -> the title it means. Plain Foundation: the share
// extension compiles this file (with Models, Format, Route and WidgetSnapshot for ExtensionCatalog), and so do the
// app and the Linux tests.
//
// Demo: the extension matches against the bundled library and api/extensions.json. The real extension would send
// what it can't match to the server (the website already resolves AniList, TMDB, Open Library and MAL links).

enum ShareMatch {
    /// what a shared link points at
    enum Ref: Equatable, Sendable {
        /// a GupTrack title id ("anime:210482", "tv:95396", "movie:693134", "book:OL21745884W")
        case title(String)
        /// a MyAnimeList page: "anime/61469" (mapped to an AniList id through the catalogue)
        case mal(String)
        /// words to search for, from a page's slug ("letterboxd.com/film/dune-part-two" -> "dune part two")
        case words(String)
    }

    enum How: String, Equatable, Sendable {
        /// the link named the title
        case link
        /// found by its name
        case search
    }

    struct Found: Equatable, Sendable {
        var title: Title
        var how: How
        /// "themoviedb.org/tv/95396-severance" (nil when only text was shared)
        var link: String?
        /// the title as it is on your list, nil when it isn't
        var entry: LibraryEntry?
    }

    // MARK: links

    /// the title (or the words) a link points at; nil for links that say nothing (a home page)
    static func ref(_ url: URL) -> Ref? {
        if url.scheme?.lowercased() == "guptrack" {
            if case .title(let id)? = Route(url: url) { return .title(id) }
            return nil
        }
        guard let host = host(url) else { return nil }
        let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        let first = parts.first?.lowercased()
        let second = parts.count > 1 ? parts[1] : nil
        switch host {
        case "anilist.co":
            if let first, ["anime", "manga"].contains(first), let n = second.flatMap(leadingNumber) {
                return .title("\(first):\(n)")
            }
        case "myanimelist.net":
            if let first, ["anime", "manga"].contains(first), let n = second.flatMap(leadingNumber) {
                return .mal("\(first)/\(n)")
            }
        case "themoviedb.org":
            if let first, ["tv", "movie"].contains(first), let n = second.flatMap(leadingNumber) {
                return .title("\(first):\(n)")
            }
        case "openlibrary.org":
            if first == "works", let key = second, key.uppercased().hasPrefix("OL"), key.uppercased().hasSuffix("W") {
                return .title("book:" + key.uppercased())
            }
        default:
            break
        }
        // any other page: its last readable path part, as words ("/film/dune-part-two/" -> "dune part two")
        for p in parts.reversed() {
            let w = words(p)
            if w.count >= 3, w.contains(where: \.isLetter), !["film", "title", "show", "series", "book", "works", "books"].contains(w) {
                return .words(w)
            }
        }
        return nil
    }

    /// "www.themoviedb.org" -> "themoviedb.org"
    static func host(_ url: URL) -> String? {
        guard var h = url.host?.lowercased(), !h.isEmpty else { return nil }
        for p in ["www.", "m."] where h.hasPrefix(p) { h.removeFirst(p.count) }
        return h
    }

    /// the link as the sheet shows it: "themoviedb.org/tv/95396-severance" (no scheme, www, query or trailing /)
    static func label(_ url: URL) -> String {
        guard let h = host(url) else { return url.absoluteString }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return h + path
    }

    /// the first web or guptrack link in some text
    static func firstURL(in text: String) -> URL? {
        let pattern = #"(?i)\b(?:https?|guptrack)://[^\s<>"'”“]+"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        var s = String(text[range])
        while let last = s.last, ".,;:!?)]".contains(last) { s.removeLast() }
        return URL(string: s)
    }

    // MARK: matching

    /// what was shared (a link, or text with or without one) -> the title; nil when nothing fits
    static func resolve(_ shared: String, library: [LibraryEntry], catalog: ExtensionCatalog) -> Found? {
        let text = shared.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let titles = library.map(\.title) + catalog.titles
        func found(_ t: Title, _ how: How, _ link: String?) -> Found {
            Found(title: t, how: how, link: link, entry: library.first { $0.id == t.id })
        }
        let url = firstURL(in: text)
        let link = url.map(label)
        if let url, let ref = ref(url) {
            switch ref {
            case .title(let id):
                if let t = titles.first(where: { $0.id == id }) { return found(t, .link, link) }
            case .mal(let key):
                if let id = catalog.malIds[key], let t = titles.first(where: { $0.id == id }) {
                    return found(t, .link, link)
                }
            case .words(let w):
                if let t = search(w, in: titles) { return found(t, .search, link) }
            }
        }
        // the text around a link (a page's title: "Severance | Apple TV+"), or text on its own
        var rest = text
        if let url { rest = rest.replacingOccurrences(of: url.absoluteString, with: " ") }
        for piece in rest.components(separatedBy: CharacterSet(charactersIn: "|–—\n")) {
            if let t = search(piece, in: titles) { return found(t, .search, link) }
        }
        return nil
    }

    /// the best title for some words: the whole name, then a name that starts with them, then one that contains
    /// them (or is contained in them); the list's own titles first, then shorter names
    static func search(_ query: String, in titles: [Title]) -> Title? {
        let q = words(query)
        guard q.count >= 2 else { return nil }
        var best: (score: Int, len: Int, i: Int)?
        var pick: Title?
        for (i, t) in titles.enumerated() {
            let names = [t.name] + (t.subtitle?.components(separatedBy: " · ") ?? [])
            var score = 0
            for n in names.map(words) where !n.isEmpty {
                if n == q { score = max(score, 4) }
                else if n.hasPrefix(q + " ") { score = max(score, 3) }
                else if (" " + n + " ").contains(" " + q + " ") { score = max(score, 2) }
                else if n.count >= 4, (" " + q + " ").contains(" " + n + " ") { score = max(score, 1) }
            }
            guard score > 0 else { continue }
            let key = (score, -t.name.count, -i)
            if best.map({ key > ($0.score, -$0.len, -$0.i) }) ?? true {
                best = (score, t.name.count, i)
                pick = t
            }
        }
        return pick
    }

    /// lowercased words without accents or punctuation: "Frieren: Beyond Journey’s End" -> "frieren beyond journeys end"
    static func words(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
        var out = ""
        for ch in folded {
            out.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    static func leadingNumber(_ s: String) -> Int? {
        Int(s.prefix(while: \.isNumber))
    }

    // MARK: the sheet

    /// the line under the name: "TV · 2022 · 2 seasons", "Anime · ONA · 2026 · 11 episodes", "Movie · 2024 · 2h 46m"
    static func caption(_ t: Title, seasons: [Int]?) -> String {
        var parts = [t.kindLine]
        if let y = t.year { parts.append(String(y)) }
        if t.media == .tv, let s = seasons, !s.isEmpty {
            parts.append("\(s.count) season\(s.count == 1 ? "" : "s")")
        } else if let n = t.total, t.media.unit != nil {
            parts.append(t.media.units(n))
        } else if let r = t.runtime, t.media == .movie {
            parts.append(r)
        }
        return parts.joined(separator: " · ")
    }

    /// the statuses in the sheet's order (the mockup's chips)
    static let statuses: [ListStatus] = [.planned, .current, .completed, .hold, .dropped]

    /// the sheet's choices: what's on the list already, or Plan to Watch at 0 for a new title
    struct Draft: Equatable, Sendable {
        var status: ListStatus
        /// whole-title progress (every episode watched, for TV too)
        var progress: Int

        init(status: ListStatus, progress: Int) {
            self.status = status
            self.progress = progress
        }

        init(_ found: Found) {
            self.init(status: found.entry?.status ?? .planned, progress: found.entry?.progress ?? 0)
        }

        var patch: LibraryPatch { LibraryPatch(status: status, progress: progress) }

        /// a status chip: Completed fills the progress to the end when the end is known
        mutating func choose(_ s: ListStatus, max: Int?) {
            status = s
            if s == .completed, let max { progress = max }
        }

        /// the stepper: by one (books by 10 pages), between 0 and the end; going past 0 on a planned title starts it
        mutating func step(_ n: Int, media: MediaKind, max: Int?) {
            var v = Swift.max(0, progress + n * media.step)
            if let max { v = Swift.min(v, max) }
            progress = v
            if status == .planned, v > 0 { status = .current }
        }
    }

    /// the progress row: the stepper's number and total, and the line under "Progress" ("Season 2"); nil for films
    struct Stepper: Equatable, Sendable {
        var value: Int
        var total: Int?
        var note: String?
        /// the most the whole-title progress can be
        var max: Int?
    }

    static func stepper(_ t: Title, progress: Int, seasons: [Int]?) -> Stepper? {
        switch t.media {
        case .movie:
            return nil
        case .tv:
            if let pos = SeasonPosition.of(progress: progress, lengths: seasons) {
                return Stepper(value: pos.episode, total: pos.total, note: "Season \(pos.season)",
                               max: seasons?.reduce(0, +))
            }
            return Stepper(value: progress, total: t.total, note: nil, max: t.total)
        default:
            let note: String? = t.media == .book ? "Pages" : (t.media == .manga ? "Chapters" : nil)
            return Stepper(value: progress, total: t.total, note: note, max: t.total)
        }
    }

    /// "Add to TV", "Add to Anime", "Add to Movies"; "Save" when it's on your list already
    static func addLabel(_ found: Found) -> String {
        found.entry == nil ? "Add to \(found.title.media.plural)" : "Save"
    }
}
