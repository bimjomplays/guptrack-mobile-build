import Foundation

// docs/app-api.md §6: Home. `GET home` is the fast part (your own library), `GET home/live` the slow part (AniList and
// TMDB, cached), `POST home/picks` the "Start something" choices. Shapes: src/home/types.ts.

/// A title on one of your lists that you are watching or reading: `{ media, entry: ListEntry }`.
struct OnTheGo: Codable, Hashable, Sendable {
    var media: APIMedia
    var entry: ListEntry

    var titleId: String { TitleKey(media: media, id: entry.id).titleId }

    /// the entry as the screens show it; `updated` (days ago) dates it
    func library(now: Date = Clock.now) -> LibraryEntry {
        entry.library(media, updatedAt: now.addingTimeInterval(-entry.updated * 86_400))
    }
}

/// Episodes, chapters and pages logged in the last seven days, and the watch time.
struct Week: Codable, Hashable, Sendable {
    var episodes: Int
    var chapters: Int
    var pages: Int
    var minutes: Int
}

/// GET home: `HomeLibrary`. The activity lines are kept as the server wrote them (Activity, FriendActivity:
/// src/library/types.ts, src/social/types.ts); Home's screen doesn't show them.
struct HomeLibrary: Codable, Hashable, Sendable {
    var current: [OnTheGo]
    var week: Week
    var activity: [JSONValue]
    var friends: Friends
    /// titles on all your lists; 0 = a new, empty library
    var total: Int
    var at: Int64

    struct Friends: Codable, Hashable, Sendable {
        var count: Int
        var activity: [JSONValue]
    }
}

/// A sequel or related title not out yet.
struct Announcement: Codable, Hashable, Sendable {
    var ref: TitleRef
    var title: String
    @Picture var cover: URL?
    /// "Sequel", "Anime film", "Side story"…
    var what: String
    /// "Dec 11", "April 2027", "Date to be announced"
    var when: String
    /// "Follows Frieren"
    var link: String
}

/// A card on one of Home's shelves.
struct ShelfCard: Codable, Hashable, Sendable, Identifiable {
    var ref: TitleRef
    var title: String
    @Picture var cover: URL?
    /// "Ep 6 out", "Because you watched Severance", "Dec 11 · Film"
    var note: String

    var id: String { ref.titleId }
}

/// GET home/live: `HomeLive`.
struct HomeLive: Codable, Hashable, Sendable {
    var upcoming: [NextEpisode]
    var announced: [Announcement]
    var recommended: [ShelfCard]
    var comingSoon: [ShelfCard]
    /// anime only
    var trending: [ShelfCard]
}

/// POST home/picks's body: what's on show now ("<media>:<id>", the list's media), at most 10.
struct PicksBody: Codable, Hashable, Sendable {
    var avoid: [String]
}

extension APIClient {
    /// GET home: from your own library, fast; show it first
    func home() async throws -> HomeLibrary { try await get("home") }

    /// GET home/live: AniList and TMDB, slower; fill it in after `home`
    func homeLive() async throws -> HomeLive { try await get("home/live") }

    /// POST home/picks: random titles from your Planning lists, the ones in `avoid` last
    func picks(avoid: [String] = []) async throws -> [OnTheGo] {
        let keep = avoid.filter { $0.count <= 40 }.prefix(HomeShelves.maxAvoid)
        return try await send("POST", "home/picks", PicksBody(avoid: Array(keep)))
    }
}

/// GET resolve?url=…: `{ title: TitleRef | null }` (docs/app-api.md §8.4), the title a shared link names (AniList,
/// MyAnimeList, TMDB, IMDb, Open Library…). The share extension's demo matches links itself (ShareMatch); the
/// signed-in app asks this.
struct ResolveAnswer: Codable, Hashable, Sendable {
    var title: TitleRef?

    init(title: TitleRef?) { self.title = title }

    // `null` comes as a key with no value; decode it as nil rather than failing
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(TitleRef.self, forKey: .title)
    }
}

extension APIClient {
    /// GET resolve?url=…: nil when the link names no title GupTrack knows
    func resolve(url: String) async throws -> TitleRef? {
        let a: ResolveAnswer = try await get("resolve", query: [URLQueryItem(name: "url", value: url)])
        return a.title
    }
}

/// Home's shelves. Continue and Stalled come from the offline library (an edit shows at once, and they work
/// offline); Upcoming and Trending from home/live; Start something from home/picks.
enum HomeShelves {
    /// a current title with no progress for this long is Stalled instead of in Continue
    static let stallDays = 30
    /// home/picks takes at most this many keys to avoid
    static let maxAvoid = 10

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

    /// Upcoming: home/live's next episodes (soonest first, as the server sends them), without the ones that
    /// have aired since it answered, and without titles you've since dropped or finished
    static func upcoming(_ live: [NextEpisode], library: [LibraryEntry] = [], now: Date = Clock.now) -> [NextEpisode] {
        let status = Dictionary(library.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        return live.filter { n in
            let gone = n.dateOnly ? Format.dayOffset(n.date, now: now) < 0 : n.date <= now
            let s = status[n.titleId]
            return !gone && s != .dropped && s != .completed
        }
    }

    /// "Ep 7 · Fri 3:00 AM" this week, "Ep 1181 · Jan 3" later; a day-only one has no time ("Ep 4 · Wed")
    static func upcomingCaption(_ n: NextEpisode, now: Date = Clock.now) -> String { n.caption(now: now) }

    /// Start something: home/picks's choices as the screens show them (the library's own copy wins: it may have
    /// changed since). Without an answer (offline), your planned titles, last added first.
    static func startCandidates(_ picks: [OnTheGo]?, library: [LibraryEntry], now: Date = Clock.now) -> [LibraryEntry] {
        guard let picks else {
            return library.filter { $0.status == .planned }.sorted { $0.updatedAt > $1.updatedAt }
        }
        let mine = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return picks.compactMap { p in
            let e = mine[p.titleId] ?? p.library(now: now)
            return e.status == .planned ? e : nil
        }
    }

    /// what to tell home/picks to avoid: the cards shown lately, newest last ("anime:21170", "movies:1078605")
    static func avoid(_ shown: [String]) -> [String] {
        shown.compactMap { TitleKey(titleId: $0).map { "\($0.media.rawValue):\($0.id)" } }.suffix(maxAvoid)
    }

    /// the line under Start something's title: "TV · 25 episodes", "Movie · 2h 46m"
    static func startLine(_ t: Title) -> String {
        var parts: [String] = []
        if let f = t.format { parts.append(f) }
        if let n = t.total, t.media.unit != nil { parts.append(t.media.units(n)) }
        else if let r = t.runtime { parts.append(r) }
        if let s = t.studio { parts.append(s) }
        return parts.joined(separator: " · ")
    }
}
