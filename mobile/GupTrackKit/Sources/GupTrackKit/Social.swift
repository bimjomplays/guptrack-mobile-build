import Foundation

// Social (44-54): friends' activity, one activity with its replies, friends and requests, finding someone, a
// title's reviews and one review, messages, a conversation and a message request. The answers' shapes and the
// logic the screens show (sentences, captions, times, grouping chat bubbles, filters) live here, so they're tested
// on Linux; the views only draw them.

// MARK: activity (44, 45)

/// GET social/activity: what friends did, newest first.
struct ActivityFeed: Codable, Equatable, Sendable {
    var items: [Item]

    /// One thing a friend did: "kenji completed Frieren", "lena added 4 shows to Plan to Watch".
    struct Item: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var user: UserRef
        /// the words between the name and the object ("completed", "read chapters 41–46 of", "added 4 shows to")
        var verb: String
        /// the bold part after the verb: a title's name or a list's
        var object: String
        var media: MediaKind
        /// the title it's about (its cover on the right, the card in the thread)
        var title: Title?
        /// several titles at once (a poster strip under the sentence)
        var titles: [Title]?
        /// their score out of 100
        var score: Int?
        /// a word for the meta line ("Season 2")
        var detail: String?
        /// a review's opening lines
        var quote: String?
        var at: Date
        var likes: Int
        var replies: Int
        var liked: Bool

        /// "Anime · ★9 · 12m" split in its parts: the words before the score, the score, the time
        var metaBefore: String {
            ([media.singular] + (detail.map { [$0] } ?? [])).joined(separator: " · ")
        }

        var score10: String? { score.map { Format.score10($0) } }

        /// the thread's sentence ends "and rated it ★ 9" when there's a score and no review
        var ratedInThread: Bool { score != nil && quote == nil }

        /// a like from you: the heart and the count
        func toggledLike() -> Item {
            var i = self
            i.liked.toggle()
            i.likes = max(0, likes + (i.liked ? 1 : -1))
            return i
        }
    }
}

/// GET activity/<id>: one activity with who liked it and the replies.
struct ActivityThread: Codable, Equatable, Sendable {
    var item: ActivityFeed.Item
    var likedBy: [UserRef]
    var replies: [Reply]

    struct Reply: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var user: UserRef
        var text: String
        var at: Date
        var likes: Int
        var liked: Bool

        func toggledLike() -> Reply {
            var r = self
            r.liked.toggle()
            r.likes = max(0, likes + (r.liked ? 1 : -1))
            return r
        }
    }
}

/// what's sent for a reply or a message
struct SocialPost: Codable, Equatable, Sendable {
    var text: String?
    var titleId: String?
}

// MARK: friends (46, 47)

/// GET friends: requests to you, your friends, requests you sent, people you blocked.
struct FriendsPage: Codable, Equatable, Sendable {
    var requests: [Request]
    var friends: [Friend]
    var sent: [Request]
    var blocked: [UserRef]

    struct Request: Codable, Identifiable, Hashable, Sendable {
        var user: UserRef
        var inCommon: Int
        var at: Date

        var id: String { user.username }
        /// "12 in common · 12m"
        var line: String { "\(Format.grouped(inCommon)) in common · \(Format.ago(at))" }
    }

    struct Friend: Codable, Identifiable, Hashable, Sendable {
        var user: UserRef
        var inCommon: Int
        /// what they're up to ("Active now", "Reading Vagabond")
        var seen: String
        var online: Bool

        var id: String { user.username }
        /// "41 in common · Active now"
        var line: String { "\(Format.grouped(inCommon)) in common · \(seen)" }
    }

    /// accepting a request makes them a friend (at the top of Friends)
    func accepting(_ username: String) -> FriendsPage {
        var p = self
        guard let r = requests.first(where: { $0.id == username }) else { return p }
        p.requests.removeAll { $0.id == username }
        p.friends.insert(Friend(user: r.user, inCommon: r.inCommon, seen: "New friend", online: false), at: 0)
        return p
    }

    func declining(_ username: String) -> FriendsPage {
        var p = self
        p.requests.removeAll { $0.id == username }
        return p
    }

    func cancelling(_ username: String) -> FriendsPage {
        var p = self
        p.sent.removeAll { $0.id == username }
        return p
    }

    func unblocking(_ username: String) -> FriendsPage {
        var p = self
        p.blocked.removeAll { $0.username == username }
        return p
    }
}

/// GET users/search?q=<username>: exact username search, one person or nobody.
struct FriendSearch: Codable, Equatable, Sendable {
    var user: Found?

    struct Found: Codable, Hashable, Sendable {
        var user: UserRef
        var titles: Int
        var inCommon: Int
        /// already a friend
        var friend: Bool
        /// you already asked
        var requested: Bool

        /// "212 titles · 22 in common"
        var line: String { "\(Format.grouped(titles)) titles · \(Format.grouped(inCommon)) in common" }
    }

    /// what's searched: the whole username, trimmed, lowercased, without a leading @
    static func query(_ typed: String) -> String {
        var q = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.hasPrefix("@") { q.removeFirst() }
        return q
    }
}

// MARK: reviews (50)

/// GET titles/<id>/reviews: the title, the average of its reviews and the reviews.
struct ReviewsPage: Codable, Equatable, Sendable {
    var title: Title
    /// out of 10
    var average: Double
    var count: Int
    var reviews: [Review]

    struct Review: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var user: UserRef
        var friend: Bool
        /// out of 100
        var score: Int
        var at: Date
        var headline: String
        var body: String
        var likes: Int
        var replies: Int
        var liked: Bool
        var spoiler: Bool

        var score10: String { Format.score10(score) }

        func toggledLike() -> Review {
            var r = self
            r.liked.toggle()
            r.likes = max(0, likes + (r.liked ? 1 : -1))
            return r
        }
    }

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

    var friendCount: Int { reviews.filter(\.friend).count }

    /// "average of 46 reviews"
    var averageLine: String { "average of \(Format.grouped(count)) review\(count == 1 ? "" : "s")" }

    /// The reviews to show: friends only, near your own score (within one point), spoilers in or out, sorted.
    static func shown(_ reviews: [Review], sort: Sort, friendsOnly: Bool = false, nearScore: Int? = nil,
                      spoilers: Bool = true) -> [Review] {
        var out = reviews
        if friendsOnly { out = out.filter(\.friend) }
        if let s = nearScore { out = out.filter { abs($0.score - s) <= 10 } }
        if !spoilers { out = out.filter { !$0.spoiler } }
        switch sort {
        case .liked: out.sort { ($0.likes, $0.at) > ($1.likes, $1.at) }
        case .newest: out.sort { $0.at > $1.at }
        case .highest: out.sort { ($0.score, $0.likes) > ($1.score, $1.likes) }
        case .lowest: out.sort { ($0.score, -$0.likes) < ($1.score, -$1.likes) }
        }
        return out
    }
}

/// GET reviews/<id>: one review with its title, who liked it and the replies.
struct ReviewThread: Codable, Equatable, Sendable {
    var review: ReviewsPage.Review
    var title: Title
    var likedBy: [UserRef]
    var replies: [ActivityThread.Reply]
}

// MARK: messages (51-54)

/// GET messages: message requests on top, then conversations, latest first.
struct MessageList: Codable, Equatable, Sendable {
    var requests: [Request]
    var conversations: [Row]

    /// someone who isn't a friend and wants to message you
    struct Request: Codable, Identifiable, Hashable, Sendable {
        var user: UserRef
        var at: Date
        var id: String { user.username }
    }

    /// one conversation in the list; its id is the other person's username
    struct Row: Codable, Identifiable, Hashable, Sendable {
        var user: UserRef
        var last: String
        var fromMe: Bool
        var at: Date
        var unread: Int
        var online: Bool

        var id: String { user.username }
        /// "You: Sent you Andor"
        var preview: String { (fromMe ? "You: " : "") + last }
        var time: String { SocialText.listTime(at) }
    }

    /// the Social tab's badge
    var unread: Int { conversations.reduce(0) { $0 + $1.unread } }

    /// "aki.h wants to message you", "aki.h and 2 others want to message you"
    var requestLine: String? {
        guard let first = requests.first else { return nil }
        if requests.count == 1 { return "\(first.id) wants to message you" }
        let n = requests.count - 1
        return "\(first.id) and \(n) other\(n == 1 ? "" : "s") want to message you"
    }

    /// the list with conversations you've opened since it loaded marked read
    func markingRead(_ ids: Set<String>) -> MessageList {
        var l = self
        for i in l.conversations.indices where ids.contains(l.conversations[i].id) {
            l.conversations[i].unread = 0
        }
        return l
    }
}

/// GET conversations/<username>: the chat with one person.
struct Conversation: Codable, Equatable, Sendable {
    var user: UserRef
    /// "Active now", "Active 2h ago"
    var status: String
    var messages: [Message]
    var typing: Bool
    var unread: Int

    struct Message: Codable, Identifiable, Hashable, Sendable {
        var id: String
        var fromMe: Bool
        var text: String?
        /// a shared title (the card that opens it)
        var title: Title?
        var at: Date
        /// a reaction on this message (from the other side on yours, from you on theirs)
        var reaction: String?
        /// when they read it (yours only)
        var read: Date?
    }

    /// One line of the chat as drawn: a time stamp between stretches, a bubble (with its tail when it's the last
    /// of a run), or "Read 12:03 AM" under your last read message.
    enum Line: Hashable, Identifiable, Sendable {
        case stamp(String)
        case bubble(Message, tail: Bool)
        case read(String)

        var id: String {
            switch self {
            case .stamp(let s): return "stamp " + s
            case .bubble(let m, _): return m.id
            case .read(let s): return "read " + s
            }
        }
    }

    /// a gap this long between two messages gets a time stamp
    static let stampGap: TimeInterval = 3600

    static func lines(_ messages: [Message]) -> [Line] {
        var out: [Line] = []
        let lastRead = messages.lastIndex { $0.fromMe && $0.read != nil }
        for (i, m) in messages.enumerated() {
            if i == 0 || m.at.timeIntervalSince(messages[i - 1].at) > stampGap {
                out.append(.stamp(SocialText.stamp(m.at)))
            }
            let next = messages[safe: i + 1]
            let tail = next == nil || next!.fromMe != m.fromMe || next!.at.timeIntervalSince(m.at) > stampGap
            out.append(.bubble(m, tail: tail))
            if i == lastRead, let r = m.read { out.append(.read("Read " + Format.time(r))) }
        }
        return out
    }

    /// a sent message, added at the end (and no longer typing back while you write)
    func sending(_ m: Message) -> Conversation {
        var c = self
        c.messages.append(m)
        return c
    }

    func reacting(_ id: String, _ emoji: String?) -> Conversation {
        var c = self
        if let i = c.messages.firstIndex(where: { $0.id == id }) {
            c.messages[i].reaction = c.messages[i].reaction == emoji ? nil : emoji
        }
        return c
    }

    static let reactions = ["❤️", "😂", "😮", "😢", "🔥", "👍"]
}

/// GET message-requests/<username>: who they are and what they sent.
struct MessageRequest: Codable, Equatable, Sendable {
    var user: UserRef
    var titles: Int
    var inCommon: Int
    var messages: [Conversation.Message]

    /// "Not a friend · 312 titles · 14 in common"
    var line: String { "Not a friend · \(Format.grouped(titles)) titles · \(Format.grouped(inCommon)) in common" }
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

    /// "Liked by tobiwan and 3 others": the bold name and the rest; nil when nobody liked it
    static func likedBy(_ users: [UserRef], likes: Int) -> (name: String, rest: String)? {
        guard let first = users.first, likes > 0 else { return nil }
        let others = likes - 1
        if others <= 0 { return (first.username, "") }
        return (first.username, "and \(others) other\(others == 1 ? "" : "s")")
    }

    /// a shared title's line: "Anime · 11 eps · Fall 2026", "Movie · 2h 47m · 2024"
    static func cardLine(_ t: Title) -> String {
        var parts = [t.media.singular]
        if let n = t.total, let unit = t.media.unit {
            let short = unit == "episode" ? "ep" : unit == "chapter" ? "ch" : "p."
            parts.append(unit == "page" ? "\(Format.grouped(n)) pages" : "\(Format.grouped(n)) \(short)\(n == 1 || short == "p." ? "" : "s")")
        } else if let r = t.runtime, t.media == .movie {
            parts.append(r)
        }
        if let s = t.season { parts.append(s) } else if let y = t.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
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
        var l = list.markingRead(read)
        l.requests.removeAll { answered.contains($0.id) }
        return l
    }
}

// MARK: the app API

extension APIClient {
    func activityFeed() async throws -> ActivityFeed { try await get("social/activity") }
    func activityThread(_ id: String) async throws -> ActivityThread { try await get("activity/" + id) }
    func likeActivity(_ id: String, _ on: Bool) async throws -> OKReply {
        try await send(on ? "POST" : "DELETE", "activity/\(id)/like")
    }
    func replyToActivity(_ id: String, _ text: String) async throws -> OKReply {
        try await send("POST", "activity/\(id)/replies", SocialPost(text: text))
    }

    func friendsPage() async throws -> FriendsPage { try await get("friends") }
    func answerFriendRequest(_ username: String, accept: Bool) async throws -> OKReply {
        try await send("POST", "friends/requests/\(username)/\(accept ? "accept" : "decline")")
    }
    func requestFriend(_ username: String) async throws -> OKReply {
        try await send("POST", "friends/requests", ["username": username])
    }
    func cancelFriendRequest(_ username: String) async throws -> OKReply {
        try await send("DELETE", "friends/requests/" + username)
    }
    func unblock(_ username: String) async throws -> OKReply { try await send("DELETE", "blocks/" + username) }
    func block(_ username: String) async throws -> OKReply { try await send("POST", "blocks", ["username": username]) }
    func findUser(_ username: String) async throws -> FriendSearch {
        try await get("users/search", query: [URLQueryItem(name: "q", value: username)])
    }

    func reviewsPage(_ titleId: String) async throws -> ReviewsPage { try await get("titles/\(titleId)/reviews") }
    func reviewThread(_ id: String) async throws -> ReviewThread { try await get("reviews/" + id) }
    func likeReview(_ id: String, _ on: Bool) async throws -> OKReply {
        try await send(on ? "POST" : "DELETE", "reviews/\(id)/like")
    }
    func replyToReview(_ id: String, _ text: String) async throws -> OKReply {
        try await send("POST", "reviews/\(id)/replies", SocialPost(text: text))
    }

    func messageList() async throws -> MessageList { try await get("messages") }
    func conversation(_ username: String) async throws -> Conversation { try await get("conversations/" + username) }
    func sendMessage(_ username: String, _ post: SocialPost) async throws -> OKReply {
        try await send("POST", "conversations/\(username)/messages", post)
    }
    func markRead(_ username: String) async throws -> OKReply { try await send("POST", "conversations/\(username)/read") }
    func messageRequest(_ username: String) async throws -> MessageRequest { try await get("message-requests/" + username) }
    /// accept, ignore or report
    func answerMessageRequest(_ username: String, _ answer: String) async throws -> OKReply {
        try await send("POST", "message-requests/\(username)/\(answer)")
    }
}
