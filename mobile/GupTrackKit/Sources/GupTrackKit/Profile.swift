import Foundation

// Profiles and statistics (41-43b, 48, 49): your own profile, someone else's, the Statistics page and Compare
// (docs/app-api.md §10.2, §10.4). The answers are the website's types (src/social/types.ts, src/library/types.ts,
// src/stats/types.ts); the numbers and words the screens show are worked out here.

// MARK: shared parts

/// a favourite character (FavouriteCharacter)
struct FavouriteCharacter: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var image: String
    var sub: String
}

/// a favourite person, author, studio, network or company (FavouriteName)
struct FavouriteName: Codable, Hashable, Identifiable, Sendable {
    /// person, author, studio, network, company
    var kind: String
    var id: String
    var name: String
    var image: String
    var sub: String
}

/// Per list: the numbers the profile shows (MediaStats).
struct MediaStats: Codable, Hashable, Sendable {
    var media: APIMedia
    var entries: Int
    /// status -> how many
    var counts: [String: Int]
    /// mean of the scored entries out of 100, 0 when none
    var meanScore: Double
    var scored: Int
    /// days watched (anime, TV, movies), chapters read (manga) or pages read (books)
    var amount: Double
    /// episodes / chapters / pages logged, rewatches not counted
    var progress: Int
    var repeats: Int
    var favourites: Int

    var kind: MediaKind { media.kind }

    static func empty(_ media: MediaKind) -> MediaStats {
        MediaStats(media: media.api, entries: 0, counts: [:], meanScore: 0, scored: 0, amount: 0, progress: 0,
                   repeats: 0, favourites: 0)
    }

    func count(_ s: ListStatus) -> Int { s == .repeating ? 0 : counts[s.rawValue] ?? 0 }

    /// the status bar's counts
    var statusCounts: [ListStatus: Int] {
        Dictionary(uniqueKeysWithValues: ListStatus.ordered.map { ($0, count($0)) })
    }

    /// "4%" of the entries
    func percent(_ s: ListStatus) -> String {
        guard entries > 0 else { return "0%" }
        return "\(Int((Double(count(s)) / Double(entries) * 100).rounded()))%"
    }

    /// "8.28" (two decimals, as the website), "–" when nothing is scored
    var meanText: String { ProfileText.mean(meanScore) }

    /// the four columns under the media switch (41, 48)
    var columns: [StatColumn] {
        let mean = StatColumn(value: meanText, label: "Mean score")
        let days = Format.trim((amount * 10).rounded() / 10)
        let amountText = Format.grouped(Int(amount.rounded()))
        switch kind {
        case .anime, .tv:
            return [StatColumn(value: days, label: "Days"), mean,
                    StatColumn(value: Format.grouped(repeats), label: "Rewatched"),
                    StatColumn(value: Format.grouped(progress), label: "Episodes")]
        case .movie:
            return [StatColumn(value: days, label: "Days"), mean,
                    StatColumn(value: Format.grouped(repeats), label: "Rewatched"),
                    StatColumn(value: Format.grouped(count(.completed)), label: "Films")]
        case .manga:
            return [StatColumn(value: amountText, label: "Chapters"), mean,
                    StatColumn(value: Format.grouped(repeats), label: "Reread"),
                    StatColumn(value: Format.grouped(count(.completed)), label: "Completed")]
        case .book:
            return [StatColumn(value: amountText, label: "Pages"), mean,
                    StatColumn(value: Format.grouped(repeats), label: "Reread"),
                    StatColumn(value: Format.grouped(count(.completed)), label: "Books read")]
        }
    }
}

struct StatColumn: Hashable, Sendable {
    var value: String
    var label: String
}

/// what the bio (BioState) gives the profile's top: the banner, its fade and the words
struct ProfileBio: Hashable, Sendable {
    var banner: URL?
    /// 0...1, how solid the shade at the banner's bottom is; 0 when the fade is off
    var fade: Double
    /// the bio's words, one paragraph a line
    var text: String

    static let defaultFade = 0.74

    init(banner: URL? = nil, fade: Double = defaultFade, text: String = "") {
        self.banner = banner
        self.fade = fade
        self.text = text
    }

    init(_ bio: JSONValue?) {
        guard case .object(let o)? = bio else { self.init(); return }
        var banner: URL?
        var fade = Self.defaultFade
        if case .object(let b)? = o["banner"] {
            banner = pictureURL(b["src"]?.string)
            if case .object(let f)? = b["fade"] {
                let on = f["on"]?.bool ?? true
                fade = on ? max(0, min(1, (f["strength"]?.double ?? 74) / 100)) : 0
            }
        }
        self.init(banner: banner, fade: fade, text: Self.text(o["doc"]))
    }

    /// the doc's (tiptap JSON) words: text nodes joined, a new line between blocks
    static func text(_ doc: JSONValue?) -> String {
        func walk(_ v: JSONValue) -> String {
            guard case .object(let n) = v else { return "" }
            if n["type"]?.string == "text" { return n["text"]?.string ?? "" }
            if n["type"]?.string == "hardBreak" { return "\n" }
            guard case .array(let kids)? = n["content"] else { return "" }
            let parts = kids.map(walk)
            let blocks: Set<String> = ["doc", "bulletList", "orderedList", "blockquote", "listItem"]
            return blocks.contains(n["type"]?.string ?? "") ? parts.filter { !$0.isEmpty }.joined(separator: "\n")
                                                            : parts.joined()
        }
        return doc.map(walk)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// a comment on a profile (ProfileComment)
struct ProfileComment: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var author: Person
    var body: String
    var at: Int64
    var edited: Int64?
    var canEdit: Bool
    var canDelete: Bool

    var date: Date { Millis.date(at) }
}

/// GET comments, GET users/:username/comments (CommentsState)
struct CommentsState: Codable, Hashable, Sendable {
    var comments: [ProfileComment]
    var canPost: Bool
    /// yours: who may comment (friends, everyone, nobody)
    var setting: String?
}

struct CommentAnswer: Codable, Hashable, Sendable { var comment: ProfileComment }
private struct CommentBody: Codable { var body: String }

/// one of your lists as the profile shows it (MyListSummary; its items aren't in the answer)
struct ProfileListSummary: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var slug: String
    var name: String
    var description: String
    var count: Int
    var covers: [String?]
    var media: [APIMedia]
    var updated: Int64

    var coverURLs: [URL] { covers.compactMap { pictureURL($0) } }
}

/// YourLists: who may see your lists, and the lists
struct ProfileLists: Codable, Hashable, Sendable {
    var profile: WireVisibility
    var lists: [ProfileListSummary]
}

// MARK: your profile (GET profile; 41, 42)

struct MyProfile: Codable, Equatable, Sendable {
    var profile: Profile
    var friends: FriendCount
    var stats: [MediaStats]
    var characters: [FavouriteCharacter]
    var names: [FavouriteName]
    /// your newest three
    var reviews: UserReviews
    var lists: ProfileLists
    var comments: CommentsState
    var at: Int64

    struct FriendCount: Codable, Hashable, Sendable {
        var count: Int
        var incoming: Int
    }

    var bio: ProfileBio { ProfileBio(profile.bio) }

    /// "Joined Mar 2, 2025"
    var joinedLine: String { "Joined " + Format.longDay(Millis.date(profile.joined)) }

    /// "6 friends", "1 friend"
    var friendsLabel: String { ProfileText.count(friends.count, "friend") }

    func stats(_ media: MediaKind) -> MediaStats { stats.first { $0.kind == media } ?? .empty(media) }
}

// MARK: someone's profile (GET users/:username; 48)

struct UserProfile: Codable, Hashable, Sendable {
    var person: Person
    /// nil unless person.open
    var profile: Info?
    var stats: [MediaStats]
    /// plural media -> their entries (only lists you may see)
    var lists: [String: [ListEntry]]
    var activity: [Activity]
    /// friends you both have
    var mutual: [Person]

    struct Info: Codable, Hashable, Sendable {
        var joined: Int64
        var bio: JSONValue?
        var characters: [FavouriteCharacter]
        var names: [FavouriteName]
    }

    var bio: ProfileBio { ProfileBio(profile?.bio) }

    /// "Joined Mar 12, 2026 · Friends since Oct"
    func joinedLine(now: Date = Clock.now) -> String {
        var parts: [String] = []
        if let j = profile?.joined { parts.append("Joined " + Format.longDay(Millis.date(j))) }
        if person.relation == .friend, let d = person.sinceDate {
            let sameYear = Clock.calendar.component(.year, from: d) == Clock.calendar.component(.year, from: now)
            parts.append("Friends since " + (sameYear ? ProfileText.month(d) : Format.monthYear(d)))
        }
        return parts.joined(separator: " · ")
    }

    func stats(_ media: MediaKind) -> MediaStats { stats.first { $0.kind == media } ?? .empty(media) }

    func entries(_ media: MediaKind) -> [ListEntry] { lists[media.api.rawValue] ?? [] }

    /// how many titles on their list for this media are on yours too
    func inCommon(_ media: MediaKind, mine: [LibraryEntry]) -> Int {
        let ids = Set(mine.filter { $0.media == media }.map(\.id))
        return entries(media).filter { ids.contains(TitleKey(media: media.api, id: $0.id).titleId) }.count
    }

    /// their newest changes from the lists they let you see, newest first
    func lastUpdates(limit: Int = 12, now: Date = Clock.now) -> [ProfileUpdate] {
        var all: [LibraryEntry] = []
        for (key, es) in lists {
            guard let media = APIMedia(rawValue: key) else { continue }
            for e in es { all.append(e.library(media, updatedAt: now.addingTimeInterval(-e.updated * 86400))) }
        }
        return ProfileText.lastUpdates(all, limit: limit)
    }

    /// the media they show first: the one with most entries you may see
    var firstMedia: MediaKind? {
        stats.filter { $0.entries > 0 }.max { $0.entries < $1.entries }?.kind
    }
}

/// a poster in Last updates
struct ProfileUpdate: Hashable, Identifiable, Sendable {
    var title: Title
    /// "Ep 6 of 11", "Completed · ★9"
    var caption: String
    var at: Date

    var id: String { title.id }
}

/// GET users/:username/library/:media
struct UserLibrary: Codable, Hashable, Sendable {
    var person: Person
    var entries: [ListEntry]
}

/// small words shared by the profile pages
enum ProfileText {
    /// "6 friends", "1 friend", "1,204 titles"
    static func count(_ n: Int, _ noun: String, plural: String? = nil) -> String {
        "\(Format.grouped(n)) \(n == 1 ? noun : plural ?? noun + "s")"
    }

    /// "Oct"
    static func month(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = Clock.zone
        f.dateFormat = "MMM"
        return f.string(from: d)
    }

    /// a mean out of 100 as "8.28" (out of 10, two decimals); "–" for 0 (nothing scored)
    static func mean(_ outOf100: Double) -> String {
        outOf100 > 0 ? String(format: "%.2f", outOf100 / 10) : "–"
    }

    /// the caption under a poster in Last updates: "Ep 6 of 11", "Started", "Completed · ★9", "Rewatching · Ep 12"
    static func updateCaption(_ e: LibraryEntry) -> String {
        let m = e.media
        let at: String = {
            guard m != .movie else { return "" }
            var s = "\(m.unitShort) \(Format.grouped(e.progress))"
            if let t = e.title.total { s += " of \(Format.grouped(t))" }
            return s
        }()
        switch e.status {
        case .completed:
            if let s = e.score10 { return "Completed · ★" + s }
            return "Completed"
        case .current:
            if m == .movie { return "Watching" }
            return e.progress == 0 ? "Started" : at
        case .repeating:
            return m == .movie ? e.status.label(m) : "\(e.status.label(m)) · \(m.unitShort) \(Format.grouped(e.progress))"
        case .planned: return e.status.label(m)
        case .hold, .dropped:
            return e.progress > 0 && m != .movie ? "\(e.status.label(m)) · \(at)" : e.status.label(m)
        }
    }

    /// the newest updates of a library, newest first
    static func lastUpdates(_ lib: [LibraryEntry], limit: Int = 12) -> [ProfileUpdate] {
        lib.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit)
            .map { ProfileUpdate(title: $0.title, caption: updateCaption($0), at: $0.updatedAt) }
    }
}

// MARK: statistics (GET stats, GET users/:username/stats; 43)

/// StatsPage: whose, and one KindStats per list you may see.
struct StatsPage: Codable, Hashable, Sendable {
    var person: Person
    var kinds: [KindStats]

    func kind(_ media: MediaKind) -> KindStats? { kinds.first { $0.kind == media } }
}

/// Everything the Statistics page shows for one list (src/stats/types.ts).
struct KindStats: Codable, Hashable, Sendable {
    var media: APIMedia
    var entries: Int
    var counts: [String: Int]
    /// episodes / chapters / pages, first time through
    var progress: Int
    /// the same unit again, from rewatches and rereads
    var again: Int
    var volumes: Int
    /// watching lists: seconds watched first time through
    var seconds: Double
    var againSeconds: Double
    var repeats: Int
    var favourites: Int
    /// out of 100, 0 when nothing is scored
    var meanScore: Double
    var scored: Int
    /// [score out of 100, how many]
    var scores: [[Double]]
    var formats: [Group]
    var genres: [Group]
    /// studios (anime), networks (TV), directors (movies), authors (manga, books)
    var makers: [Group]
    var years: [YearCount]
    var added: [Period]
    var finished: [Period]
    /// titles still being looked up
    var pending: Int

    struct Group: Codable, Hashable, Identifiable, Sendable {
        var name: String
        /// titles in it (planned not counted)
        var count: Int
        /// out of 100, 0 when none scored
        var mean: Double
        var scored: Int
        /// a maker's page id
        var id: String?

        var key: String { id ?? name }
        /// out of 10, nil when none scored
        var mean10: Double? { scored > 0 && mean > 0 ? mean / 10 : nil }
        var meanText: String? { mean10.map { Format.average($0) } }
    }

    struct YearCount: Codable, Hashable, Sendable {
        var year: Int
        var count: Int
    }

    struct Period: Codable, Hashable, Sendable {
        /// "2026-10" or "2026"
        var at: String
        var count: Int
    }

    /// a part of a bar: a format, a release-year bucket
    struct Slice: Hashable, Identifiable, Sendable {
        var label: String
        var count: Int
        /// 0xRRGGBB
        var color: UInt32 = 0x0A84FF

        var id: String { label }
    }

    var kind: MediaKind { media.kind }

    func count(_ s: ListStatus) -> Int { s == .repeating ? 0 : counts[s.rawValue] ?? 0 }

    /// how many titles got each score, 1...10 (index 0 is 1)
    var histogram: [Int] {
        var h = Array(repeating: 0, count: 10)
        for p in scores where p.count == 2 && p[0] > 0 { h[Self.bucket(Int(p[0])) - 1] += Int(p[1]) }
        return h
    }

    /// the middle score, out of 10
    var median: Double? {
        var all: [Double] = []
        for p in scores where p.count == 2 && p[0] > 0 { all += Array(repeating: p[0] / 10, count: max(0, Int(p[1]))) }
        return Self.median(all)
    }

    var medianText: String { median.map { Format.trim($0) } ?? "–" }
    var meanText: String { ProfileText.mean(meanScore) }

    var perfect: Int { scores.filter { $0.count == 2 && $0[0] == 100 }.reduce(0) { $0 + Int($1[1]) } }

    var formatSlices: [Slice] {
        formats.map { Slice(label: $0.name, count: $0.count, color: Self.formatColor($0.name)) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
    }

    var yearSlices: [Slice] { Self.yearBuckets(years) }

    var genreGroups: [Group] { genres.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name } }
    var makerGroups: [Group] { makers.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name } }

    /// what the makers list is called
    var makersLabel: String {
        switch kind {
        case .anime: return "Studios"
        case .tv: return "Networks"
        case .movie: return "Directors"
        case .manga, .book: return "Authors"
        }
    }

    /// "45 days 7 hours" watched (rewatching included), "1,204 chapters" read
    var timeHeadline: (main: String, rest: String) {
        if kind.isReading {
            let n = progress + again
            let unit = kind == .book ? "page" : "chapter"
            return (Format.grouped(n), n == 1 ? unit : unit + "s")
        }
        let minutes = Int((seconds + againSeconds) / 60)
        let d = minutes / 1440, h = (minutes % 1440) / 60
        if d == 0 { return ("\(h) hour\(h == 1 ? "" : "s")", "\(minutes % 60) min") }
        return ("\(d) day\(d == 1 ? "" : "s")", "\(h) hour\(h == 1 ? "" : "s")")
    }

    var timeLabel: String { kind.isReading ? (kind == .book ? "Pages read" : "Chapters read") : "Time watched" }

    /// "2,775 episodes · 194 entries · 109 watched or watching"
    var timeLine: String {
        let done = entries - count(.planned)
        let verb = kind.isReading ? "read or reading" : "watched or watching"
        var parts: [String] = []
        if kind != .movie && !kind.isReading { parts.append(kind.units(progress)) }
        if kind == .movie { parts.append(ProfileText.count(count(.completed), "film")) }
        parts.append(ProfileText.count(entries, "entry", plural: "entries"))
        parts.append("\(Format.grouped(done)) \(verb)")
        return parts.joined(separator: " · ")
    }

    /// what the share button sends: "Mika's anime on GupTrack: 45 days watched, mean score 8.28, 57 entries"
    func shareText(name: String) -> String {
        let t = timeHeadline
        let amount = kind.isReading ? "\(t.main) \(t.rest) read" : "\(t.main) \(t.rest) watched"
        return "\(name)’s \(kind.plural.lowercased()) on GupTrack: \(amount), mean score \(meanText), "
            + ProfileText.count(entries, "entry", plural: "entries")
    }

    /// a 0-100 score's bar on the 1-10 histogram (85 -> 9, 80 -> 8, 5 -> 1)
    static func bucket(_ score: Int) -> Int { max(1, min(10, Int((Double(score) / 10).rounded()))) }

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    static func formatColor(_ f: String) -> UInt32 {
        switch f {
        case "TV", "Manga", "Book", "Movie": return 0x0A84FF
        case "Film", "Light Novel", "Novel": return 0xBF5AF2
        case "ONA", "One Shot": return 0x30D158
        case "OVA", "TV Short": return 0xFF9F0A
        case "Special": return 0x64D2FF
        default: return 0x8E8E93
        }
    }

    /// release years in 5-year steps ("’95" … "’25"), every step from the first to the last; 10-year steps when
    /// that would be more than 8 bars
    static func yearBuckets(_ years: [YearCount]) -> [Slice] {
        let ys = years.filter { $0.count > 0 }
        guard let lo = ys.map(\.year).min(), let hi = ys.map(\.year).max() else { return [] }
        var step = 5
        if hi / 5 - lo / 5 + 1 > 8 { step = 10 }
        let first = lo / step * step, last = hi / step * step
        var out: [Slice] = []
        var y = first
        while y <= last {
            let n = ys.filter { $0.year >= y && $0.year < y + step }.reduce(0) { $0 + $1.count }
            out.append(Slice(label: "’" + String(format: "%02d", y % 100), count: n))
            y += step
        }
        return out
    }
}

// MARK: compare (GET users/:username/compare; 49)

/// One side of a compared title.
struct CompareSide: Codable, Hashable, Sendable {
    var status: EntryStatus
    var score: Int?
    var progress: Int
}

struct ComparedTitle: Codable, Hashable, Identifiable, Sendable {
    var media: APIMedia
    var id: String
    var title: String
    var cover: String
    var format: String
    var mine: CompareSide?
    var theirs: CompareSide?

    var titleId: String { TitleKey(media: media, id: id).titleId }
    var card: Title {
        Title(id: titleId, media: media.kind, name: title, cover: pictureURL(cover), format: format.isEmpty ? nil : format)
    }

    var myScore: Int? { mine?.score.flatMap { $0 > 0 ? $0 : nil } }
    var theirScore: Int? { theirs?.score.flatMap { $0 > 0 ? $0 : nil } }
    var bothScored: Bool { myScore != nil && theirScore != nil }

    /// out of 100
    var apart: Int { abs((myScore ?? 0) - (theirScore ?? 0)) }

    /// "4 apart", "1.5 apart", "Same score"
    var caption: String { apart == 0 ? "Same score" : Format.score10(apart) + " apart" }
}

/// Comparison: both libraries side by side (only lists you both may see).
struct Comparison: Codable, Hashable, Sendable {
    var person: Person
    var shared: [ComparedTitle]
    var theirsOnly: [ComparedTitle]
    /// plural media -> counts
    var counts: [String: Counts]

    struct Counts: Codable, Hashable, Sendable {
        var mine: Int
        var theirs: Int
        var shared: Int
    }

    /// the media you can compare, the one with most in common first
    var media: [MediaKind] {
        MediaKind.allCases.filter { m in counts[m.api.rawValue] != nil || shared.contains { $0.media == m.api } }
    }

    func on(_ media: MediaKind) -> CompareSet {
        CompareSet(media: media, rows: shared.filter { $0.media == media.api },
                   inCommon: counts[media.api.rawValue]?.shared)
    }
}

/// You and someone else for one media.
struct CompareSet: Hashable, Sendable {
    var media: MediaKind
    var rows: [ComparedTitle]
    var inCommon: Int

    init(media: MediaKind, rows: [ComparedTitle], inCommon: Int? = nil) {
        self.media = media
        self.rows = rows
        self.inCommon = inCommon ?? rows.count
    }

    var scoredByBoth: Int { rows.filter(\.bothScored).count }

    /// how far apart your scores are on average, out of 10; nil without scores in common
    var apartAverage: Double? {
        let both = rows.filter(\.bothScored)
        guard !both.isEmpty else { return nil }
        return Double(both.reduce(0) { $0 + $1.apart }) / Double(both.count) / 10
    }

    var apartText: String { apartAverage.map { Format.trim(($0 * 10).rounded() / 10) } ?? "–" }

    /// scored by both, furthest apart first
    var mostDifferent: [ComparedTitle] {
        rows.filter(\.bothScored).sorted { $0.apart != $1.apart ? $0.apart > $1.apart : $0.title < $1.title }
    }

    /// scored by both, the ones you both rate highest first
    var bestTogether: [ComparedTitle] {
        rows.filter(\.bothScored).sorted {
            let a = ($0.myScore ?? 0) + ($0.theirScore ?? 0), b = ($1.myScore ?? 0) + ($1.theirScore ?? 0)
            if a != b { return a > b }
            return $0.apart != $1.apart ? $0.apart < $1.apart : $0.title < $1.title
        }
    }

    /// "Anime · both lists"
    var subtitle: String { media.plural + " · both lists" }
}

// MARK: the calls

extension APIClient {
    /// GET profile: your profile screen
    func myProfile() async throws -> MyProfile { try await get("profile") }

    /// GET users/:username
    func userProfile(_ username: String) async throws -> UserProfile { try await get("users/" + username) }

    /// GET users/:username/library/:media
    func userLibrary(_ username: String, _ media: MediaKind) async throws -> UserLibrary {
        try await get("users/\(username)/library/\(media.api.rawValue)")
    }

    /// GET users/:username/activity
    func userActivity(_ username: String, before: Int64? = nil) async throws -> [Activity] {
        let a: UserActivityAnswer = try await get("users/\(username)/activity",
                                                  query: before.map { [URLQueryItem(name: "before", value: String($0))] } ?? [])
        return a.activity
    }

    /// GET users/:username/compare
    func compare(_ username: String) async throws -> Comparison { try await get("users/\(username)/compare") }

    /// GET stats (yours) or users/:username/stats
    func stats(of username: String? = nil) async throws -> StatsPage {
        try await get(username.map { "users/\($0)/stats" } ?? "stats")
    }

    /// GET comments (yours) or users/:username/comments
    func comments(of username: String? = nil) async throws -> CommentsState {
        try await get(username.map { "users/\($0)/comments" } ?? "comments")
    }

    func postComment(on username: String, _ body: String) async throws -> ProfileComment {
        let a: CommentAnswer = try await send("POST", "users/\(username)/comments", CommentBody(body: body))
        return a.comment
    }

    func editComment(_ id: Int, _ body: String) async throws -> ProfileComment {
        let a: CommentAnswer = try await send("PATCH", "comments/\(id)", CommentBody(body: body))
        return a.comment
    }

    func deleteComment(_ id: Int) async throws -> OKReply { try await send("DELETE", "comments/\(id)") }
}
