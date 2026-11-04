import Foundation

// docs/app-api.md §6: the calendar. `GET calendar?from=<ms>&to=<ms>` → `CalendarData` (src/calendar/types.ts):
// the episodes, releases and starts of the titles on your Watching, Planning and On-Hold lists (plus new releases of
// what you completed), with the list entries they belong to. Local midnights, `to` exclusive, about 3 months at most.
// The app asks one month at a time; your status comes from the offline library first, so an offline edit shows.

/// GET calendar's answer.
struct CalendarData: Codable, Hashable, Sendable {
    var items: [CalendarItem]
    /// the list entries the items belong to, by "<media>:<id>" (none for a sequel you haven't added)
    var entries: [String: ListEntry]
    /// the days asked for (ms, local midnights): from inclusive, to exclusive
    var from: Int64
    var to: Int64
    /// false: no TV and films (no TMDB key on the server)
    var tmdb: Bool
    var at: Int64

    /// several answers as one (a week across two months)
    static func merged(_ parts: [CalendarData]) -> CalendarData {
        var out = CalendarData(items: [], entries: [:], from: parts.map(\.from).min() ?? 0,
                               to: parts.map(\.to).max() ?? 0, tmdb: parts.allSatisfy(\.tmdb),
                               at: parts.map(\.at).max() ?? 0)
        var seen = Set<String>()
        for p in parts {
            out.items += p.items.filter { seen.insert($0.key).inserted }
            out.entries.merge(p.entries) { a, _ in a }
        }
        return out
    }
}

/// One thing on a day: an episode, a film coming out, a series starting.
struct CalendarItem: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable { case episode, release, start }

    /// unique on the page
    var key: String
    var media: APIMedia
    var id: String
    var ref: TitleRef
    var title: String
    @Picture var cover: URL?
    var kind: Kind
    /// episodes: counted the way the list counts (across seasons for shows); nil for the rest
    var number: Int?
    /// "Ep 7", "S2 · E5", "Film", "Anime film", "Anime", "Manga"
    var label: String
    /// "Premiere", "Season finale", "In cinemas"…
    var note: String?
    /// ms; with `dateOnly` only the day is known
    var at: Int64
    var dateOnly: Bool
    /// a new release of a Completed title: `sequelOf` names the Completed anime a sequel follows (the sequel is on
    /// none of your lists); nil for a Completed show's new episodes. nil on everything else.
    var news: News?

    struct News: Codable, Hashable, Sendable {
        var sequelOf: String?
    }

    init(key: String, media: APIMedia, id: String, title: String, cover: URL? = nil, kind: Kind = .episode,
         number: Int? = nil, label: String, note: String? = nil, at: Int64, dateOnly: Bool = false, news: News? = nil) {
        self.key = key
        self.media = media
        self.id = id
        self.ref = TitleRef(kind: media.kind, id: id)
        self.title = title
        _cover = Picture(wrappedValue: cover)
        self.kind = kind
        self.number = number
        self.label = label
        self.note = note
        self.at = at
        self.dateOnly = dateOnly
        self.news = news
    }

    var titleId: String { ref.titleId }
    var date: Date { Millis.date(at) }
    /// the list entry's key in `CalendarData.entries`
    var entryKey: String { "\(media.rawValue):\(id)" }
    /// the title's kind (anime films stay under Anime)
    var titleKind: MediaKind { ref.kind }

    /// a release (a film, an anime film) rather than an episode or a start
    var isFilm: Bool { kind == .release }

    /// the label in words: "Episode 5", "Season 6 · Episode 4", "Anime film"
    var what: String {
        let words = label.components(separatedBy: " · ")
        if words.count == 2, words[0].hasPrefix("S"), words[1].hasPrefix("E"),
           let s = Int(words[0].dropFirst()), let e = Int(words[1].dropFirst()) {
            return "Season \(s) · Episode \(e)"
        }
        if label.hasPrefix("Ep "), let n = Int(label.dropFirst(3)) { return "Episode \(n)" }
        return label
    }
}

/// The calendar's days, rows, filters and words (09, 10).
enum AiringSchedule {
    typealias Item = CalendarItem

    /// An item with the status it shows (yours from the library, else the list entry the answer came with).
    struct Row: Identifiable, Hashable, Sendable {
        var item: Item
        var status: ListStatus?

        var id: String { item.key }
        var titleId: String { item.titleId }
    }

    /// One day of the week view or of a tapped month day.
    struct Day: Identifiable, Hashable, Sendable {
        var date: Date
        var rows: [Row]

        var id: String { Format.day(date) }
    }

    enum Mode: String, CaseIterable, Identifiable, Hashable, Sendable {
        case week, month

        var id: String { rawValue }
        var label: String { self == .week ? "Week" : "Month" }
    }

    /// The status chips: which of your titles show.
    enum Show: String, CaseIterable, Identifiable, Hashable, Sendable {
        case watching, planning, completed, onHold, notOnList

        var id: String { rawValue }

        var label: String {
            switch self {
            case .watching: return "Watching"
            case .planning: return "Planning"
            case .completed: return "Completed"
            case .onHold: return "On-Hold"
            case .notOnList: return "Not on your list"
            }
        }

        func matches(_ s: ListStatus?) -> Bool {
            switch self {
            case .watching: return s == .current || s == .repeating
            case .planning: return s == .planned
            case .completed: return s == .completed
            case .onHold: return s == .hold
            case .notOnList: return s == nil
            }
        }
    }

    /// The type menu and the status chips (the mockups start on Watching + Planning).
    struct Filter: Hashable, Sendable {
        /// nil: all types
        var media: MediaKind?
        var shows: Set<Show> = [.watching, .planning]

        /// the kinds the calendar has (books don't air; manga only has its starts)
        static let kinds: [MediaKind] = [.anime, .manga, .tv, .movie]

        var mediaLabel: String { media?.plural ?? "All types" }

        func keeps(_ row: Row) -> Bool {
            if let media, row.item.titleKind != media { return false }
            if row.status == .dropped { return false }
            return shows.contains { $0.matches(row.status) }
        }

        mutating func toggle(_ s: Show) {
            if shows.contains(s) { shows.remove(s) } else { shows.insert(s) }
        }
    }

    // MARK: rows

    /// an item's status: the library's, else the entry the answer came with (a rewatch reads as Rewatching), else
    /// a Completed show's new episode is Completed; a sequel you haven't added has none
    static func status(_ item: Item, entries: [String: ListEntry], library: [String: ListStatus]) -> ListStatus? {
        if let s = library[item.titleId] { return s }
        if let e = entries[item.entryKey] {
            return e.rewatch != nil ? .repeating : ListStatus(rawValue: e.status.rawValue)
        }
        if let n = item.news, n.sequelOf == nil { return .completed }
        return nil
    }

    /// the items with your statuses, filtered, in the server's order (time, day-only first, title), one of each
    static func rows(_ items: [Item], entries: [String: ListEntry] = [:], library: [LibraryEntry],
                     filter: Filter = Filter()) -> [Row] {
        let mine = Dictionary(library.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return items
            .filter { seen.insert($0.key).inserted }
            .map { Row(item: $0, status: status($0, entries: entries, library: mine)) }
            .filter { filter.keeps($0) }
            .sorted {
                if $0.item.at != $1.item.at { return $0.item.at < $1.item.at }
                if $0.item.dateOnly != $1.item.dateOnly { return $0.item.dateOnly }
                return $0.item.title < $1.item.title
            }
    }

    static func rows(_ data: CalendarData, library: [LibraryEntry], filter: Filter = Filter()) -> [Row] {
        rows(data.items, entries: data.entries, library: library, filter: filter)
    }

    /// rows grouped onto the given days (each day keeps its order; days with nothing get an empty list)
    static func days(_ rows: [Row], on dates: [Date]) -> [Day] {
        let c = Clock.calendar
        return dates.map { d in Day(date: d, rows: rows.filter { c.isDate($0.item.date, inSameDayAs: d) }) }
    }

    // MARK: dates

    /// the Sunday a week starts on (00:00)
    static func weekStart(_ d: Date) -> Date {
        let c = Clock.calendar
        let day = c.startOfDay(for: d)
        let wd = c.component(.weekday, from: day)  // 1 = Sunday
        return c.date(byAdding: .day, value: -(wd - 1), to: day) ?? day
    }

    /// the first day of d's month (00:00)
    static func monthStart(_ d: Date) -> Date {
        let c = Clock.calendar
        return c.date(from: c.dateComponents([.year, .month], from: d)) ?? d
    }

    /// the first day of the month after d's
    static func nextMonthStart(_ d: Date) -> Date {
        Clock.calendar.date(byAdding: .month, value: 1, to: monthStart(d)) ?? d
    }

    /// seven days from a week's start
    static func weekDays(_ start: Date) -> [Date] {
        let c = Clock.calendar
        return (0..<7).compactMap { c.date(byAdding: .day, value: $0, to: start) }
    }

    /// every day of d's month
    static func monthDays(_ d: Date) -> [Date] {
        let c = Clock.calendar
        let first = monthStart(d)
        let n = c.range(of: .day, in: .month, for: first)?.count ?? 30
        return (0..<n).compactMap { c.date(byAdding: .day, value: $0, to: first) }
    }

    /// the month grid: blanks before the 1st so it sits under its weekday, then the days
    static func monthGrid(_ d: Date) -> [Date?] {
        let days = monthDays(d)
        guard let first = days.first else { return [] }
        let lead = Clock.calendar.component(.weekday, from: first) - 1
        return Array(repeating: nil, count: lead) + days.map { Optional($0) }
    }

    /// "2026-11"
    static func monthKey(_ d: Date) -> String {
        let c = Clock.calendar.dateComponents([.year, .month], from: d)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// the months to load for a view (their first days): one for a month, one or two for a week
    static func monthsToLoad(_ anchor: Date, mode: Mode) -> [Date] {
        switch mode {
        case .month: return [monthStart(anchor)]
        case .week:
            var out: [Date] = []
            for d in weekDays(weekStart(anchor)) where !out.contains(monthStart(d)) { out.append(monthStart(d)) }
            return out
        }
    }

    /// a week or a month on (or back)
    static func shift(_ anchor: Date, mode: Mode, by n: Int) -> Date {
        let c = Clock.calendar
        switch mode {
        case .week: return c.date(byAdding: .day, value: 7 * n, to: weekStart(anchor)) ?? anchor
        case .month: return c.date(byAdding: .month, value: n, to: monthStart(anchor)) ?? anchor
        }
    }

    // MARK: words

    /// "Nov 1 – 7, 2026", "Oct 25 – Nov 1, 2026", "Dec 27, 2026 – Jan 2, 2027"
    static func weekLabel(_ start: Date) -> String {
        let c = Clock.calendar
        let end = c.date(byAdding: .day, value: 6, to: start) ?? start
        let y1 = c.component(.year, from: start), y2 = c.component(.year, from: end)
        if y1 != y2 { return "\(Format.shortDay(start)), \(y1) – \(Format.shortDay(end)), \(y2)" }
        if c.component(.month, from: start) == c.component(.month, from: end) {
            return "\(Format.shortDay(start)) – \(c.component(.day, from: end)), \(y2)"
        }
        return "\(Format.shortDay(start)) – \(Format.shortDay(end)), \(y2)"
    }

    /// "November 2026"
    static func monthLabel(_ d: Date) -> String { ScheduleWords.format("MMMM yyyy", d) }

    /// "Tue, Nov 3" (week view)
    static func dayLabel(_ d: Date) -> String { ScheduleWords.format("EEE, MMM d", d) }

    /// "Friday, Nov 6" (under the month grid)
    static func longDayLabel(_ d: Date) -> String { ScheduleWords.format("EEEE, MMM d", d) }

    /// a row's time: "3:00 AM", or "All day" when only the day is known
    static func timeLabel(_ item: Item) -> String { item.dateOnly ? "All day" : Format.time(item.date) }

    /// "4 episodes", "1 episode", "2 releases", "Nothing airing"
    static func countLabel(_ rows: [Row]) -> String {
        if rows.isEmpty { return "Nothing airing" }
        let n = rows.count
        if rows.allSatisfy({ $0.item.kind == .episode }) { return "\(n) episode\(n == 1 ? "" : "s")" }
        return "\(n) release\(n == 1 ? "" : "s")"
    }

    /// "S", "M", "T", "W", "T", "F", "S"
    static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    // MARK: today

    /// where the now line goes in today's rows: before the first that hasn't aired (rows.count after them all)
    static func nowIndex(_ rows: [Row], now: Date = Clock.now) -> Int {
        rows.firstIndex { !isOut($0, now: now) } ?? rows.count
    }

    /// out already (a day-only one is out on its day)
    static func isOut(_ row: Row, now: Date = Clock.now) -> Bool { row.item.date <= now }

    /// past days fold to one line in the week view
    static func isPast(_ d: Date, now: Date = Clock.now) -> Bool { Format.dayOffset(d, now: now) < 0 }

    static func isToday(_ d: Date, now: Date = Clock.now) -> Bool { Format.dayOffset(d, now: now) == 0 }

    /// a month day's dots: the statuses airing that day, each once, in the legend's order, at most three
    /// (nil: a title that isn't on your list)
    static func dots(_ rows: [Row]) -> [ListStatus?] {
        let order: [ListStatus?] = [.current, .planned, .completed, .hold, nil]
        let here = Set(rows.map { $0.status == .repeating ? ListStatus.current : $0.status })
        return Array(order.filter { here.contains($0) }.prefix(3))
    }

    /// the legend under the grid: the statuses the month has, in order
    static func legend(_ rows: [Row]) -> [ListStatus?] {
        let order: [ListStatus?] = [.current, .planned, .completed, .hold, nil]
        let here = Set(rows.map { $0.status == .repeating ? ListStatus.current : $0.status })
        return order.filter { here.contains($0) }
    }

    /// a status's word on the calendar ("Watching", "Plan to Watch", "Not on your list")
    static func statusLabel(_ s: ListStatus?, media: MediaKind) -> String {
        s?.label(media) ?? "Not on your list"
    }

    /// the second line of a row: "Episode 5 · Finale", "Sequel to Frieren · Premiere"
    static func detail(_ item: Item) -> String {
        var parts = [item.what]
        if let n = item.note, !item.what.localizedCaseInsensitiveContains(n) { parts.append(n) }
        if let of = item.news?.sequelOf, !of.isEmpty { parts.insert("Sequel to \(of)", at: 0) }
        return parts.joined(separator: " · ")
    }
}

/// date words the shared Format doesn't have (kept here so they can't clash)
enum ScheduleWords {
    static func format(_ pattern: String, _ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Clock.zone
        f.dateFormat = pattern
        return f.string(from: d)
    }
}

extension APIClient {
    /// GET calendar?from=<ms>&to=<ms>: local midnights, `to` exclusive
    func calendar(from: Date, to: Date) async throws -> CalendarData {
        try await get("calendar", query: [URLQueryItem(name: "from", value: String(Millis.of(from))),
                                          URLQueryItem(name: "to", value: String(Millis.of(to)))])
    }

    /// one month (d's)
    func calendar(month d: Date) async throws -> CalendarData {
        try await calendar(from: AiringSchedule.monthStart(d), to: AiringSchedule.nextMonthStart(d))
    }

    /// several months as one answer (a week across two months)
    func calendar(months: [Date]) async throws -> CalendarData {
        var parts: [CalendarData] = []
        for m in months { parts.append(try await calendar(month: m)) }
        return CalendarData.merged(parts)
    }
}
