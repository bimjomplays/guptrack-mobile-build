import Foundation

/// GET notifications: what happened for you (08), newest first. Friend requests are answered right in the list
/// (POST friends/requests/<username>/accept or /decline); Mark all read is POST notifications/read.
struct NotificationFeed: Codable, Equatable, Sendable {
    var items: [Item]

    struct Item: Codable, Identifiable, Hashable, Sendable {
        enum Kind: String, Codable, Hashable, Sendable {
            /// someone wants to be friends (Accept / Decline inline)
            case friendRequest
            /// a direct message
            case message
            /// a comment on your profile or one of your activities
            case comment
            /// likes on your review or activity
            case like
            /// a reply to your comment
            case reply
            /// a new episode of something you watch
            case episode
            /// a sequel to something on your list was announced
            case sequel
            /// something on your Plan to Watch / Read comes out
            case release
        }

        var id: String
        var kind: Kind
        var at: Date
        var unread: Bool
        var user: UserRef?
        /// "and 2 others" on likes
        var others: Int?
        var title: Title?
        /// the message or comment
        var quote: String?
        /// what a tap opens: a conversation, activity or review id
        var target: String?
        /// what a comment or like is on: "profile", "activity", "review"
        var subject: String?
        var episode: Int?
        /// when a planned title comes out
        var releaseAt: Date?
        /// "comes 2027" when there's no date yet
        var note: String?
        /// on a friend request: titles you both have
        var inCommon: Int?
        /// the server's copy of your status for the title (the library's wins)
        var status: ListStatus?
    }

    /// a piece of a notification's sentence; strong pieces are names and titles (semibold, full ink)
    struct Run: Hashable, Sendable {
        var text: String
        var strong: Bool
    }

    struct Section: Identifiable, Hashable, Sendable {
        var name: String
        var items: [Item]

        var id: String { name }
    }

    /// Today, This week, Earlier (empty ones left out)
    static func sections(_ items: [Item], now: Date = Clock.now) -> [Section] {
        let sorted = items.sorted { $0.at > $1.at }
        var today: [Item] = [], week: [Item] = [], earlier: [Item] = []
        for i in sorted {
            let d = Format.dayOffset(i.at, now: now)
            if d >= 0 { today.append(i) } else if d >= -6 { week.append(i) } else { earlier.append(i) }
        }
        return [Section(name: "Today", items: today), Section(name: "This week", items: week),
                Section(name: "Earlier", items: earlier)].filter { !$0.items.isEmpty }
    }

    static func unreadCount(_ items: [Item]) -> Int { items.filter(\.unread).count }
}

extension NotificationFeed.Item {
    private typealias Run = NotificationFeed.Run

    /// the sentence, e.g. [kenji] sent you a message: “…”. `entry` is the title's library entry (for "on your Plan
    /// to Watch").
    func runs(entry: LibraryEntry? = nil) -> [NotificationFeed.Run] {
        let who = user?.username ?? "Someone"
        let name = title?.name ?? "a title"
        let q = quote.map { "“\($0)”" } ?? ""
        switch kind {
        case .friendRequest:
            return [Run(text: who, strong: true), Run(text: " wants to be friends", strong: false)]
        case .message:
            return [Run(text: who, strong: true), Run(text: " sent you a message" + (q.isEmpty ? "" : ": " + q), strong: false)]
        case .comment:
            let on = subject == "activity" ? "your activity" : "your profile"
            return [Run(text: who, strong: true), Run(text: " commented on \(on)" + (q.isEmpty ? "" : ": " + q), strong: false)]
        case .like:
            var out = [Run(text: who, strong: true)]
            if let n = others, n > 0 { out.append(Run(text: " and \(n) other\(n == 1 ? "" : "s")", strong: false)) }
            let what = subject == "activity" ? "your update on " : "your review of "
            out.append(Run(text: " liked " + what, strong: false))
            out.append(Run(text: name, strong: true))
            return out
        case .reply:
            return [Run(text: who, strong: true), Run(text: " replied to your comment on ", strong: false),
                    Run(text: name, strong: true)]
        case .episode:
            let unit = (title?.media).map { $0 == .manga ? "Chapter" : "Episode" } ?? "Episode"
            return [Run(text: "\(unit) \(episode ?? 1)", strong: true), Run(text: " of ", strong: false),
                    Run(text: name, strong: true), Run(text: " is out", strong: false)]
        case .sequel:
            return [Run(text: "A sequel was announced: ", strong: false), Run(text: name, strong: true)]
        case .release:
            var tail = ""
            if let s = entry?.status ?? status, let media = title?.media { tail += ", on your \(s.label(media))," }
            if let d = releaseAt { tail += " comes out \(ScheduleWords.format("EEE, MMM d", d))" }
            else if let note { tail += " " + note }
            else { tail += " is out" }
            return [Run(text: name, strong: true), Run(text: tail, strong: false)]
        }
    }

    /// the whole sentence as plain text (VoiceOver, tests)
    func sentence(entry: LibraryEntry? = nil) -> String { runs(entry: entry).map(\.text).joined() }

    /// the grey line: "12 min ago · 12 titles in common", "Fri, Oct 30 · you're on 6 of 11", "Thu · comes 2027"
    func caption(entry: LibraryEntry? = nil, now: Date = Clock.now) -> String {
        let today = Format.dayOffset(at, now: now) == 0
        var parts: [String] = []
        if today { parts.append(Format.agoLong(at, now: now)) }
        else if kind == .episode { parts.append(ScheduleWords.format("EEE, MMM d", at)) }
        else if Format.dayOffset(at, now: now) >= -6 { parts.append(Format.weekday(at)) }
        else { parts.append(Format.shortDay(at)) }
        switch kind {
        case .friendRequest:
            if let n = inCommon, n > 0 { parts.append("\(n) title\(n == 1 ? "" : "s") in common") }
        case .episode:
            if let e = entry, e.status.isActive || e.status == .hold {
                parts.append("you're on \(Format.grouped(e.progress))" + (e.title.total.map { " of \(Format.grouped($0))" } ?? ""))
            }
        case .sequel:
            if let note { parts.append(note) }
        default: break
        }
        return parts.joined(separator: " · ")
    }

    /// the page a tap opens
    var route: Route? {
        switch kind {
        case .friendRequest: return user.map { .user($0.username) }
        case .message: return target.map { .conversation($0) } ?? user.map { .user($0.username) }
        case .comment, .reply: return target.map { .activity($0) } ?? user.map { .user($0.username) }
        case .like:
            guard let target else { return title.map { .title($0.id) } }
            return subject == "activity" ? .activity(target) : .review(target)
        case .episode, .sequel, .release: return title.map { .title($0.id) }
        }
    }

    /// a person leads the row (avatar); title news leads with the poster
    var leadsWithPerson: Bool {
        switch kind {
        case .friendRequest, .message, .comment, .like, .reply: return true
        case .episode, .sequel, .release: return false
        }
    }

    /// a small poster on the right (likes on a review show what was reviewed)
    var showsThumb: Bool { kind == .like && title != nil }
}

extension APIClient {
    func notifications() async throws -> NotificationFeed { try await get("notifications") }

    func markNotificationsRead() async throws -> OKReply { try await send("POST", "notifications/read") }
    // friend requests are answered with answerFriendRequest(_:accept:) from Social.swift (the same call)
}
