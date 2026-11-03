import Foundation

/// GET schedule?month=2026-11: what airs in a month (09, 10). The server sends the episodes and releases of the
/// titles on your list (and may add popular ones); your status comes from the offline library, so an edit made
/// offline shows at once. The week view loads the one or two months its seven days touch.
struct AiringSchedule: Codable, Equatable, Sendable {
    /// "2026-11"
    var month: String
    var items: [Item]

    /// One episode (or a film's release) at a time.
    struct Item: Codable, Identifiable, Hashable, Sendable {
        var title: Title
        var at: Date
        var episode: Int?
        /// TV: the season the episode is in
        var season: Int?
        /// the server's copy of your status (nil when the title isn't on your list); the library's wins
        var status: ListStatus?

        var id: String { "\(title.id)@\(Int(at.timeIntervalSince1970))" }

        /// a film (anime films too: they stay under Anime, marked Film)
        var isFilm: Bool { title.media == .movie || title.format == "Movie" }

        /// "Episode 5", "Season 6 · Episode 4", "Film"
        var what: String {
            if isFilm || episode == nil { return "Film" }
            let ep = "Episode \(episode!)"
            if title.media == .tv, let season { return "Season \(season) · \(ep)" }
            return ep
        }
    }

    /// An item with the status it shows (yours from the library, else the server's).
    struct Row: Identifiable, Hashable, Sendable {
        var item: Item
        var status: ListStatus?

        var id: String { item.id }
        var titleId: String { item.title.id }
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
        case watching, planning, completed, onHold, dropped, notOnList

        var id: String { rawValue }

        var label: String {
            switch self {
            case .watching: return "Watching"
            case .planning: return "Planning"
            case .completed: return "Completed"
            case .onHold: return "On-Hold"
            case .dropped: return "Dropped"
            case .notOnList: return "Not on your list"
            }
        }

        func matches(_ s: ListStatus?) -> Bool {
            switch self {
            case .watching: return s == .current || s == .repeating
            case .planning: return s == .planned
            case .completed: return s == .completed
            case .onHold: return s == .hold
            case .dropped: return s == .dropped
            case .notOnList: return s == nil
            }
        }
    }

    /// The type menu and the status chips (the mockups start on Watching + Planning).
    struct Filter: Hashable, Sendable {
        /// nil: all types
        var media: MediaKind?
        var shows: Set<Show> = [.watching, .planning]

        /// the kinds the calendar has (books and manga don't air)
        static let kinds: [MediaKind] = [.anime, .tv, .movie]

        var mediaLabel: String { media?.plural ?? "All types" }

        func keeps(_ row: Row) -> Bool {
            if let media, row.item.title.media != media { return false }
            return shows.contains { $0.matches(row.status) }
        }

        mutating func toggle(_ s: Show) {
            if shows.contains(s) { shows.remove(s) } else { shows.insert(s) }
        }
    }

    // MARK: rows

    /// the items with your statuses, filtered, by time (one copy of each)
    static func rows(_ items: [Item], library: [LibraryEntry], filter: Filter = Filter()) -> [Row] {
        let mine = Dictionary(library.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        return items
            .filter { seen.insert($0.id).inserted }
            .map { Row(item: $0, status: mine[$0.title.id] ?? $0.status) }
            .filter { filter.keeps($0) }
            .sorted { $0.item.at == $1.item.at ? $0.item.title.name < $1.item.title.name : $0.item.at < $1.item.at }
    }

    /// rows grouped onto the given days (each day keeps its order; days with nothing get an empty list)
    static func days(_ rows: [Row], on dates: [Date]) -> [Day] {
        let c = Clock.calendar
        return dates.map { d in Day(date: d, rows: rows.filter { c.isDate($0.item.at, inSameDayAs: d) }) }
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

    /// the months to load for a view: one for a month, one or two for a week
    static func monthsToLoad(_ anchor: Date, mode: Mode) -> [String] {
        switch mode {
        case .month: return [monthKey(anchor)]
        case .week:
            var out: [String] = []
            for d in weekDays(weekStart(anchor)) where !out.contains(monthKey(d)) { out.append(monthKey(d)) }
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

    /// "4 episodes", "1 episode", "2 releases", "Nothing airing"
    static func countLabel(_ rows: [Row]) -> String {
        if rows.isEmpty { return "Nothing airing" }
        let n = rows.count
        if rows.allSatisfy({ !$0.item.isFilm }) { return "\(n) episode\(n == 1 ? "" : "s")" }
        return "\(n) release\(n == 1 ? "" : "s")"
    }

    /// "S", "M", "T", "W", "T", "F", "S"
    static let weekdayLetters = ["S", "M", "T", "W", "T", "F", "S"]

    // MARK: today

    /// where the now line goes in today's rows: before the first that hasn't aired (rows.count after them all)
    static func nowIndex(_ rows: [Row], now: Date = Clock.now) -> Int {
        rows.firstIndex { $0.item.at > now } ?? rows.count
    }

    static func isOut(_ row: Row, now: Date = Clock.now) -> Bool { row.item.at <= now }

    /// past days fold to one line in the week view
    static func isPast(_ d: Date, now: Date = Clock.now) -> Bool { Format.dayOffset(d, now: now) < 0 }

    static func isToday(_ d: Date, now: Date = Clock.now) -> Bool { Format.dayOffset(d, now: now) == 0 }

    /// a month day's dots: the statuses airing that day, each once, in the legend's order, at most three
    /// (nil: a title that isn't on your list)
    static func dots(_ rows: [Row]) -> [ListStatus?] {
        let order: [ListStatus?] = [.current, .repeating, .planned, .completed, .hold, .dropped, nil]
        let here = Set(rows.map { $0.status == .repeating ? ListStatus.current : $0.status })
        return Array(order.filter { here.contains($0) }.prefix(3))
    }

    /// the legend under the grid: the statuses the month has, in order
    static func legend(_ rows: [Row]) -> [ListStatus?] {
        let order: [ListStatus?] = [.current, .planned, .completed, .hold, .dropped, nil]
        let here = Set(rows.map { $0.status == .repeating ? ListStatus.current : $0.status })
        return order.filter { here.contains($0) }
    }

    /// a status's word on the calendar ("Watching", "Plan to Watch", "Not on your list")
    static func statusLabel(_ s: ListStatus?, media: MediaKind) -> String {
        s?.label(media) ?? "Not on your list"
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
    /// one month of the airing schedule ("2026-11")
    func airingSchedule(month: String) async throws -> AiringSchedule {
        try await get("schedule", query: [URLQueryItem(name: "month", value: month)])
    }

    /// several months' items together (a week across two months)
    func airingSchedule(months: [String]) async throws -> [AiringSchedule.Item] {
        var out: [AiringSchedule.Item] = []
        for m in months { out += try await airingSchedule(month: m).items }
        return out
    }
}
