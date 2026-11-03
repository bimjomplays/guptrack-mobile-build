import Foundation

// Profiles and statistics (41-43b, 48, 49): your own profile page, someone else's, the Statistics page and
// Compare. Your own numbers are worked out here from the offline library (`LibraryStats`); someone else's come from
// the server in the same `LibraryStats.Summary` shape.

// MARK: your profile (GET profile)

/// GET profile: what the library can't know about your profile (bio, banner, favourites, reviews, comments).
struct ProfilePage: Codable, Hashable, Sendable {
    var user: UserRef
    var bio: String
    var banner: URL?
    /// the banner fade's strength from Settings › Profile, 0...1 (nil: the default 0.7)
    var bannerFade: Double?
    var joined: Date
    var friends: Int
    var favourites: [Title]
    var reviews: [Review]
    var reviewCount: Int
    var comments: [Comment]
    var commentCount: Int

    /// one of your reviews (42)
    struct Review: Codable, Hashable, Identifiable, Sendable {
        var id: String
        var title: Title
        /// out of 100
        var score: Int?
        var headline: String
        var body: String
        var likes: Int
        var at: Date
    }

    /// a comment someone left on your profile (42)
    struct Comment: Codable, Hashable, Identifiable, Sendable {
        var id: String
        var user: UserRef
        var text: String
        var at: Date
    }

    /// "Joined Mar 2, 2025"
    var joinedLine: String { "Joined " + Format.longDay(joined) }

    /// "6 friends", "1 friend"
    var friendsLabel: String { ProfileText.count(friends, "friend") }

    var fade: Double { ProfileText.fade(bannerFade) }
}

// MARK: someone else's profile (GET users/<username>)

struct UserPage: Codable, Hashable, Sendable {
    var user: UserRef
    var bio: String
    var banner: URL?
    var bannerFade: Double?
    var joined: Date
    /// when you became friends; nil when you aren't
    var friendsSince: Date?
    /// "friends", "requested" (you asked), "incoming" (they asked), "none"
    var friendship: String
    /// media raw value -> how many titles you both have on your lists
    var inCommon: [String: Int]
    /// one per media that has entries
    var summaries: [LibraryStats.Summary]
    var lastUpdates: [Update]

    struct Update: Codable, Hashable, Identifiable, Sendable {
        var title: Title
        /// "Ep 6 of 11", "Completed · ★9"
        var caption: String
        var at: Date

        var id: String { title.id }
    }

    /// "Joined Mar 12, 2026 · Friends since Oct"
    var joinedLine: String {
        var s = "Joined " + Format.longDay(joined)
        if let friendsSince {
            let sameYear = Clock.calendar.component(.year, from: friendsSince) == Clock.calendar.component(.year, from: Clock.now)
            s += " · Friends since " + (sameYear ? ProfileText.month(friendsSince) : Format.monthYear(friendsSince))
        }
        return s
    }

    var isFriend: Bool { friendship == "friends" }

    /// the Friends button's words
    var friendshipLabel: String {
        switch friendship {
        case "friends": return "Friends"
        case "requested": return "Requested"
        case "incoming": return "Accept"
        default: return "Add friend"
        }
    }

    func inCommon(_ media: MediaKind) -> Int { inCommon[media.rawValue] ?? 0 }

    func summary(_ media: MediaKind) -> LibraryStats.Summary {
        summaries.first { $0.media == media } ?? LibraryStats.Summary(media: media)
    }

    var fade: Double { ProfileText.fade(bannerFade) }
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

    static func fade(_ v: Double?) -> Double { max(0, min(1, v ?? 0.7)) }

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

    /// your last updates from the library, newest first
    static func lastUpdates(_ lib: [LibraryEntry], limit: Int = 12) -> [UserPage.Update] {
        lib.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit)
            .map { UserPage.Update(title: $0.title, caption: updateCaption($0), at: $0.updatedAt) }
    }
}

// MARK: statistics from the library

/// Your statistics for one media, worked out from the offline library (the profile's columns, the Statistics page).
struct LibraryStats: Hashable, Sendable {
    let media: MediaKind
    let summary: Summary
    /// how many titles you gave each score, 1...10 (index 0 is 1)
    let histogram: [Int]
    let median: Double?
    let perfect: Int
    let formats: [Slice]
    let years: [Slice]
    let genres: [Group]
    let studios: [Group]

    /// The numbers the profile shows for one media (also what the server sends for someone else).
    struct Summary: Codable, Hashable, Sendable {
        var media: MediaKind
        var entries: Int = 0
        /// status raw value -> how many (String keys so the JSON is an object)
        var counts: [String: Int] = [:]
        var scored: Int = 0
        /// out of 10
        var mean: Double?
        /// how many times you rewatched or reread, all titles together
        var rewatched: Int = 0
        /// episodes, chapters, pages or films
        var units: Int = 0
        /// time spent (watching media)
        var minutes: Int = 0
        /// manga: completed titles; books: books read
        var completed: Int = 0

        func count(_ s: ListStatus) -> Int {
            let n = counts[s.rawValue] ?? 0
            return s == .current ? n + (counts[ListStatus.repeating.rawValue] ?? 0) : n
        }

        /// the status bar's counts (rewatching counts as watching)
        var statusCounts: [ListStatus: Int] {
            Dictionary(uniqueKeysWithValues: ListStatus.ordered.map { ($0, count($0)) })
        }

        /// "4%" of the entries
        func percent(_ s: ListStatus) -> String {
            guard entries > 0 else { return "0%" }
            return "\(Int((Double(count(s)) / Double(entries) * 100).rounded()))%"
        }

        /// "8.28" (two decimals, as the website), "–" when nothing is scored
        var meanText: String { mean.map { String(format: "%.2f", $0) } ?? "–" }

        /// the four columns under the media switch (41, 48)
        var columns: [Column] {
            let mean = Column(value: meanText, label: "Mean score")
            switch media {
            case .anime, .tv:
                return [Column(value: Format.days(minutes: minutes), label: "Days"), mean,
                        Column(value: Format.grouped(rewatched), label: "Rewatched"),
                        Column(value: Format.grouped(units), label: "Episodes")]
            case .movie:
                return [Column(value: Format.days(minutes: minutes), label: "Days"), mean,
                        Column(value: Format.grouped(rewatched), label: "Rewatched"),
                        Column(value: Format.grouped(units), label: "Films")]
            case .manga:
                return [Column(value: Format.grouped(units), label: "Chapters"), mean,
                        Column(value: Format.grouped(rewatched), label: "Reread"),
                        Column(value: Format.grouped(completed), label: "Completed")]
            case .book:
                return [Column(value: Format.grouped(units), label: "Pages"), mean,
                        Column(value: Format.grouped(rewatched), label: "Reread"),
                        Column(value: Format.grouped(completed), label: "Books read")]
            }
        }

        /// "45 days 7 hours" (watching), "1,204 chapters" (reading)
        var timeHeadline: (main: String, rest: String) {
            if media.isReading {
                let unit = media == .book ? "page" : "chapter"
                return (Format.grouped(units), units == 1 ? unit : unit + "s")
            }
            let d = minutes / 1440, h = (minutes % 1440) / 60
            if d == 0 { return ("\(h) hour\(h == 1 ? "" : "s")", "\((minutes % 60)) min") }
            return ("\(d) day\(d == 1 ? "" : "s")", "\(h) hour\(h == 1 ? "" : "s")")
        }

        /// "Time watched" / "Read"
        var timeLabel: String { media.isReading ? (media == .book ? "Pages read" : "Chapters read") : "Time watched" }

        /// "2,775 episodes · 194 entries · 109 watched or watching"
        var timeLine: String {
            let done = entries - count(.planned)
            let verb = media.isReading ? "read or reading" : "watched or watching"
            var parts: [String] = []
            if !media.isReading {
                parts.append(media == .movie ? ProfileText.count(units, "film") : media.units(units))
            }
            parts.append(ProfileText.count(entries, "entry", plural: "entries"))
            parts.append("\(Format.grouped(done)) \(verb)")
            return parts.joined(separator: " · ")
        }
    }

    struct Column: Hashable, Sendable {
        var value: String
        var label: String
    }

    /// a part of a bar: a format, a release-year bucket
    struct Slice: Hashable, Identifiable, Sendable {
        var label: String
        var count: Int
        /// 0xRRGGBB (formats)
        var color: UInt32 = 0x0A84FF

        var id: String { label }
    }

    /// a genre or studio with how many titles and your mean score
    struct Group: Hashable, Identifiable, Sendable {
        var name: String
        var count: Int
        /// out of 10
        var mean: Double?

        var id: String { name }
        var meanText: String? { mean.map { Format.average($0) } }
    }

    init(_ library: [LibraryEntry], media: MediaKind) {
        self.media = media
        let es = library.filter { $0.media == media }
        var s = Summary(media: media)
        s.entries = es.count
        for e in es { s.counts[e.status.rawValue, default: 0] += 1 }
        let scores = es.compactMap(\.score).filter { $0 > 0 }
        s.scored = scores.count
        s.mean = scores.isEmpty ? nil : Double(scores.reduce(0, +)) / Double(scores.count) / 10
        s.rewatched = es.reduce(0) { $0 + $1.repeats }
        s.completed = es.filter { $0.status == .completed }.count
        for e in es {
            let done = Self.unitsDone(e)
            s.units += done
            if !media.isReading { s.minutes += done * Self.minutes(e.title) }
        }
        summary = s

        var hist = Array(repeating: 0, count: 10)
        for v in scores { hist[Self.bucket(v) - 1] += 1 }
        histogram = hist
        perfect = scores.filter { $0 == 100 }.count
        median = Self.median(scores.map { Double($0) / 10 })

        var fmt: [String: Int] = [:]
        for e in es { fmt[Self.formatName(e.title), default: 0] += 1 }
        formats = fmt.map { Slice(label: $0.key, count: $0.value, color: Self.formatColor($0.key)) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label < $1.label }
        years = Self.yearBuckets(es.compactMap(\.title.year))
        genres = Self.groups(es) { $0.title.genres ?? [] }
        studios = Self.groups(es) { e in e.title.studio.map { [$0] } ?? [] }
    }

    /// what the second list on the Statistics page counts: studios, networks or authors
    var peopleLabel: String { media == .book ? "Authors" : media == .tv ? "Networks" : "Studios" }

    /// episodes, chapters or pages done (rewatches count again); films count once each
    static func unitsDone(_ e: LibraryEntry) -> Int {
        if e.media == .movie {
            let seen = e.status == .completed || e.progress > 0 ? 1 : 0
            return seen + (seen > 0 ? e.repeats : 0)
        }
        if e.status == .planned { return 0 }
        return e.progress + e.repeats * (e.title.total ?? e.progress)
    }

    /// minutes per episode (or per film) from "24 min", "2h 47m", "1h"; a usual length when unknown
    static func minutes(_ t: Title) -> Int {
        if let r = t.runtime, let m = parseRuntime(r) { return m }
        switch t.media {
        case .anime: return t.format == "Movie" ? 100 : 24
        case .tv: return 45
        case .movie: return 120
        case .manga, .book: return 0
        }
    }

    static func parseRuntime(_ s: String) -> Int? {
        var total = 0, num = "", any = false
        for ch in s.lowercased() + " " {
            if ch.isNumber { num.append(ch); continue }
            if let n = Int(num) {
                total += ch == "h" ? n * 60 : n
                any = true
            }
            num = ""
        }
        return any && total > 0 ? total : nil
    }

    /// a 0-100 score's bar on the 1-10 histogram (85 -> 9, 80 -> 8, 5 -> 1)
    static func bucket(_ score: Int) -> Int { max(1, min(10, Int((Double(score) / 10).rounded()))) }

    static func median(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    var medianText: String { median.map { Format.trim($0) } ?? "–" }

    /// an anime film is a "Film" (anime films stay under Anime); no format is "Other"
    static func formatName(_ t: Title) -> String {
        guard let f = t.format, !f.isEmpty else { return "Other" }
        if f == "Movie" { return t.media == .anime ? "Film" : "Movie" }
        return f
    }

    static func formatColor(_ f: String) -> UInt32 {
        switch f {
        case "TV", "Manga", "Book", "Movie": return 0x0A84FF
        case "Film", "Light Novel": return 0xBF5AF2
        case "ONA", "One Shot": return 0x30D158
        case "OVA", "TV Short": return 0xFF9F0A
        case "Special": return 0x64D2FF
        default: return 0x8E8E93
        }
    }

    /// release years in 5-year steps ("’95" … "’25"), every step from the first to the last; 10-year steps when
    /// that would be more than 8 bars
    static func yearBuckets(_ years: [Int]) -> [Slice] {
        guard let lo = years.min(), let hi = years.max() else { return [] }
        var step = 5
        if hi / 5 - lo / 5 + 1 > 8 { step = 10 }
        let first = lo / step * step, last = hi / step * step
        var out: [Slice] = []
        var y = first
        while y <= last {
            let n = years.filter { $0 >= y && $0 < y + step }.count
            out.append(Slice(label: "’" + String(format: "%02d", y % 100), count: n, color: 0x0A84FF))
            y += step
        }
        return out
    }

    /// genres or studios by how many titles (planned ones left out), with your mean score
    static func groups(_ es: [LibraryEntry], _ keys: (LibraryEntry) -> [String]) -> [Group] {
        var count: [String: Int] = [:], sum: [String: Int] = [:], scored: [String: Int] = [:]
        for e in es where e.status != .planned {
            for k in Set(keys(e)) {
                count[k, default: 0] += 1
                if let s = e.score, s > 0 { sum[k, default: 0] += s; scored[k, default: 0] += 1 }
            }
        }
        return count.map { k, n in
            Group(name: k, count: n, mean: scored[k].map { Double(sum[k] ?? 0) / Double($0) / 10 })
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    /// what the share button sends: "Mika's anime on GupTrack: 2.1 days, mean score 8.28, 57 entries"
    func shareText(name: String) -> String {
        let s = summary
        let first = s.columns[0]
        return "\(name)’s \(media.plural.lowercased()) on GupTrack: \(first.value) \(first.label.lowercased()), "
            + "mean score \(s.meanText), \(ProfileText.count(s.entries, "entry", plural: "entries"))"
    }
}

// MARK: compare (GET compare/<username>?media=anime)

/// You and someone else for one media: the titles on both your lists with both scores.
struct CompareResult: Codable, Hashable, Sendable {
    var user: UserRef
    var media: MediaKind
    var rows: [Row]

    struct Row: Codable, Hashable, Identifiable, Sendable {
        var title: Title
        /// out of 100
        var mine: Int?
        var theirs: Int?

        var id: String { title.id }

        var bothScored: Bool { (mine ?? 0) > 0 && (theirs ?? 0) > 0 }

        /// out of 100
        var apart: Int { abs((mine ?? 0) - (theirs ?? 0)) }

        /// "4 apart", "1.5 apart", "Same score"
        var caption: String { apart == 0 ? "Same score" : Format.score10(apart) + " apart" }
    }

    var inCommon: Int { rows.count }

    var scoredByBoth: Int { rows.filter(\.bothScored).count }

    /// how far apart your scores are on average, out of 10 ("0.9"); nil without scores in common
    var apartAverage: Double? {
        let both = rows.filter(\.bothScored)
        guard !both.isEmpty else { return nil }
        return Double(both.reduce(0) { $0 + $1.apart }) / Double(both.count) / 10
    }

    var apartText: String { apartAverage.map { Format.trim($0) } ?? "–" }

    /// scored by both, furthest apart first
    var mostDifferent: [Row] {
        rows.filter(\.bothScored).sorted {
            $0.apart != $1.apart ? $0.apart > $1.apart : $0.title.name < $1.title.name
        }
    }

    /// scored by both, the ones you both rate highest first
    var bestTogether: [Row] {
        rows.filter(\.bothScored).sorted {
            let a = ($0.mine ?? 0) + ($0.theirs ?? 0), b = ($1.mine ?? 0) + ($1.theirs ?? 0)
            if a != b { return a > b }
            return $0.apart != $1.apart ? $0.apart < $1.apart : $0.title.name < $1.title.name
        }
    }

    /// "Anime · both lists"
    var subtitle: String { media.plural + " · both lists" }
}

// MARK: the calls

extension APIClient {
    /// GET profile: your own profile's bio, banner, favourites, reviews and comments
    func profilePage() async throws -> ProfilePage { try await get("profile") }

    /// GET users/<username>: someone's profile with their numbers per media
    func userPage(_ username: String) async throws -> UserPage { try await get("users/" + username) }

    /// GET compare/<username>?media=anime
    func compare(_ username: String, media: MediaKind) async throws -> CompareResult {
        try await get("compare/" + username, query: [URLQueryItem(name: "media", value: media.rawValue)])
    }
}
