import Foundation

// docs/app-api.md §6: the bell. `GET notices` → `BellNotice[]` (src/home/notices.server.ts: `Notice` from
// src/home/types.ts plus `seenAt` and `unseen`), newest first; `POST notices/seen` when the bell is opened. The
// server writes each notice's words: `title` is the person (their display name) or the title, `text` the rest.
// Friend requests are answered inline with answerFriend(_:accept:) (Social.swift).

/// What a like or a reply is on (src/social/reactions.ts `ItemLink`): an activity line or a review.
enum ItemLink: Codable, Hashable, Sendable {
    case activity(id: Int)
    case review(username: String, kind: MediaKind, id: String)

    private enum Key: String, CodingKey { case to, id, username, kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .to) {
        case "activity":
            self = .activity(id: try c.decode(Int.self, forKey: .id))
        case "review":
            self = .review(username: try c.decode(String.self, forKey: .username),
                           kind: try c.decode(MediaKind.self, forKey: .kind), id: try c.decode(String.self, forKey: .id))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .to, in: c, debugDescription: "not an item link: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .activity(let id):
            try c.encode("activity", forKey: .to)
            try c.encode(id, forKey: .id)
        case .review(let username, let kind, let id):
            try c.encode("review", forKey: .to)
            try c.encode(username, forKey: .username)
            try c.encode(kind, forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }

    /// the page it opens: the activity line, or the review ("<username>:<kind>:<id>")
    var route: Route {
        switch self {
        case .activity(let id): return .activity(String(id))
        case .review(let username, let kind, let id): return .review("\(username):\(kind.rawValue):\(id)")
        }
    }
}

/// One thing the bell tells you about.
struct BellNotice: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case episode, sequel, release
        case friendRequest = "friend-request"
        case friendAccepted = "friend-accepted"
        case comment, like, reply
        case replyToYou = "reply-to-you"
        case message
        case messageRequest = "message-request"
    }

    /// stable for the same news
    var key: String
    var kind: Kind
    /// the title it's about; nil for news about people
    var ref: TitleRef?
    /// friend news, comments and messages: who (their username)
    var user: String?
    /// likes and replies: the activity line or review they're on
    var item: ItemLink?
    /// the person's name, or the title's
    var title: String
    /// their avatar or the title's cover ("" = none)
    @Picture var cover: URL?
    /// "Episode 7 is out", "Wants to be friends", "Commented on your profile: “…”"
    var text: String
    /// when it happened (ms); 0 = unknown
    var at: Int64
    /// when it first showed up (ms)
    var seenAt: Int64
    /// came in since the bell was last opened
    var unseen: Bool

    var id: String { key }

    /// when it happened, else when it first showed up
    var date: Date { Millis.date(at > 0 ? at : seenAt) }

    /// a person leads the row (avatar); title news leads with the poster
    var leadsWithPerson: Bool {
        switch kind {
        case .episode, .sequel, .release: return false
        default: return true
        }
    }

    /// a piece of the sentence; strong pieces are names and titles (semibold, full ink)
    struct Run: Hashable, Sendable {
        var text: String
        var strong: Bool
    }

    /// [kenji] sent you a message…: a person's notice reads name + the server's text (its first letter lowered);
    /// a title's reads title, then the text on its own ("Episode 7 is out"). A single message's text is just the
    /// message, so it reads "sent you a message: “…”"; "3 new messages: “…”" reads "sent you 3 new messages: “…”".
    var runs: [Run] {
        guard leadsWithPerson else { return [Run(text: title, strong: true), Run(text: " · " + text, strong: false)] }
        if kind == .message {
            let several = text.first?.isNumber == true && text.contains(" new messages: “")
            return [Run(text: title, strong: true),
                    Run(text: several ? " sent you \(text)" : " sent you a message: “\(text)”", strong: false)]
        }
        let rest = text.prefix(1).lowercased() + text.dropFirst()
        return [Run(text: title, strong: true), Run(text: " " + rest, strong: false)]
    }

    /// the whole sentence as plain text (VoiceOver, tests)
    var sentence: String { runs.map(\.text).joined() }

    /// the grey line: "12 min ago", "Wed", "Oct 21"; a new episode adds where you are ("you're on 5 of 11")
    func caption(entry: LibraryEntry? = nil, now: Date = Clock.now) -> String {
        let d = date
        let offset = Format.dayOffset(d, now: now)
        var parts = [offset == 0 ? Format.agoLong(d, now: now) : offset >= -6 ? Format.weekday(d) : Format.shortDay(d)]
        if kind == .episode, let e = entry, e.status.isActive || e.status == .hold {
            parts.append("you're on \(Format.grouped(e.progress))" + (e.title.total.map { " of \(Format.grouped($0))" } ?? ""))
        }
        return parts.joined(separator: " · ")
    }

    /// the page a tap opens; `me` is your username (a comment is on your profile)
    func route(me: String? = nil) -> Route? {
        switch kind {
        case .episode, .sequel, .release:
            return ref.map { .title($0.titleId) }
        case .friendRequest, .friendAccepted:
            return user.map { .user($0) }
        case .message:
            return user.map { .conversation($0) }
        case .messageRequest:
            return user.map { .messageRequest($0) }
        case .comment:
            return item?.route ?? me.map { .user($0) } ?? user.map { .user($0) }
        case .like, .reply, .replyToYou:
            return item?.route ?? ref.map { .title($0.titleId) } ?? user.map { .user($0) }
        }
    }
}

/// The bell's sections: Today, This week, Earlier.
struct NoticeSection: Identifiable, Hashable, Sendable {
    var name: String
    var items: [BellNotice]

    var id: String { name }

    /// newest first, empty sections left out
    static func of(_ items: [BellNotice], now: Date = Clock.now) -> [NoticeSection] {
        var today: [BellNotice] = [], week: [BellNotice] = [], earlier: [BellNotice] = []
        for i in items.sorted(by: { $0.date > $1.date }) {
            let d = Format.dayOffset(i.date, now: now)
            if d >= 0 { today.append(i) } else if d >= -6 { week.append(i) } else { earlier.append(i) }
        }
        return [NoticeSection(name: "Today", items: today), NoticeSection(name: "This week", items: week),
                NoticeSection(name: "Earlier", items: earlier)].filter { !$0.items.isEmpty }
    }

    /// the bell's dot: how many came in since it was last opened
    static func unseen(_ items: [BellNotice]) -> Int { items.filter(\.unseen).count }
}

extension APIClient {
    /// GET notices: the bell, newest first
    func notices() async throws -> [BellNotice] { try await get("notices") }

    /// POST notices/seen: the bell was opened
    func markNoticesSeen() async throws -> OKReply { try await send("POST", "notices/seen") }
}
