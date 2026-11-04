import Foundation

// Social (44-54): friends and their activity, one activity with its replies, finding someone, a title's reviews and
// one review, messages, a conversation and a message request. The answers are the website's own types
// (docs/app-api.md §10, §11; src/social, src/messages, src/library/types.ts); the logic the screens show (the feed's
// sentences, times, chat bubbles, filters) lives here so it's tested on Linux, and the views only draw it.
//
// Pictures stay as the answer gives them: an address starting with "/" is GupTrack's own and the image loader
// fetches it on the signed-in server. A cover of "" means none.

/// a cover address from an answer ("" = none) as a URL, not resolved
func pictureURL(_ address: String?) -> URL? {
    guard let a = address, !a.isEmpty else { return nil }
    return URL(string: a)
}

// MARK: people (§10)

/// You and someone else.
enum Relation: String, Codable, Hashable, Sendable {
    case me = "self", friend, incoming, outgoing, none
}

/// Person (src/social/types.ts): the way people appear everywhere.
struct Person: Codable, Hashable, Identifiable, Sendable {
    var username: String
    /// "" when not set or not yours to see
    var name: String
    var avatar: URL?
    var relation: Relation
    /// you may see their profile
    var open: Bool
    /// the lists you may see
    var lists: [APIMedia]
    /// friends since, or when the request was sent (ms)
    var since: Int64?

    var id: String { username }

    /// what the screens draw (the name falls back to the username)
    var user: UserRef { UserRef(username: username, name: name.isEmpty ? username : name, avatar: avatar) }

    var sinceDate: Date? { since.map(Millis.date) }

    var isFriend: Bool { relation == .friend }

    init(username: String, name: String = "", avatar: URL? = nil, relation: Relation = .none, open: Bool = true,
         lists: [APIMedia] = APIMedia.allCases, since: Int64? = nil) {
        self.username = username
        self.name = name
        self.avatar = avatar
        self.relation = relation
        self.open = open
        self.lists = lists
        self.since = since
    }
}

/// GET friends: FriendsState.
struct FriendsState: Codable, Equatable, Sendable {
    var friends: [Person]
    /// they asked you
    var incoming: [Person]
    /// you asked
    var outgoing: [Person]
    /// usernames you blocked
    var blocked: [String]
    /// your profile's visibility
    var visibility: WireVisibility
    /// each list's visibility (plural media keys)
    var lists: [String: WireVisibility]

    /// accepting a request makes them a friend (at the top of Friends), friends since now
    func accepting(_ username: String, now: Date = Clock.now) -> FriendsState {
        var s = self
        guard var p = incoming.first(where: { $0.username == username }) else { return s }
        s.incoming.removeAll { $0.username == username }
        p.relation = .friend
        p.since = Millis.of(now)
        s.friends.insert(p, at: 0)
        return s
    }

    func declining(_ username: String) -> FriendsState {
        var s = self
        s.incoming.removeAll { $0.username == username }
        return s
    }

    func cancelling(_ username: String) -> FriendsState {
        var s = self
        s.outgoing.removeAll { $0.username == username }
        return s
    }

    func unblocking(_ username: String) -> FriendsState {
        var s = self
        s.blocked.removeAll { $0 == username }
        return s
    }

    /// "Friends since Oct 2026" (the friends list), "Asked 12m ago" (a request), "Sent Oct 30" (yours)
    static func line(_ p: Person, now: Date = Clock.now) -> String {
        guard let d = p.sinceDate else { return p.relation == .friend ? "Friends" : "" }
        switch p.relation {
        case .friend: return "Friends since " + Format.monthYear(d)
        case .incoming: return "Asked " + SocialText.feedTime(d, now: now)
        case .outgoing: return "Sent " + Format.shortDay(d)
        default: return ""
        }
    }
}

/// Finding someone by their exact username (Add friend).
enum FriendSearch {
    /// what's searched: the whole username, trimmed, lowercased, without a leading @
    static func query(_ typed: String) -> String {
        var q = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.hasPrefix("@") { q.removeFirst() }
        return q
    }

    /// "5 lists open to you", "Profile hidden"
    static func line(_ p: Person) -> String {
        guard p.open else { return "Profile hidden" }
        return ProfileText.count(p.lists.count, "list") + " open to you"
    }
}

/// POST users/:username/friend, …/friend/answer
struct RelationAnswer: Codable, Equatable, Sendable {
    var relation: Relation
}

// MARK: likes and replies (§10.6)

/// Reactions (src/social/reactions.ts): an activity line's or a review's likes and reply count.
struct Reactions: Codable, Hashable, Sendable {
    var target: Target
    var likes: Int
    var liked: Bool
    /// newest first, at most 30
    var likers: [Person]
    var replies: Int
    /// someone else's: you may like it
    var canLike: Bool

    struct Target: Codable, Hashable, Sendable {
        /// "activity" or "review"
        var on: String
        var id: Int
    }

    /// a like from you (or taking it back), with you first among the likers
    func toggledLike(me: Person? = nil) -> Reactions {
        var r = self
        r.liked.toggle()
        r.likes = max(0, likes + (r.liked ? 1 : -1))
        if let me {
            r.likers.removeAll { $0.username == me.username }
            if r.liked { r.likers.insert(me, at: 0) }
        }
        return r
    }

    /// "Liked by tobiwan and 3 others": the bold name and the rest; nil when nobody liked it
    var likedBy: (name: String, rest: String)? {
        guard let first = likers.first, likes > 0 else { return nil }
        let others = likes - 1
        if others <= 0 { return (first.username, "") }
        return (first.username, "and \(others) other\(others == 1 ? "" : "s")")
    }
}

/// a reply on an activity line or a review
struct Reply: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    /// the top-level reply this answers; nil for a top-level one
    var parent: Int?
    var author: Person
    var body: String
    var at: Int64
    var edited: Int64?
    var canEdit: Bool
    var canDelete: Bool

    var date: Date { Millis.date(at) }
}

/// GET replies/:on/:id
struct Replies: Codable, Hashable, Sendable {
    var replies: [Reply]
    var reactions: Reactions
}

struct ReactionsAnswer: Codable, Hashable, Sendable { var reactions: Reactions }
struct ReplyAnswer: Codable, Hashable, Sendable { var reply: Reply }
private struct LikeBody: Codable { var like: Bool }
private struct ReplyBody: Codable {
    var body: String
    var parent: Int?
}
private struct BodyOnly: Codable { var body: String }
private struct AcceptBody: Codable { var accept: Bool }

// MARK: activity (§10.1; 44, 45)

/// Activity (src/library/types.ts): one change to a list.
struct Activity: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var at: Int64
    var media: APIMedia
    /// the entry's id; nil for an import
    var entry: String?
    var title: String
    var cover: String
    /// added, status, progress, position, score, repeats, removed, import, review
    var type: String
    /// status: old and new status; progress: old and new count; score: old and new score; import: counts
    var before: JSONValue?
    var after: JSONValue?
    var social: Reactions?

    var date: Date { Millis.date(at) }
    var titleId: String? { entry.map { TitleKey(media: media, id: $0).titleId } }

    /// the title it's about, as the screens draw it
    var titleCard: Title? {
        guard let titleId else { return nil }
        return Title(id: titleId, media: media.kind, name: title, cover: pictureURL(cover))
    }

    init(id: Int, at: Int64, media: APIMedia, entry: String?, title: String, cover: String = "", type: String,
         before: JSONValue? = nil, after: JSONValue? = nil, social: Reactions? = nil) {
        self.id = id
        self.at = at
        self.media = media
        self.entry = entry
        self.title = title
        self.cover = cover
        self.type = type
        self.before = before
        self.after = after
        self.social = social
    }
}

/// FriendActivity: an Activity with whose it is (one flat object in the answer).
struct FriendActivity: Codable, Hashable, Identifiable, Sendable {
    var activity: Activity
    var user: Person

    var id: Int { activity.id }

    init(_ activity: Activity, user: Person) {
        self.activity = activity
        self.user = user
    }

    private enum Keys: String, CodingKey { case user }

    init(from decoder: Decoder) throws {
        activity = try Activity(from: decoder)
        user = try decoder.container(keyedBy: Keys.self).decode(Person.self, forKey: .user)
    }

    func encode(to encoder: Encoder) throws {
        try activity.encode(to: encoder)
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(user, forKey: .user)
    }
}

/// GET feed, GET users/:username/activity
struct FeedAnswer: Codable, Hashable, Sendable { var activity: [FriendActivity] }
struct UserActivityAnswer: Codable, Hashable, Sendable { var activity: [Activity] }
/// GET activity/:id
struct ActivityItem: Codable, Hashable, Sendable { var item: FriendActivity }

/// One line of the feed as drawn: "kenji completed Frieren", "lena added 4 shows to Plan to Watch",
/// "noor.reads read chs 41–46 of Vagabond", with the score and the time underneath.
struct FeedLine: Identifiable, Hashable, Sendable {
    /// the (first) activity's id: its thread
    var id: Int
    var user: Person
    /// the words after the name, before the bold object ("completed", "read chs 41–46 of", "added")
    var verb: String
    /// the bold part: a title's name, a file's, or "4 shows"
    var object: String
    /// after the object: " to Plan to Watch", " on hold", " from their list"
    var tail: String
    var media: APIMedia
    /// the title it's about (nil for imports and groups)
    var title: Title?
    /// several titles at once (a poster strip under the sentence)
    var titles: [Title]
    /// out of 100: the score given (on its own, or folded onto Completed)
    var score: Int?
    var at: Date
    /// its likes and replies (nil for a group of several)
    var social: Reactions?

    /// "Anime", the first part of the meta line
    var mediaWord: String { media.kind.singular }
    var score10: String? { score.map { Format.score10($0) } }

    /// a like from you
    func toggledLike(me: Person? = nil) -> FeedLine {
        var l = self
        l.social = social?.toggledLike(me: me)
        return l
    }
}

enum Feed {
    private static func watches(_ m: APIMedia) -> Bool { m == .anime || m == .tv || m == .movies }

    private static func units(_ m: APIMedia) -> (String, String) {
        switch m {
        case .anime, .tv: return ("ep", "eps")
        case .manga: return ("ch", "chs")
        case .books: return ("page", "pages")
        case .movies: return ("", "")
        }
    }

    /// "Watching", "Plan to Read" (the website's statusLabel)
    static func statusLabel(_ m: APIMedia, _ s: String) -> String? {
        let reading = !watches(m)
        switch s {
        case "current": return reading ? "Reading" : "Watching"
        case "completed": return "Completed"
        case "hold": return "On-Hold"
        case "dropped": return "Dropped"
        case "planned": return reading ? "Plan to Read" : "Plan to Watch"
        default: return nil
        }
    }

    /// The words for one change, as the website's lineOf (src/components/home/activity.tsx), lower-cased after a
    /// name; nil for a change that isn't a line (position, a status it doesn't know, a progress that didn't move).
    static func words(_ a: Activity) -> (verb: String, object: String, tail: String, score: Int?)? {
        let m = a.media
        let name = a.title
        switch a.type {
        case "added":
            return ("added", name, a.after?.string.flatMap { statusLabel(m, $0) }.map { " to " + $0 } ?? "", nil)
        case "status":
            switch a.after?.string {
            case "current": return (a.before?.string == "planned" ? "started" : "resumed", name, "", nil)
            case "completed": return ("completed", name, "", nil)
            case "hold": return ("put", name, " on hold", nil)
            case "dropped": return ("dropped", name, "", nil)
            case "planned": return ("moved", name, " to " + (statusLabel(m, "planned") ?? ""), nil)
            case "rewatching": return (watches(m) ? "started rewatching" : "started rereading", name, "", nil)
            case "rewatch-ended": return (watches(m) ? "stopped rewatching" : "stopped rereading", name, "", nil)
            default: return nil
            }
        case "progress":
            guard let from = a.before?.double, let to = a.after?.double, from != to else { return nil }
            let (one, many) = units(m)
            let f = Int(from), t = Int(to)
            if m == .movies { return (to < from ? "went back to" : "watched", name, "", nil) }
            if to < from { return ("went back to \(one) \(Format.grouped(t)) of", name, "", nil) }
            let detail = t - f == 1 ? "\(one) \(Format.grouped(t))" : "\(many) \(Format.grouped(f + 1))–\(Format.grouped(t))"
            return ((watches(m) ? "watched " : "read ") + detail + " of", name, "", nil)
        case "score":
            if let s = a.after?.int { return ("rated", name, "", s) }
            return ("took the score off", name, "", nil)
        case "repeats":
            guard let to = a.after?.double, to > (a.before?.double ?? 0) else { return nil }
            return (watches(m) ? "rewatched" : "reread", name, "", nil)
        case "removed":
            return ("removed", name, " from their list", nil)
        case "import":
            var n = 0
            if case .object(let o) = a.after { n = (o["added"]?.int ?? 0) + (o["updated"]?.int ?? 0) }
            return ("imported \(Format.grouped(n)) \(n == 1 ? "title" : "titles") from", name.isEmpty ? "a file" : name, "", nil)
        case "review":
            return ("reviewed", name, "", nil)
        default:
            return nil
        }
    }

    private static func near(_ a: FriendActivity, _ b: FriendActivity, _ ms: Int64) -> Bool {
        a.user.username == b.user.username && a.activity.media == b.activity.media && a.activity.entry == b.activity.entry
            && abs(a.activity.at - b.activity.at) <= ms
    }

    /// The feed's lines, newest first, as the website folds them: the count Completed fills in isn't a line, a score
    /// given within 10 minutes of finishing goes on the Completed line. Then several titles one person added to the
    /// same list in a row become one line with a poster strip ("added 4 shows to Plan to Watch").
    static func lines(_ log: [FriendActivity]) -> [FeedLine] {
        let completed = log.filter { $0.activity.type == "status" && $0.activity.after?.string == "completed" }
        var scoredWith: [Int: Int] = [:]
        var skip = Set<Int>()
        for c in log {
            if c.activity.type == "progress", completed.contains(where: { near($0, c, 2000) }) { skip.insert(c.id) }
            if c.activity.type == "score", let s = c.activity.after?.int,
               let done = completed.first(where: { near($0, c, 600_000) }), scoredWith[done.id] == nil {
                scoredWith[done.id] = s
                skip.insert(c.id)
            }
        }
        var out: [FeedLine] = []
        var groupKeys: [Int: String] = [:]
        for c in log where !skip.contains(c.id) {
            guard let w = words(c.activity) else { continue }
            let a = c.activity
            let line = FeedLine(id: a.id, user: c.user, verb: w.verb, object: w.object, tail: w.tail, media: a.media,
                                title: a.titleCard, titles: [], score: scoredWith[a.id] ?? w.score, at: a.date,
                                social: a.social)
            // "added" lines in a row from one person to one list fold into one
            let key = a.type == "added" ? "\(c.user.username)|\(a.media.rawValue)|\(w.tail)" : nil
            if let key, let last = out.last, groupKeys[last.id] == key, let t = line.title {
                var g = out.removeLast()
                if g.titles.isEmpty, let first = g.title { g.titles = [first] }
                g.titles.append(t)
                g.title = nil
                g.social = nil
                g.object = "\(g.titles.count) \(a.media.kind.titleNoun(g.titles.count))"
                out.append(g)
                continue
            }
            out.append(line)
            if let key { groupKeys[line.id] = key }
        }
        return out
    }
}

extension MediaKind {
    /// "shows", "films", "books" — what a group of added titles is called
    func titleNoun(_ n: Int) -> String {
        switch self {
        case .anime, .tv: return n == 1 ? "show" : "shows"
        case .movie: return n == 1 ? "film" : "films"
        case .manga: return "manga"
        case .book: return n == 1 ? "book" : "books"
        }
    }
}

// MARK: reviews (§10.5; 50)

/// ReviewTitle (src/social/reviews.ts)
struct ReviewTitle: Codable, Hashable, Sendable {
    var media: APIMedia
    var id: String
    var title: String
    var cover: String
    var format: String

    var titleId: String { TitleKey(media: media, id: id).titleId }
    var card: Title {
        Title(id: titleId, media: media.kind, name: title, cover: pictureURL(cover), format: format.isEmpty ? nil : format)
    }
}

/// Review (src/social/reviews.ts)
struct Review: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var author: Person
    var title: ReviewTitle
    /// the whole text, or its start when `cut`
    var body: String
    var cut: Bool
    var spoiler: Bool
    /// the reviewer's score, out of 100 (from their list)
    var score: Int?
    var at: Int64
    var edited: Int64?
    var social: Reactions?

    var date: Date { Millis.date(at) }
    var score10: String? { score.map { Format.score10($0) } }
    var likes: Int { social?.likes ?? 0 }
    /// the route id of its own page: "<titleId>@<username>"
    var key: String { ReviewKey(titleId: title.titleId, username: author.username).id }

    func toggledLike(me: Person? = nil) -> Review {
        var r = self
        r.social = social?.toggledLike(me: me)
        return r
    }
}

/// One review's place: whose and on what ("anime:154587@kenji", one path segment for the route).
struct ReviewKey: Hashable, Sendable {
    var titleId: String
    var username: String

    var id: String { titleId + "@" + username }

    init(titleId: String, username: String) {
        self.titleId = titleId
        self.username = username
    }

    init?(_ id: String) {
        guard let at = id.lastIndex(of: "@") else { return nil }
        let t = String(id[..<at]), u = String(id[id.index(after: at)...])
        guard !u.isEmpty, TitleKey(titleId: t) != nil else { return nil }
        titleId = t
        username = u
    }
}

/// GET titles/:kind/:id/reviews
struct TitleReviews: Codable, Hashable, Sendable {
    var mine: Review?
    /// others' you may see: friends first, then everyone else
    var reviews: [Review]
    var visibility: WireVisibility

    /// all of them, yours first
    var all: [Review] { (mine.map { [$0] } ?? []) + reviews }

    /// the reviewers' scores' average, out of 10; nil when none has a score
    var average: Double? {
        let s = all.compactMap(\.score).filter { $0 > 0 }
        guard !s.isEmpty else { return nil }
        return Double(s.reduce(0, +)) / Double(s.count) / 10
    }

    var count: Int { all.count }

    /// "average of 46 reviews"
    var averageLine: String { "average of \(Format.grouped(count)) review\(count == 1 ? "" : "s")" }

    var friendCount: Int { reviews.filter(\.author.isFriend).count }

    /// the title they're about (from the first review)
    var title: ReviewTitle? { all.first?.title }

    enum Sort: String, CaseIterable, Identifiable, Sendable {
        case liked, newest, highest, lowest
        var id: String { rawValue }
        var label: String {
            switch self {
            case .liked: return "Most liked"
            case .newest: return "Newest"
            case .highest: return "Highest score"
            case .lowest: return "Lowest score"
            }
        }
    }

    /// The reviews to show: friends only, near your own score (within one point), spoilers in or out, sorted.
    static func shown(_ reviews: [Review], sort: Sort, friendsOnly: Bool = false, nearScore: Int? = nil,
                      spoilers: Bool = true) -> [Review] {
        var out = reviews
        if friendsOnly { out = out.filter(\.author.isFriend) }
        if let s = nearScore { out = out.filter { $0.score.map { abs($0 - s) <= 10 } ?? false } }
        if !spoilers { out = out.filter { !$0.spoiler } }
        switch sort {
        case .liked: out.sort { ($0.likes, $0.at) > ($1.likes, $1.at) }
        case .newest: out.sort { $0.at > $1.at }
        case .highest: out.sort { ($0.score ?? -1, $0.likes) > ($1.score ?? -1, $1.likes) }
        case .lowest: out.sort { ($0.score ?? 101, -$0.likes) < ($1.score ?? 101, -$1.likes) }
        }
        return out
    }

    func replacing(_ r: Review) -> TitleReviews {
        var t = self
        if t.mine?.id == r.id { t.mine = r }
        if let i = t.reviews.firstIndex(where: { $0.id == r.id }) { t.reviews[i] = r }
        return t
    }
}

/// GET reviews, GET users/:username/reviews
struct UserReviews: Codable, Hashable, Sendable {
    var person: Person
    var reviews: [Review]
    var total: Int
}

/// GET titles/:kind/:id/friends: a friend with this title on their list
struct FriendEntry: Codable, Hashable, Sendable {
    var user: Person
    var status: EntryStatus
    var score: Int?
    var progress: Int
    var total: Int?
    var rewatching: Bool
    var repeats: Int
    var notes: String
}

struct FriendEntries: Codable, Hashable, Sendable { var friends: [FriendEntry] }
struct ReviewAnswer: Codable, Hashable, Sendable { var review: Review }

// MARK: messages (§11; 51-54)

/// a title shared in a message: a snapshot of it when it was sent
struct Card: Codable, Hashable, Sendable {
    /// singular ("anime", "movie")
    var kind: MediaKind
    var id: String
    var title: String
    /// "" = none
    var cover: String
    var format: String
    var year: Int?
    /// the sender's status and score, when they chose to include them
    var status: EntryStatus?
    var score: Int?

    var titleId: String { "\(kind.rawValue):\(id)" }
    var card: Title {
        Title(id: titleId, media: kind, name: title, cover: pictureURL(cover), format: format.isEmpty ? nil : format,
              year: year)
    }

    /// "Anime · TV · 2023"
    var line: String {
        ([kind.singular] + (format.isEmpty ? [] : [format]) + (year.map { [String($0)] } ?? [])).joined(separator: " · ")
    }
}

/// a photo in a message ("/dm/photo/<name>")
struct Photo: Codable, Hashable, Sendable {
    var src: URL
    var thumb: URL
    var width: Int
    var height: Int

    /// what a message sends for it: the last part of `src`
    var name: String { src.lastPathComponent }
}

struct Reaction: Codable, Hashable, Sendable {
    var emoji: String
    var mine: Bool
}

struct Message: Codable, Hashable, Identifiable, Sendable {
    /// a later message has a higher id
    var id: Int
    var mine: Bool
    var body: String
    var card: Card?
    var photos: [Photo]
    var at: Int64
    var edited: Int64?
    var deleted: Bool
    var reactions: [Reaction]

    var date: Date { Millis.date(at) }

    /// the same words, photos and shared title (a message shown while sending and the server's copy of it)
    func sameContent(_ o: Message) -> Bool {
        body == o.body && photos.map(\.name) == o.photos.map(\.name) && card?.id == o.card?.id
    }

    /// your reaction: one each, a new one replaces yours, the same one takes it back
    func reacting(_ emoji: String?) -> Message {
        var m = self
        let had = reactions.first { $0.mine }?.emoji
        m.reactions.removeAll(where: \.mine)
        if let emoji, emoji != had { m.reactions.append(Reaction(emoji: emoji, mine: true)) }
        return m
    }
}

/// a line in the conversation list
struct ConversationLine: Codable, Hashable, Identifiable, Sendable {
    var person: Person
    /// the newest message; nil when only cleared ones are left
    var last: Last?
    var unread: Int
    var muted: Bool

    struct Last: Codable, Hashable, Sendable {
        var mine: Bool
        var text: String
        var at: Int64
    }

    var id: String { person.username }
    /// "You: Sent you Andor"
    var preview: String { last.map { ($0.mine ? "You: " : "") + $0.text } ?? "" }
    var time: String { last.map { SocialText.listTime(Millis.date($0.at)) } ?? "" }
}

/// GET messages (and ?box=requests): your conversations, latest first, and how many requests wait.
struct MessagesAnswer: Codable, Hashable, Sendable {
    var lines: [ConversationLine]
    var requests: Int
}

/// The Messages part of the Social tab: the conversations and the requests waiting.
struct MessageList: Hashable, Sendable {
    var lines: [ConversationLine]
    /// the requests' own lines (GET messages?box=requests)
    var requestLines: [ConversationLine]
    var requests: Int

    /// the conversations with something unread (muted ones left out), as the tab badge
    var unread: Int { lines.filter { $0.unread > 0 && !$0.muted }.count }

    /// "aki.h wants to message you", "aki.h and 2 others want to message you"
    var requestLine: String? {
        let n = max(requests, requestLines.count)
        guard n > 0 else { return nil }
        guard let first = requestLines.first?.person.username else {
            return "\(n) \(n == 1 ? "person wants" : "people want") to message you"
        }
        if n == 1 { return "\(first) wants to message you" }
        return "\(first) and \(n - 1) other\(n - 1 == 1 ? "" : "s") want to message you"
    }

    /// the list with conversations you've opened since it loaded marked read
    func markingRead(_ ids: Set<String>) -> MessageList {
        var l = self
        for i in l.lines.indices where ids.contains(l.lines[i].id) { l.lines[i].unread = 0 }
        return l
    }

    func answering(_ ids: Set<String>) -> MessageList {
        var l = self
        let before = l.requestLines.count
        l.requestLines.removeAll { ids.contains($0.id) }
        l.requests = max(0, l.requests - (before - l.requestLines.count))
        return l
    }
}

/// GET conversations/:username: one conversation.
struct Conversation: Codable, Hashable, Sendable {
    var person: Person
    /// inbox, request (theirs, waiting for your answer), ignored, new (nothing yet)
    var box: String
    /// oldest first, 50
    var messages: [Message]
    /// there are older ones (`before` = the first one's id)
    var more: Bool
    /// the newest of your messages they read; nil when not shown
    var seen: Int?
    var muted: Bool
    var canSend: Bool
    /// why you can't send, to show
    var why: String?

    var isRequest: Bool { box == "request" }

    /// One line of the chat as drawn: a time stamp between stretches, a bubble (with its tail when it's the last
    /// of a run), or "Read" under the newest of yours they read.
    enum Line: Hashable, Identifiable, Sendable {
        case stamp(String)
        case bubble(Message, tail: Bool)
        case read

        var id: String {
            switch self {
            case .stamp(let s): return "stamp " + s
            case .bubble(let m, _): return "m\(m.id)"
            case .read: return "read"
            }
        }
    }

    /// a gap this long between two messages gets a time stamp
    static let stampGap: TimeInterval = 3600

    func lines(now: Date = Clock.now) -> [Line] {
        Self.lines(messages, seen: seen, now: now)
    }

    static func lines(_ messages: [Message], seen: Int?, now: Date = Clock.now) -> [Line] {
        var out: [Line] = []
        let readAt = seen.flatMap { s in messages.lastIndex { $0.mine && $0.id <= s } }
        for (i, m) in messages.enumerated() {
            if i == 0 || m.date.timeIntervalSince(messages[i - 1].date) > stampGap {
                out.append(.stamp(SocialText.stamp(m.date, now: now)))
            }
            let next = i + 1 < messages.count ? messages[i + 1] : nil
            let tail = next.map { $0.mine != m.mine || $0.date.timeIntervalSince(m.date) > stampGap } ?? true
            out.append(.bubble(m, tail: tail))
            if i == readAt { out.append(.read) }
        }
        return out
    }

    /// a sent message, added at the end
    func sending(_ m: Message) -> Conversation {
        var c = self
        c.messages.append(m)
        if c.box == "new" { c.box = "inbox" }
        return c
    }

    func reacting(_ id: Int, _ emoji: String?) -> Conversation {
        var c = self
        if let i = c.messages.firstIndex(where: { $0.id == id }) { c.messages[i] = c.messages[i].reacting(emoji) }
        return c
    }

    /// The server's copy after live news, keeping yours that are still on their way (shown, not yet in the
    /// server's answer): a sent one stays until a message of yours with the same words, photos and title shows up.
    func refreshed(_ server: Conversation) -> Conversation {
        var out = server
        let known = Set(server.messages.map(\.id))
        let newest = server.messages.map(\.id).max() ?? 0
        var confirmed = server.messages.filter(\.mine)
        for m in messages where m.mine && !known.contains(m.id) && m.id > newest {
            if let i = confirmed.firstIndex(where: { $0.sameContent(m) && $0.at >= m.at - 120_000 }) {
                confirmed.remove(at: i)
            } else {
                out.messages.append(m)
            }
        }
        return out
    }

    static let reactions = ["❤️", "😂", "😮", "😢", "🔥", "👍"]
}

/// GET messages/pulse: cheap; the tab badge, and who's typing (when the live stream isn't open)
struct Pulse: Codable, Hashable, Sendable {
    var unread: Int
    var requests: Int
    /// changes whenever anything in your messages did
    var stamp: Int64
    var typing: [String]
}

/// someone you could send to
struct Recipient: Codable, Hashable, Identifiable, Sendable {
    var person: Person
    var canSend: Bool
    var id: String { person.username }
}

struct RecipientAnswer: Codable, Hashable, Sendable { var recipient: Recipient? }
struct MessageAnswer: Codable, Hashable, Sendable { var message: Message }
struct PhotoAnswer: Codable, Hashable, Sendable { var photo: Photo }

/// POST conversations/:username/messages: any of the three
struct OutgoingMessage: Codable, Hashable, Sendable {
    var body: String?
    /// the last part of each upload's src
    var photos: [String]?
    var card: CardRef?

    struct CardRef: Codable, Hashable, Sendable {
        var kind: MediaKind
        var id: String
        /// add your status and score
        var mine: Bool
    }

    init(body: String? = nil, photos: [String]? = nil, card: CardRef? = nil) {
        self.body = body
        self.photos = photos
        self.card = card
    }
}

private struct EmojiBody: Codable {
    var emoji: String?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(emoji, forKey: .emoji)   // null takes it back
    }
}

private struct MutedBody: Codable { var muted: Bool }

// MARK: live (§11.6)

/// One event from GET messages/events: news, never a message's contents.
enum LiveEvent: Hashable, Sendable {
    /// a new message from or to `with`
    case message(String)
    /// `with` read yours
    case read(String)
    /// `with` is typing (show it for about 6 s)
    case typing(String)
    /// something else changed: reload what's open
    case change(String?)

    init?(json: Data) {
        guard let o = try? JSONDecoder().decode(JSONValue.self, from: json), case .object(let d) = o,
              let t = d["t"]?.string else { return nil }
        let with = d["with"]?.string
        switch t {
        case "message": guard let with else { return nil }; self = .message(with)
        case "read": guard let with else { return nil }; self = .read(with)
        case "typing": guard let with else { return nil }; self = .typing(with)
        case "change": self = .change(with)
        default: return nil
        }
    }
}

/// Reads the text/event-stream line by line: `data:` lines make an event at the blank line after them,
/// `retry:` sets the reconnect wait, lines starting with ":" (hello, beat) are comments.
struct LiveStream: Sendable {
    /// ms to wait before reconnecting
    private(set) var retry: Int = 5000
    private var data: [String] = []

    init() {}

    /// one line (without its newline); an event when this ends one
    mutating func feed(_ line: String) -> LiveEvent? {
        var l = line
        if l.hasSuffix("\r") { l.removeLast() }
        if l.isEmpty {
            defer { data = [] }
            guard !data.isEmpty else { return nil }
            return LiveEvent(json: Data(data.joined(separator: "\n").utf8))
        }
        if l.hasPrefix(":") { return nil }
        let (field, value) = Self.split(l)
        switch field {
        case "data": data.append(value)
        case "retry": if let n = Int(value) { retry = n }
        default: break
        }
        return nil
    }

    /// a whole chunk of the stream
    mutating func feed(text: String) -> [LiveEvent] {
        text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { feed(String($0)) }
    }

    private static func split(_ l: String) -> (String, String) {
        guard let c = l.firstIndex(of: ":") else { return (l, "") }
        var v = l[l.index(after: c)...]
        if v.hasPrefix(" ") { v = v.dropFirst() }
        return (String(l[..<c]), String(v))
    }
}

// MARK: words and times

enum SocialText {
    private static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = Clock.zone
        d.dateFormat = f
        return d
    }

    /// the feed's times: "12m", "3h" today, "Yesterday", "Sun" this week, "Oct 30" before
    static func feedTime(_ d: Date, now: Date = Clock.now) -> String {
        let days = -Format.dayOffset(d, now: now)
        if days <= 0 || now.timeIntervalSince(d) < 3600 { return Format.ago(d, now: now) }
        if days == 1 { return "Yesterday" }
        if days < 7 { return Format.weekday(d) }
        return Format.shortDay(d)
    }

    /// the message list's times: "9:12" today, "Yesterday", "Sun" this week, "Oct 30" before
    static func listTime(_ d: Date, now: Date = Clock.now) -> String {
        let days = -Format.dayOffset(d, now: now)
        if days <= 0 { return formatter("h:mm").string(from: d) }
        if days == 1 { return "Yesterday" }
        if days < 7 { return Format.weekday(d) }
        return Format.shortDay(d)
    }

    /// "12 minutes ago", "3 hours ago", "Yesterday", "Oct 28" (a thread's or review's header)
    static func agoWords(_ d: Date, now: Date = Clock.now) -> String {
        let s = now.timeIntervalSince(d)
        if s < 60 { return "Just now" }
        if s < 3600 { let m = Int(s / 60); return "\(m) minute\(m == 1 ? "" : "s") ago" }
        let days = -Format.dayOffset(d, now: now)
        if days <= 0 { let h = Int(s / 3600); return "\(h) hour\(h == 1 ? "" : "s") ago" }
        if days == 1 { return "Yesterday" }
        return Format.shortDay(d)
    }

    /// a chat's time stamps: "Today 9:10 AM", "Yesterday 11:40 PM", "Sun 8:02 PM", "Oct 30 8:02 PM"
    static func stamp(_ d: Date, now: Date = Clock.now) -> String {
        let days = -Format.dayOffset(d, now: now)
        let t = Format.time(d)
        if days <= 0 { return "Today " + t }
        if days == 1 { return "Yesterday " + t }
        if days < 7 { return Format.weekday(d) + " " + t }
        return Format.shortDay(d) + " " + t
    }

    /// the "replies" heading: "2 replies", "1 reply", "No replies yet"
    static func repliesHeading(_ n: Int) -> String {
        n == 0 ? "No replies yet" : "\(Format.grouped(n)) repl\(n == 1 ? "y" : "ies")"
    }
}

/// What changed this session that the next load of a list doesn't know yet (the demo answers the same files):
/// conversations you opened (read now) and message requests you answered.
@MainActor
enum SocialSession {
    static var read: Set<String> = []
    static var answered: Set<String> = []

    /// the list as this session left it
    static func applied(_ list: MessageList) -> MessageList {
        list.markingRead(read).answering(answered)
    }

    /// a new session (a new AppModel, signing out, a screen test's launch) starts with nothing read or answered
    static func reset() {
        read = []
        answered = []
    }
}

// MARK: the app API (§10, §11)

extension APIClient {
    /// "anime/154587" from "anime:154587" (the singular kind and the id)
    private static func titlePath(_ titleId: String) -> String {
        guard let k = TitleKey(titleId: titleId) else { return titleId }
        return "\(k.media.kind.rawValue)/\(k.id)"
    }

    // friends and the feed
    func friends() async throws -> FriendsState { try await get("friends") }
    func feed(before: Int64? = nil) async throws -> [FriendActivity] {
        let q = before.map { [URLQueryItem(name: "before", value: String($0))] } ?? []
        let a: FeedAnswer = try await get("feed", query: q)
        return a.activity
    }
    func activity(_ id: Int) async throws -> FriendActivity {
        let a: ActivityItem = try await get("activity/\(id)")
        return a.item
    }

    // friend requests and blocks
    /// someone by their exact username; nil when there's nobody (404)
    func findPerson(_ username: String) async throws -> Person? {
        do { return try await get("users/\(username)/person") as Person } catch let e as APIError where e.status == 404 {
            return nil
        }
    }
    func requestFriend(_ username: String) async throws -> Relation {
        let a: RelationAnswer = try await send("POST", "users/\(username)/friend")
        return a.relation
    }
    func answerFriend(_ username: String, accept: Bool) async throws -> Relation {
        let a: RelationAnswer = try await send("POST", "users/\(username)/friend/answer", AcceptBody(accept: accept))
        return a.relation
    }
    func cancelFriendRequest(_ username: String) async throws -> OKReply {
        try await send("DELETE", "users/\(username)/friend/request")
    }
    func unfriend(_ username: String) async throws -> OKReply { try await send("DELETE", "users/\(username)/friend") }
    func block(_ username: String) async throws -> OKReply { try await send("POST", "users/\(username)/block") }
    func unblock(_ username: String) async throws -> OKReply { try await send("DELETE", "users/\(username)/block") }

    // likes and replies
    func like(_ target: Reactions.Target, _ on: Bool) async throws -> Reactions {
        let a: ReactionsAnswer = try await send("POST", "likes/\(target.on)/\(target.id)", LikeBody(like: on))
        return a.reactions
    }
    func replies(_ target: Reactions.Target) async throws -> Replies { try await get("replies/\(target.on)/\(target.id)") }
    func reply(_ target: Reactions.Target, _ body: String, parent: Int? = nil) async throws -> Reply {
        let a: ReplyAnswer = try await send("POST", "replies/\(target.on)/\(target.id)", ReplyBody(body: body, parent: parent))
        return a.reply
    }
    func editReply(_ id: Int, _ body: String) async throws -> Reply {
        let a: ReplyAnswer = try await send("PATCH", "replies/\(id)", BodyOnly(body: body))
        return a.reply
    }
    func deleteReply(_ id: Int) async throws -> OKReply { try await send("DELETE", "replies/\(id)") }

    // reviews
    func titleReviews(_ titleId: String) async throws -> TitleReviews {
        try await get("titles/\(Self.titlePath(titleId))/reviews")
    }
    func titleFriends(_ titleId: String) async throws -> [FriendEntry] {
        let a: FriendEntries = try await get("titles/\(Self.titlePath(titleId))/friends")
        return a.friends
    }
    /// yours (nil) or someone's
    func reviews(of username: String? = nil, limit: Int = 50) async throws -> UserReviews {
        let path = username.map { "users/\($0)/reviews" } ?? "reviews"
        return try await get(path, query: [URLQueryItem(name: "limit", value: String(limit))])
    }
    /// one whole review
    func review(_ key: ReviewKey) async throws -> Review {
        try await get("users/\(key.username)/reviews/\(Self.titlePath(key.titleId))")
    }

    // messages
    func messages(requests: Bool = false) async throws -> MessagesAnswer {
        try await get("messages", query: requests ? [URLQueryItem(name: "box", value: "requests")] : [])
    }
    /// the conversations and the requests' own lines
    func messageList() async throws -> MessageList {
        let inbox = try await messages()
        var waiting: [ConversationLine] = []
        if inbox.requests > 0 { waiting = try await messages(requests: true).lines }
        return MessageList(lines: inbox.lines, requestLines: waiting, requests: inbox.requests)
    }
    func pulse() async throws -> Pulse { try await get("messages/pulse") }
    /// someone you could send to, by their exact username
    func findRecipient(_ username: String) async throws -> Recipient? {
        let a: RecipientAnswer = try await get("messages/recipients/\(username)")
        return a.recipient
    }
    func conversation(_ username: String, before: Int? = nil) async throws -> Conversation {
        try await get("conversations/\(username)",
                      query: before.map { [URLQueryItem(name: "before", value: String($0))] } ?? [])
    }
    func sendMessage(_ username: String, _ m: OutgoingMessage, requestId: String? = nil) async throws -> Message {
        let a: MessageAnswer = try await send("POST", "conversations/\(username)/messages", m, requestId: requestId)
        return a.message
    }
    func uploadPhoto(_ data: Data, contentType: String) async throws -> Photo {
        let a: PhotoAnswer = try await upload("messages/photos", data, contentType: contentType)
        return a.photo
    }
    func deletePhoto(_ name: String) async throws -> OKReply { try await send("DELETE", "messages/photos/\(name)") }
    func typing(_ username: String) async throws -> OKReply { try await send("POST", "conversations/\(username)/typing") }
    func editMessage(_ id: Int, _ body: String) async throws -> OKReply { try await send("PATCH", "messages/\(id)", BodyOnly(body: body)) }
    func deleteMessage(_ id: Int) async throws -> OKReply { try await send("DELETE", "messages/\(id)") }
    func react(_ id: Int, _ emoji: String?) async throws -> OKReply {
        try await send("POST", "messages/\(id)/reaction", EmojiBody(emoji: emoji))
    }
    func markRead(_ username: String) async throws -> OKReply { try await send("POST", "conversations/\(username)/read") }
    func answerMessageRequest(_ username: String, accept: Bool) async throws -> OKReply {
        try await send("POST", "conversations/\(username)/answer", AcceptBody(accept: accept))
    }
    func mute(_ username: String, _ muted: Bool) async throws -> OKReply {
        try await send("POST", "conversations/\(username)/mute", MutedBody(muted: muted))
    }
    func clearConversation(_ username: String) async throws -> OKReply {
        try await send("POST", "conversations/\(username)/clear")
    }
}
