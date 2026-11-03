import Foundation

// The sheets over a title page (18, 19, 26, 27, 53): the list editor's draft and what it saves, the custom lists to
// tick, a review to post and a title to send to friends. Drawing is in mobile/ios/Sources/Sheets; everything here is
// plain logic, tested on Linux (SheetsTests.swift).

enum TitleSheets {
    // MARK: the title a sheet is about

    /// The bit of `GET titles/<id>` a sheet needs when the title isn't on your list (the title page's own models
    /// live with the title page; this decodes only its "title").
    struct TitleLookup: Decodable, Sendable {
        var title: Title
    }

    /// "Anime · 11 episodes · Fall 2026" under a title in the send-to sheet
    static func summary(_ t: Title) -> String {
        var parts = [t.media.singular]
        if let total = t.total, total > 0, t.media != .movie { parts.append(t.media.units(total)) }
        if let s = t.season { parts.append(s) } else if let y = t.year { parts.append(String(y)) }
        return parts.joined(separator: " · ")
    }

    // MARK: scores (the 10-point row)

    /// a 0-100 score as the 10-point row's chosen dot: 80 -> 8, 85 -> 9 (rounds half up), nil when unscored
    static func scoreDot(_ score: Int?) -> Int? {
        guard let score, score > 0 else { return nil }
        return min(10, max(1, Int((Double(score) / 10).rounded())))
    }

    /// tapping dot n: picks n (stored as n×10), or clears the score when n is already the chosen one
    static func pick(_ n: Int, current: Int?) -> Int? {
        scoreDot(current) == n ? nil : min(10, max(1, n)) * 10
    }

    // MARK: the list editor (18, 19)

    /// A copy of a library entry being edited. Nothing changes until ✓ (`patch` then goes to `model.change` in one
    /// go); ✕ drops it. The rules follow the website: starting sets the started date, finishing the last episode
    /// completes it, completing fills progress and the finished date.
    struct EditorDraft: Equatable, Sendable {
        /// the entry as it was (nil when the title isn't on your list yet)
        let original: LibraryEntry?
        let title: Title
        var status: ListStatus
        var progress: Int
        var volume: Int?
        var season: Int?
        var score: Int?
        var repeats: Int
        var started: String?
        var finished: String?
        var notes: String
        var favourite: Bool

        init(entry e: LibraryEntry) {
            original = e
            title = e.title
            status = e.status
            progress = e.progress
            volume = e.volume
            season = e.season
            score = e.score
            repeats = e.repeats
            started = e.started
            finished = e.finished
            notes = e.notes
            favourite = e.favourite
        }

        /// a title that isn't on the list: it goes on as Plan to Watch unless you pick something else
        init(title t: Title) {
            original = nil
            title = t
            status = .planned
            progress = 0
            volume = nil
            season = nil
            score = nil
            repeats = 0
            started = nil
            finished = nil
            notes = ""
            favourite = false
        }

        var media: MediaKind { title.media }
        var total: Int? { title.total.flatMap { $0 > 0 ? $0 : nil } }
        var isNew: Bool { original == nil }
        /// films have no progress (watched or not)
        var hasProgress: Bool { media.unit != nil }

        /// "Episode", "Chapter", "Page"
        var unitWord: String { (media.unit ?? "").capitalized }

        /// "Episode 6 of 11" (or "Episode 6" while the total isn't known)
        var progressCaption: String {
            let n = "\(unitWord) \(Format.grouped(progress))"
            return total.map { n + " of \(Format.grouped($0))" } ?? n
        }

        /// "Ep 7 airs Fri" next to Progress (the next episode's day; a date when it's over a week away)
        var nextLine: String? {
            guard let next = title.next, next.at > Clock.now else { return nil }
            let days = Format.dayOffset(next.at)
            let when = days == 0 ? "today" : days == 1 ? "tomorrow" : days < 7 ? Format.weekday(next.at)
                : Format.shortDay(next.at)
            return "\(media.unitShort) \(next.episode) airs \(when)"
        }

        var canStepDown: Bool { progress > 0 }
        var canStepUp: Bool { total.map { progress < $0 } ?? true }

        mutating func setStatus(_ s: ListStatus, today: String = Format.day(Clock.now)) {
            status = s
            switch s {
            case .completed:
                if let total, hasProgress { progress = max(progress, total) }
                if !hasProgress { progress = max(progress, 1) }
                if finished == nil { finished = today }
            case .current, .repeating:
                if started == nil { started = today }
            default:
                break
            }
        }

        mutating func setProgress(_ n: Int, today: String = Format.day(Clock.now)) {
            progress = max(0, total.map { min(n, $0) } ?? n)
            if status == .planned, progress > 0 {
                status = .current
                if started == nil { started = today }
            }
            if let total, progress == total, status.isActive {
                status = .completed
                if finished == nil { finished = today }
            }
        }

        /// − / +: one episode or chapter, ten pages for books
        mutating func step(_ direction: Int, today: String = Format.day(Clock.now)) {
            setProgress(progress + direction * media.step, today: today)
        }

        mutating func pickScore(_ n: Int) { score = TitleSheets.pick(n, current: score) }

        var scoreDot: Int? { TitleSheets.scoreDot(score) }

        /// "8" for the "★ 8 / 10" next to Your score
        var scoreText: String? { score.map { Format.score10($0) } }

        mutating func stepRepeats(_ d: Int) { repeats = max(0, repeats + d) }
        mutating func stepVolume(_ d: Int) {
            let v = max(0, (volume ?? 0) + d)
            volume = title.volumes.map { min(v, $0) } ?? v
        }
        mutating func stepSeason(_ d: Int) { season = max(1, (season ?? 1) + d) }

        /// what ✓ sends: only what changed (a new title sends its status and anything set)
        var patch: LibraryPatch {
            var p = LibraryPatch()
            guard let o = original else {
                p.status = status
                if progress > 0 { p.progress = progress }
                p.volume = volume
                p.season = season
                p.score = score
                if repeats > 0 { p.repeats = repeats }
                p.started = started
                p.finished = finished
                if !notes.isEmpty { p.notes = notes }
                if favourite { p.favourite = true }
                return p
            }
            if progress != o.progress {
                p.progress = progress
                // said outright so the server doesn't apply its own finishing rule over the choice made here
                p.status = status
            }
            if status != o.status { p.status = status }
            if volume != o.volume, let volume { p.volume = volume }
            if season != o.season, let season { p.season = season }
            if score != o.score { p.score = score ?? -1 }
            if repeats != o.repeats { p.repeats = repeats }
            if started != o.started { p.started = started ?? "" }
            if finished != o.finished { p.finished = finished ?? "" }
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != o.notes.trimmingCharacters(in: .whitespacesAndNewlines) { p.notes = trimmed }
            if favourite != o.favourite { p.favourite = favourite }
            return p
        }

        var hasChanges: Bool { isNew || !patch.isEmpty }

        /// "Sep 26, 2026" for a stored "2026-09-26"
        static func dateText(_ day: String?) -> String? {
            day.flatMap(Format.parseDay).map(Format.longDay)
        }

        /// ✓: the patch through the offline library (nothing when nothing changed). Returns whether it saved.
        @MainActor @discardableResult
        func save(to model: AppModel) -> Bool {
            guard hasChanges else { return false }
            model.change(title.id, patch, title: title)
            return true
        }

        /// Remove from list
        @MainActor
        func remove(from model: AppModel) {
            guard original != nil else { return }
            model.change(title.id, LibraryPatch(remove: true))
        }
    }

    // MARK: add to a custom list (26)

    /// The lists ticked for one title. Ticks are kept here until Done; Done sends one add or remove per list that
    /// changed, ✕ sends nothing.
    struct ListPicks: Equatable, Sendable {
        let titleId: String
        let lists: [CustomList]
        private(set) var ticked: Set<String>
        private let before: Set<String>

        init(titleId: String, lists: [CustomList]) {
            self.titleId = titleId
            self.lists = lists
            before = Set(lists.filter { l in l.items.contains { $0.title.id == titleId } }.map(\.id))
            ticked = before
        }

        func isOn(_ listId: String) -> Bool { ticked.contains(listId) }

        mutating func toggle(_ listId: String) {
            if ticked.contains(listId) { ticked.remove(listId) } else { ticked.insert(listId) }
        }

        /// the list's size with this title's tick counted in
        func count(_ list: CustomList) -> Int {
            list.items.count + (isOn(list.id) ? 1 : 0) - (before.contains(list.id) ? 1 : 0)
        }

        /// "12 titles · Public"
        func caption(_ list: CustomList) -> String {
            let n = count(list)
            return "\(Format.grouped(n)) title\(n == 1 ? "" : "s") · \(list.visibility.label)"
        }

        /// what Done sends: (list id, true to add / false to take out), in the lists' order
        var changes: [(listId: String, add: Bool)] {
            lists.compactMap { l in
                let now = ticked.contains(l.id), was = before.contains(l.id)
                return now == was ? nil : (l.id, now)
            }
        }
    }

    struct ListItemBody: Codable, Equatable, Sendable {
        var titleId: String
    }

    // MARK: write a review (27)

    static let reviewLimit = 5000

    struct ReviewDraft: Equatable, Sendable {
        var score: Int?
        var text = ""
        var spoilers = false
        var visibility: Visibility = .public

        var count: Int { text.count }
        /// "196 / 5,000"
        var countText: String { "\(Format.grouped(count)) / \(Format.grouped(TitleSheets.reviewLimit))" }
        var tooLong: Bool { count > TitleSheets.reviewLimit }
        var canPost: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tooLong
        }

        mutating func pickScore(_ n: Int) { score = TitleSheets.pick(n, current: score) }

        /// "9 / 10", or nil when unscored
        var scoreText: String? { score.map { "\(Format.score10($0)) / 10" } }

        var body: ReviewBody {
            ReviewBody(score: score, text: text.trimmingCharacters(in: .whitespacesAndNewlines), spoilers: spoilers,
                       visibility: visibility)
        }
    }

    struct ReviewBody: Codable, Equatable, Sendable {
        /// 0-100, nil when unscored
        var score: Int?
        var text: String
        var spoilers: Bool
        var visibility: Visibility
    }

    /// "Manga · Reading · Ch 97" under the title in the review sheet (status and progress from your list)
    static func reviewLine(_ t: Title, entry: LibraryEntry?) -> (kind: String, status: ListStatus?, progress: String?) {
        guard let e = entry else { return (t.kindLine, nil, nil) }
        let p: String?
        if t.media == .movie || e.progress == 0 {
            p = nil
        } else if t.media == .book {
            p = "p. \(Format.grouped(e.progress))"
        } else {
            p = "\(t.media.unitShort) \(Format.grouped(e.progress))"
        }
        return (t.media.singular, e.status, p)
    }

    // MARK: send to friends (53)

    /// GET send-to: the friends to offer, most recently talked to first
    struct SendToPage: Codable, Equatable, Sendable {
        var friends: [UserRef]
    }

    struct SendToBody: Codable, Equatable, Sendable {
        var titleId: String
        var to: [String]
        var message: String?
    }

    /// The friends picked to send a title to, in the order they show.
    struct SendPicks: Equatable, Sendable {
        var picked: [String] = []
        var message = ""
        var query = ""

        func isOn(_ username: String) -> Bool { picked.contains(username) }

        mutating func toggle(_ username: String) {
            if let i = picked.firstIndex(of: username) { picked.remove(at: i) } else { picked.append(username) }
        }

        var canSend: Bool { !picked.isEmpty }

        /// "Send 2"
        var sendLabel: String { picked.isEmpty ? "Send" : "Send \(picked.count)" }

        /// the friends matching the search (name or username), all of them without one
        func shown(_ friends: [UserRef]) -> [UserRef] {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return friends }
            return friends.filter { $0.username.lowercased().contains(q) || $0.name.lowercased().contains(q) }
        }

        func body(_ titleId: String, friends: [UserRef]) -> SendToBody {
            let order = friends.map(\.username)
            let to = picked.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return SendToBody(titleId: titleId, to: to, message: m.isEmpty ? nil : m)
        }
    }
}

extension APIClient {
    /// a title that isn't on your list, for a sheet over its page
    func sheetTitle(_ id: String) async throws -> Title {
        let page: TitleSheets.TitleLookup = try await get("titles/" + id)
        return page.title
    }

    /// POST lists/<id>/items {titleId} adds a title to a custom list; DELETE lists/<id>/items/<titleId> takes it out
    func sheetPickList(_ listId: String, titleId: String, on: Bool) async throws -> OKReply {
        if on { return try await send("POST", "lists/\(listId)/items", TitleSheets.ListItemBody(titleId: titleId)) }
        return try await send("DELETE", "lists/\(listId)/items/\(titleId)")
    }

    /// POST titles/<id>/reviews: your review of a title
    func sheetPostReview(_ titleId: String, _ body: TitleSheets.ReviewBody) async throws -> OKReply {
        try await send("POST", "titles/\(titleId)/reviews", body)
    }

    /// GET send-to: friends to send a title to
    func sheetSendToFriends() async throws -> TitleSheets.SendToPage { try await get("send-to") }

    /// POST send-to: a title to friends (it arrives in their messages)
    func sheetSendTitle(_ body: TitleSheets.SendToBody) async throws -> OKReply { try await send("POST", "send-to", body) }
}
