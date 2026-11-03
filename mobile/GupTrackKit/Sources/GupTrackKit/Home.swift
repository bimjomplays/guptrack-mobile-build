import Foundation

/// GET home: what Home needs from the server beyond your own library (trending titles, unread notifications).
/// Continue, Upcoming, Stalled and Start something come from the offline library, so Home works offline.
struct HomeFeed: Codable, Equatable, Sendable {
    var trending: [Title]
    var unreadNotifications: Int
}

extension APIClient {
    func home() async throws -> HomeFeed { try await get("home") }
}

/// Home's shelves, worked out from the library (the website's Home does the same).
enum HomeShelves {
    /// a current title with no progress for this long is Stalled instead of in Continue
    static let stallDays = 30

    static func isStalled(_ e: LibraryEntry, now: Date = Clock.now) -> Bool {
        e.status.isActive && now.timeIntervalSince(e.updatedAt) > Double(stallDays) * 86_400
    }

    /// everything you're watching or reading (the "10 in progress" count), stalled ones too
    static func inProgress(_ lib: [LibraryEntry]) -> [LibraryEntry] {
        lib.filter { $0.status.isActive }
    }

    /// Continue: what you're on, last touched first
    static func continuing(_ lib: [LibraryEntry], now: Date = Clock.now) -> [LibraryEntry] {
        inProgress(lib).filter { !isStalled($0, now: now) }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Stalled: no progress in 30+ days, longest-forgotten first
    static func stalled(_ lib: [LibraryEntry], now: Date = Clock.now) -> [LibraryEntry] {
        inProgress(lib).filter { isStalled($0, now: now) }.sorted { $0.updatedAt < $1.updatedAt }
    }

    /// Upcoming: next episodes of what you watch (soonest first), then of what you plan to watch
    static func upcoming(_ lib: [LibraryEntry], now: Date = Clock.now) -> [LibraryEntry] {
        func airing(_ s: (ListStatus) -> Bool) -> [LibraryEntry] {
            lib.filter { s($0.status) && ($0.title.next.map { $0.at > now } ?? false) }
                .sorted { $0.title.next!.at < $1.title.next!.at }
        }
        return airing { $0.isActive } + airing { $0 == .planned }
    }

    /// "Ep 7 · Fri 3:00 AM" this week, "Ep 1181 · Jan 3" later
    static func upcomingCaption(_ a: Airing, media: MediaKind = .anime, now: Date = Clock.now) -> String {
        let days = Format.dayOffset(a.at, now: now)
        let when = days < 7 ? Format.weekdayTime(a.at) : Format.shortDay(a.at)
        return "\(media.unitShort) \(a.episode) · \(when)"
    }

    /// Start something: planned anime, TV and films with artwork, last added first; Shuffle moves along
    static func startCandidates(_ lib: [LibraryEntry]) -> [LibraryEntry] {
        lib.filter { $0.status == .planned && [.anime, .tv, .movie].contains($0.media) && $0.title.banner != nil }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// the line under Start something's title: "TV · 25 episodes · Lerche"
    static func startLine(_ t: Title) -> String {
        var parts: [String] = []
        if let f = t.format { parts.append(f) }
        if let n = t.total, t.media.unit != nil { parts.append(t.media.units(n)) }
        else if let r = t.runtime { parts.append(r) }
        if let s = t.studio { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    /// a trending card's caption: "Ep 6 out" while airing, else the average score
    static func trendingCaption(_ t: Title) -> String? {
        if let n = t.next { return n.episode > 1 ? "\(t.media.unitShort) \(n.episode - 1) out" : "Starts \(Format.shortDay(n.at))" }
        return nil
    }
}
