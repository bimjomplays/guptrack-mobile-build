import Foundation
import Observation

// The Library tab's logic (32-40): the five media lists with their counts, a list's status chips, sorting, the
// format filter, rows or covers, the captions in its rows, and custom lists (loading, creating, editing, deleting).
// The library itself is the offline `model.library`; custom lists come from the app API.

// MARK: a media list's view, sort and filters

/// How a media list shows its titles (35): rows with progress and +1, or a grid of covers. Remembered per media.
enum LibraryViewMode: String, CaseIterable, Identifiable, Sendable {
    case rows, covers

    var id: String { rawValue }

    var label: String { self == .rows ? "Rows" : "Covers" }

    var symbol: String { self == .rows ? "list.bullet" : "square.grid.2x2" }

    /// the toolbar button switches to the other one and shows its icon
    var other: LibraryViewMode { self == .rows ? .covers : .rows }
}

/// A media list's order (36). Remembered per media.
enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case updated, title, score, progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updated: return "Last updated"
        case .title: return "Title"
        case .score: return "Score"
        case .progress: return "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .updated: return "clock"
        case .title: return "textformat"
        case .score: return "star"
        case .progress: return "chart.bar"
        }
    }

    /// last updated first; A-Z; best score first (unscored last); furthest along first
    func sorted(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.sorted { a, b in
            switch self {
            case .updated:
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            case .title:
                let r = a.title.name.localizedCaseInsensitiveCompare(b.title.name)
                if r != .orderedSame { return r == .orderedAscending }
            case .score:
                let sa = a.score ?? -1, sb = b.score ?? -1
                if sa != sb { return sa > sb }
            case .progress:
                let fa = a.status == .completed ? 1 : (a.fraction ?? 0), fb = b.status == .completed ? 1 : (b.fraction ?? 0)
                if fa != fb { return fa > fb }
                if a.progress != b.progress { return a.progress > b.progress }
            }
            if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
            return a.id < b.id
        }
    }
}

/// A format filter (36): "All formats", "TV", "Film", "OVA · ONA · Special" for anime; the formats on your list
/// for the others.
struct LibraryFormat: Hashable, Identifiable, Sendable {
    var id: String
    var label: String
    /// the title formats it keeps (lowercased); nil keeps everything
    var formats: Set<String>?

    static let all = LibraryFormat(id: "all", label: "All formats", formats: nil)

    func matches(_ e: LibraryEntry) -> Bool {
        guard let formats else { return true }
        return formats.contains((e.title.format ?? "").lowercased())
    }

    /// the choices for a media's list; just "All formats" when there's nothing to tell apart
    static func options(for media: MediaKind, in entries: [LibraryEntry]) -> [LibraryFormat] {
        if media == .anime {
            return [.all,
                    LibraryFormat(id: "tv", label: "TV", formats: ["tv", "tv short", "tv_short"]),
                    LibraryFormat(id: "film", label: "Film", formats: ["movie", "film"]),
                    LibraryFormat(id: "short", label: "OVA · ONA · Special", formats: ["ova", "ona", "special", "music"])]
        }
        var counts: [String: Int] = [:]
        for e in entries where e.media == media {
            if let f = e.title.format, !f.isEmpty { counts[f, default: 0] += 1 }
        }
        guard counts.count > 1 else { return [.all] }
        let found = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        return [.all] + found.map { LibraryFormat(id: $0.key.lowercased(), label: $0.key, formats: [$0.key.lowercased()]) }
    }
}

/// One status chip over a media list (33): "All 194", "Watching 7"…
struct LibraryStatusChip: Hashable, Identifiable, Sendable {
    /// nil is All
    var status: ListStatus?
    var label: String
    var count: Int

    var id: String { status?.rawValue ?? "all" }
}

enum LibraryLists {
    /// a status filter keeps rewatches under Watching
    static func keeps(_ status: ListStatus?, _ e: LibraryEntry) -> Bool {
        guard let status else { return true }
        if status == .current { return e.status.isActive }
        return e.status == status
    }

    /// All, then the five statuses in the website's order, each with its count (zeros too, as on the website)
    static func chips(_ entries: [LibraryEntry], media: MediaKind) -> [LibraryStatusChip] {
        let mine = entries.filter { $0.media == media }
        return [LibraryStatusChip(status: nil, label: "All", count: mine.count)]
            + ListStatus.ordered.map { s in
                LibraryStatusChip(status: s, label: s.label(media), count: mine.filter { keeps(s, $0) }.count)
            }
    }

    /// what a media list shows: its media, the status chip, the format, the search, in the chosen order
    static func shown(_ entries: [LibraryEntry], media: MediaKind, status: ListStatus?, format: LibraryFormat = .all,
                      query: String = "", sort: LibrarySort = .updated) -> [LibraryEntry] {
        sort.sorted(entries.filter {
            $0.media == media && keeps(status, $0) && format.matches($0) && matchesQuery(query, $0)
        })
    }

    /// a search over the title, its other names and its studio or author
    static func matchesQuery(_ query: String, _ e: LibraryEntry) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return [e.title.name, e.title.subtitle ?? "", e.title.studio ?? ""].contains {
            $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// the whole library's search (the Library tab's search): last updated first
    static func search(_ entries: [LibraryEntry], _ query: String) -> [LibraryEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return LibrarySort.updated.sorted(entries.filter { matchesQuery(q, $0) })
    }

    // MARK: the Library root (32)

    /// "7 watching", "1 reading", "41 watched" (films are watched or not)
    static func mediaLine(_ entries: [LibraryEntry], media: MediaKind) -> String {
        let mine = entries.filter { $0.media == media }
        if media == .movie {
            return "\(Format.grouped(mine.filter { $0.status == .completed }.count)) watched"
        }
        return "\(Format.grouped(mine.filter { $0.status.isActive }.count)) \(ListStatus.current.label(media).lowercased())"
    }

    /// the Library root's icon for a media (the mockup's tv / book-open / monitor-play / clapperboard / book)
    static func symbol(_ media: MediaKind) -> String {
        switch media {
        case .anime: return "tv"
        case .manga: return "book"
        case .tv: return "play.tv"
        case .movie: return "movieclapper"
        case .book: return "book.closed"
        }
    }

    /// the icon's colour (indigo, orange, green, pink, cyan)
    static func colorHex(_ media: MediaKind) -> UInt32 {
        switch media {
        case .anime: return 0x5E5CE6
        case .manga: return 0xFF9F0A
        case .tv: return 0x30D158
        case .movie: return 0xFF375F
        case .book: return 0x64D2FF
        }
    }

    // MARK: a list's header (33)

    /// "194 entries · 45.3 days watched · 8.28 mean score" ("1,234 chapters read" for manga, "pages read" for books)
    static func summary(_ entries: [LibraryEntry], media: MediaKind) -> String {
        let mine = entries.filter { $0.media == media }
        var parts = ["\(Format.grouped(mine.count)) \(mine.count == 1 ? "entry" : "entries")"]
        switch media {
        case .anime, .tv, .movie:
            let minutes = mine.reduce(0) { $0 + minutesWatched($1) }
            if minutes > 0 { parts.append("\(Format.days(minutes: minutes)) days watched") }
        case .manga, .book:
            let read = mine.reduce(0) { $0 + $1.progress }
            if read > 0, let unit = media.unit { parts.append("\(Format.grouped(read)) \(unit)s read") }
        }
        if let mean = meanScore(mine) { parts.append("\(mean) mean score") }
        return parts.joined(separator: " · ")
    }

    /// the mean of the scored entries out of 10, two decimals ("8.28"); nil when nothing is scored
    static func meanScore(_ entries: [LibraryEntry]) -> String? {
        let scores = entries.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        let mean = Double(scores.reduce(0, +)) / Double(scores.count) / 10
        return String(format: "%.2f", mean)
    }

    /// minutes spent on an entry: episodes watched × an episode's length; a watched film's length
    static func minutesWatched(_ e: LibraryEntry) -> Int {
        let per = runtimeMinutes(e.title.runtime) ?? (e.media == .movie ? 110 : e.media == .tv ? 45 : 24)
        if e.media == .movie { return e.status == .completed || e.progress > 0 ? per : 0 }
        return e.progress * per
    }

    /// "24 min" -> 24, "2h 47m" -> 167, "1h" -> 60, "45m" -> 45
    static func runtimeMinutes(_ s: String?) -> Int? {
        guard let s, !s.isEmpty else { return nil }
        var total = 0, number = 0, found = false
        for ch in s.lowercased() {
            if let d = ch.wholeNumberValue {
                number = number * 10 + d
            } else if ch == "h" {
                total += number * 60; number = 0; found = true
            } else if ch == "m" {
                total += number; number = 0; found = true
            }
        }
        if !found && number > 0 { total = number; found = true }
        return found && total > 0 ? total : nil
    }

    // MARK: a row (33, 37)

    /// the format as a row shows it: an anime film is "Film"
    static func formatLabel(_ t: Title) -> String {
        guard let f = t.format, !f.isEmpty else { return t.media.singular }
        if t.media == .anime && f.lowercased() == "movie" { return "Film" }
        return f
    }

    /// "ONA · 11 episodes", "TV · ? episodes", "Manga · 97 chapters", "Film · 2h 47m"
    static func caption(_ t: Title) -> String {
        let format = formatLabel(t)
        if t.media == .movie || (t.media == .anime && format == "Film") {
            return [format, t.runtime].compactMap { $0 }.joined(separator: " · ")
        }
        guard let unit = t.media.unit else { return format }
        if let total = t.total { return "\(format) · \(t.media.units(total))" }
        return "\(format) · ? \(unit)s"
    }

    /// what's on the row's right under the score: "6/11", "1150/?", the total once completed; nothing for films
    static func progressText(_ e: LibraryEntry) -> String? {
        if e.media == .movie { return nil }
        if e.status == .completed { return Format.grouped(e.title.total ?? e.progress) }
        if e.title.total == 1 && e.progress == 0 { return nil }
        return "\(Format.grouped(e.progress))/\(e.title.total.map { Format.grouped($0) } ?? "?")"
    }

    /// a row has +1 (and the swipe right) while you're on it and there's more to go
    static func canStep(_ e: LibraryEntry) -> Bool {
        e.status.isActive && e.media.unit != nil && (e.left.map { $0 > 0 } ?? true)
    }

    /// the swipe right's label: the episode, chapter or page it takes you to ("Ep 7", "Ch 98", "p. 222")
    static func stepLabel(_ e: LibraryEntry) -> String {
        let next = e.progress + e.media.step
        let capped = e.title.total.map { min(next, $0) } ?? next
        return "\(e.media.unitShort) \(Format.grouped(capped))"
    }

    /// "5 min ago", "15 hours ago", "yesterday", "4 days ago", then the date ("Jun 29, 2026")
    static func when(_ d: Date, now: Date = Clock.now) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        if s < 86_400 { let h = Int((s / 3600).rounded()); return h == 1 ? "1 hour ago" : "\(min(h, 23)) hours ago" }
        let days = -Format.dayOffset(d, now: now)
        if days <= 1 { return "yesterday" }
        if days < 30 { return "\(days) days ago" }
        return Format.longDay(d)
    }
}

// MARK: custom lists (32, 38-40)

extension Visibility {
    /// the line under "Who can see it" (40)
    var listFootnote: String {
        switch self {
        case .public: return "Anyone signed in to GupTrack can see it on your profile."
        case .friends: return "Only your friends can see it, on your profile."
        case .private: return "Only you can see it."
        }
    }
}

extension CustomList {
    /// "12 titles", "1 title"
    var countLine: String { "\(Format.grouped(items.count)) \(items.count == 1 ? "title" : "titles")" }

    /// "Public · 12 titles · updated yesterday" (38)
    func metaLine(now: Date = Clock.now) -> String {
        "\(visibility.label) · \(countLine) · updated \(LibraryLists.when(updatedAt, now: now))"
    }

    /// "12 titles · drag to reorder" (39)
    var reorderLine: String { "\(countLine) · drag to reorder" }
}

/// What the new-list sheet and the list editor change (39, 40).
struct CustomListDraft: Equatable, Sendable {
    var name = ""
    var description = ""
    var visibility: Visibility = .public
    var items: [CustomListItem] = []

    init(name: String = "", description: String = "", visibility: Visibility = .public, items: [CustomListItem] = []) {
        self.name = name
        self.description = description
        self.visibility = visibility
        self.items = items
    }

    init(_ list: CustomList) {
        self.init(name: list.name, description: list.description ?? "", visibility: list.visibility, items: list.items)
    }

    /// "12 titles · drag to reorder" as the editor has it now
    var reorderLine: String {
        "\(Format.grouped(items.count)) \(items.count == 1 ? "title" : "titles") · drag to reorder"
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedDescription: String? {
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return d.isEmpty ? nil : d
    }

    /// a list needs a name (100 characters at most, as on the website)
    var isValid: Bool { !trimmedName.isEmpty && trimmedName.count <= 100 }

    mutating func move(from source: IndexSet, to destination: Int) {
        // IndexSet moves as SwiftUI's onMove does them, without SwiftUI (the Kit is Foundation only)
        let moving = source.sorted().map { items[$0] }
        var rest = items.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let before = source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: min(rest.count, destination - before))
        items = rest
    }

    mutating func remove(at offsets: IndexSet) {
        items = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    }

    /// a title's note: blank takes it off
    mutating func setNote(_ note: String, for titleId: String) {
        guard let i = items.firstIndex(where: { $0.id == titleId }) else { return }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        items[i].note = n.isEmpty ? nil : n
    }

    /// add a title to the end (not twice)
    mutating func add(_ title: Title) {
        guard !items.contains(where: { $0.id == title.id }) else { return }
        items.append(CustomListItem(title: title, note: nil))
    }

    /// the list as it is once saved
    func applied(to list: CustomList, at now: Date = Clock.now) -> CustomList {
        var l = list
        l.name = trimmedName
        l.description = trimmedDescription
        l.visibility = visibility
        l.items = items
        l.updatedAt = now
        return l
    }

    /// a new list from the sheet (the server's id when it gave one)
    func created(id: String, at now: Date = Clock.now) -> CustomList {
        CustomList(id: id, name: trimmedName, description: trimmedDescription, visibility: visibility, items: items,
                   updatedAt: now)
    }

    var body: CustomListBody {
        CustomListBody(name: trimmedName, description: trimmedDescription ?? "", visibility: visibility,
                       items: items.map { CustomListBody.Item(titleId: $0.id, note: $0.note) })
    }
}

/// POST lists and PATCH lists/<id>: the list's fields and its titles in order with their notes
struct CustomListBody: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable {
        var titleId: String
        var note: String?
    }

    var name: String
    var description: String
    var visibility: Visibility
    var items: [Item]
}

/// the server's answer to creating a list: ok, and the new list's id (the demo leaves it out)
struct CustomListCreated: Codable, Equatable, Sendable {
    var ok: Bool
    var id: String?
}

extension APIClient {
    /// GET lists/<id>: one custom list
    func customList(_ id: String) async throws -> CustomList { try await get("lists/" + id) }

    /// POST lists
    func createList(_ body: CustomListBody) async throws -> CustomListCreated { try await send("POST", "lists", body) }

    /// PATCH lists/<id>
    func updateList(_ id: String, _ body: CustomListBody) async throws -> OKReply {
        try await send("PATCH", "lists/" + id, body)
    }

    /// DELETE lists/<id>
    func deleteList(_ id: String) async throws -> OKReply { try await send("DELETE", "lists/" + id) }
}

/// Custom lists as saved on this iPhone since they were loaded: made, changed and deleted ones, laid over what the
/// server sent, so every Library page shows the same lists right after a save.
@Observable @MainActor
final class CustomListEdits {
    private(set) var created: [CustomList] = []
    private(set) var saved: [String: CustomList] = [:]
    private(set) var deleted: Set<String> = []

    private static var current = CustomListEdits()
    private static weak var owner: AnyObject?

    /// the edits for this app session (a new AppModel, e.g. signing in again or a screen test, starts clean)
    static func shared(for model: AnyObject) -> CustomListEdits {
        if owner !== model {
            owner = model
            current = CustomListEdits()
        }
        return current
    }

    /// the server's lists with this iPhone's changes: new ones first
    func merged(_ loaded: [CustomList]) -> [CustomList] {
        let known = Set(loaded.map(\.id))
        let fresh = created.filter { !known.contains($0.id) && !deleted.contains($0.id) }.map { saved[$0.id] ?? $0 }
        return fresh + loaded.filter { !deleted.contains($0.id) }.map { saved[$0.id] ?? $0 }
    }

    /// a list saved or made here (shown without loading)
    func local(_ id: String) -> CustomList? {
        if deleted.contains(id) { return nil }
        return saved[id] ?? created.first { $0.id == id }
    }

    func isDeleted(_ id: String) -> Bool { deleted.contains(id) }

    func didCreate(_ list: CustomList) { created.insert(list, at: 0) }

    func didSave(_ list: CustomList) { saved[list.id] = list }

    func didDelete(_ id: String) { deleted.insert(id) }

    /// an id for a list the server didn't name: "winter-evenings", "winter-evenings-2"…
    func newId(for name: String, taken: [String]) -> String {
        let base = Demo.slug(name).isEmpty ? "list" : Demo.slug(name)
        let all = Set(taken + created.map(\.id))
        var id = base, n = 2
        while all.contains(id) { id = "\(base)-\(n)"; n += 1 }
        return id
    }
}
