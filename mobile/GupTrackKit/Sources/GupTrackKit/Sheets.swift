import Foundation

// The sheets over a title page (18, 19, 26, 27, 53): the list editor's draft and what it saves, the custom lists to
// tick, a review to post and a title to send to friends. Drawing is in mobile/ios/Sources/Sheets; everything here is
// plain logic, tested on Linux (SheetsTests.swift).

enum TitleSheets {
    // MARK: the title a sheet is about

    /// "titles/anime/210482" for "anime:210482", "titles/movie/603" for "movie:603" (the title page's address,
    /// docs/app-api.md §8.3; nil for an id that isn't "<kind>:<id>")
    static func path(_ titleId: String) -> String? {
        guard let k = TitleKey(titleId: titleId) else { return nil }
        return "titles/\(k.media.kind.rawValue)/\(k.id)"
    }

    /// The bit of `GET titles/:kind/:id` (`{ title: TitleDetail }`, src/catalog/detail.ts) a sheet needs when the
    /// title isn't on your list; the title page's own models live with the title page.
    struct TitleLookup: Decodable, Sendable {
        struct Ref: Decodable, Sendable {
            var kind: String
            var id: String
        }

        struct Detail: Decodable, Sendable {
            var ref: Ref
            var title: String
            var alt: [String]?
            var cover: String?
            var format: String?
            var year: Int?
            /// episodes, chapters or pages
            var count: Int?
            /// one episode's length (a film's whole length)
            var minutes: Int?
            var volumes: Int?
        }

        var title: Detail

        /// the title as the sheets show it
        func sheetTitle() -> Title? {
            let d = title
            guard let kind = MediaKind(rawValue: d.ref.kind) else { return nil }
            let alt = (d.alt ?? []).filter { !$0.isEmpty }
            return Title(id: TitleKey(media: kind.api, id: d.ref.id).titleId, media: kind, name: d.title,
                         subtitle: alt.isEmpty ? nil : alt.joined(separator: " · "), cover: d.cover.flatMap { URL(string: $0) },
                         format: d.format.flatMap { $0.isEmpty ? nil : $0 }, year: d.year, total: d.count,
                         volumes: d.volumes, runtime: ListEntry.runtime(d.minutes ?? 0, kind))
        }
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

        /// "Ep 7 airs Fri" next to Progress (the next episode's day; a date when it's over a week away). Only when the
        /// title carries its next episode: the library feed's entries don't (§7.1), so the editor shows none.
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

        /// what ✓ sends: only what changed (a new title sends its status and anything set)
        var patch: LibraryPatch {
            var p = LibraryPatch()
            guard let o = original else {
                p.status = status
                if progress > 0 { p.progress = progress }
                p.volume = volume
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

    /// The lists ticked for one title (`ListChoices` from GET titles/:kind/:id/lists). Ticks are kept here until
    /// Done; Done sends one add or take-off per list that changed, ✕ sends nothing.
    struct ListPicks: Equatable, Sendable {
        let titleId: String
        private(set) var choices: [ListWire.Choice]
        private(set) var ticked: Set<Int>
        private var before: Set<Int>

        init(titleId: String, choices: ListWire.Choices) {
            self.titleId = titleId
            self.choices = choices.lists
            before = Set(choices.lists.filter(\.has).map(\.id))
            ticked = before
        }

        func isOn(_ listId: Int) -> Bool { ticked.contains(listId) }

        mutating func toggle(_ listId: Int) {
            if ticked.contains(listId) { ticked.remove(listId) } else { ticked.insert(listId) }
        }

        /// a list just made with this title on it (New list in the sheet): on top, already ticked and saved
        mutating func made(_ id: Int, name: String) {
            guard !choices.contains(where: { $0.id == id }) else { return }
            choices.insert(ListWire.Choice(id: id, name: name, has: true), at: 0)
            before.insert(id)
            ticked.insert(id)
        }

        /// the list's size with this title's tick counted in; the size comes from the phone's copy of the list
        /// (ListChoices has only id, name and has), nil when the copy doesn't have it
        func count(_ choice: ListWire.Choice, list: CustomList?) -> Int? {
            guard let list else { return nil }
            let had = list.items.contains { $0.id == titleId }
            return list.items.count + (isOn(choice.id) && !had ? 1 : 0) - (!isOn(choice.id) && had ? 1 : 0)
        }

        /// "12 titles · Public" (from the phone's copy; nil when it doesn't have the list)
        func caption(_ choice: ListWire.Choice, list: CustomList?) -> String? {
            guard let list, let n = count(choice, list: list) else { return nil }
            return "\(Format.grouped(n)) title\(n == 1 ? "" : "s") · \(list.visibility.label)"
        }

        /// what Done sends: (list id, true to add / false to take off), in the lists' order
        var changes: [(listId: Int, add: Bool)] {
            choices.compactMap { c in
                let now = ticked.contains(c.id), was = before.contains(c.id)
                return now == was ? nil : (c.id, now)
            }
        }
    }

    // MARK: write a review (27)

    /// REVIEW_MAX (src/social/reviews.ts)
    static let reviewLimit = 10_000

    /// The review being written. The score isn't part of a review: a review shows the score from your list, so a
    /// changed score is saved to your list (only when the title is on it).
    struct ReviewDraft: Equatable, Sendable {
        var score: Int?
        var text = ""
        var spoilers = false

        var count: Int { text.count }
        /// "196 / 10,000"
        var countText: String { "\(Format.grouped(count)) / \(Format.grouped(TitleSheets.reviewLimit))" }
        var tooLong: Bool { count > TitleSheets.reviewLimit }
        var canPost: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !tooLong
        }

        mutating func pickScore(_ n: Int) { score = TitleSheets.pick(n, current: score) }

        /// "9 / 10", or nil when unscored
        var scoreText: String? { score.map { "\(Format.score10($0)) / 10" } }

        /// PUT titles/:kind/:id/review's body for a title
        func body(_ t: Title) -> ReviewBody {
            ReviewBody(body: text.trimmingCharacters(in: .whitespacesAndNewlines), spoiler: spoilers,
                       meta: .init(title: t.name, cover: t.cover.flatMap { $0.scheme == "https" ? $0.absoluteString : nil } ?? "",
                                   format: t.format ?? ""))
        }
    }

    /// `{ body (1–10000), spoiler, meta: { title, cover, format } }`
    struct ReviewBody: Codable, Equatable, Sendable {
        struct Meta: Codable, Equatable, Sendable {
            var title: String
            /// https or ""
            var cover: String
            var format: String
        }

        var body: String
        var spoiler: Bool
        var meta: Meta
    }

    /// The bits of `TitleReviews` (GET titles/:kind/:id/reviews) the sheet uses: your review so far, and who may see
    /// it (the lower of your profile's and the list's setting; set in Settings › Privacy, not here).
    struct MyReview: Decodable, Equatable, Sendable {
        struct Mine: Decodable, Equatable, Sendable {
            var body: String
            var spoiler: Bool
        }

        var mine: Mine?
        var visibility: WireVisibility
    }

    /// PUT's answer `{ review: Review }`: the sheet only needs to know it worked
    struct ReviewSaved: Decodable, Sendable {}

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

    /// `{ recipients: [{ person, canSend }] }` (GET messages/recipients): recent conversations first, then friends
    struct Recipients: Codable, Equatable, Sendable {
        var recipients: [Recipient]
    }

    struct Recipient: Codable, Equatable, Identifiable, Sendable {
        /// the bits of `Person` (src/social/types.ts) the sheet shows
        struct Person: Codable, Equatable, Sendable {
            var username: String
            /// "" when not set or not yours to see
            var name: String
            var avatar: String?
        }

        var person: Person
        var canSend: Bool

        var id: String { person.username }
        var username: String { person.username }
        /// GupTrack's own "/media/…" addresses stay relative; the image loader resolves them
        var avatarURL: URL? { person.avatar.flatMap { URL(string: $0) } }
    }

    /// POST conversations/:username/messages `{ body, card: { kind, id, mine } }`
    struct MessageBody: Codable, Equatable, Sendable {
        struct Card: Codable, Equatable, Sendable {
            /// the title's kind, singular ("anime", "movie")
            var kind: String
            var id: String
            /// true adds your status and score
            var mine: Bool
        }

        var body: String?
        var card: Card
    }

    /// the answer `{ message: Message }`: the sheet only needs to know it went
    struct MessageSent: Decodable, Sendable {}

    /// The people picked to send a title to, in the order they show.
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

        /// the people matching the search (name or username), all of them without one
        func shown(_ people: [Recipient]) -> [Recipient] {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return people }
            return people.filter { $0.username.lowercased().contains(q) || $0.person.name.lowercased().contains(q) }
        }

        /// who it goes to, in the sheet's order (only those who can be sent to)
        func to(_ people: [Recipient]) -> [String] {
            people.filter { $0.canSend && picked.contains($0.username) }.map(\.username)
        }

        /// the message each of them gets: the title as a card, with the words when there are any
        func body(_ titleId: String) -> MessageBody? {
            guard let k = TitleKey(titleId: titleId) else { return nil }
            let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return MessageBody(body: m.isEmpty ? nil : String(m.prefix(4000)),
                               card: .init(kind: k.media.kind.rawValue, id: k.id, mine: false))
        }
    }
}

extension APIClient {
    /// GET titles/:kind/:id: a title that isn't on your list, for a sheet over its page
    func sheetTitle(_ titleId: String) async throws -> Title {
        guard let path = TitleSheets.path(titleId) else { throw APIError.server(404, "not_found", "No such title.") }
        let page: TitleSheets.TitleLookup = try await get(path)
        guard let t = page.sheetTitle() else { throw APIError.unreadable }
        return t
    }

    /// GET titles/:kind/:id/lists: your lists, and which have this title
    func listChoices(_ titleId: String) async throws -> ListWire.Choices {
        guard let path = TitleSheets.path(titleId) else { throw APIError.server(404, "not_found", "No such title.") }
        return try await get(path + "/lists")
    }

    /// GET titles/:kind/:id/reviews, for your review so far and who may see it
    func myReview(_ titleId: String) async throws -> TitleSheets.MyReview {
        guard let path = TitleSheets.path(titleId) else { throw APIError.server(404, "not_found", "No such title.") }
        return try await get(path + "/reviews")
    }

    /// PUT titles/:kind/:id/review: writes or replaces yours
    func putReview(_ titleId: String, _ body: TitleSheets.ReviewBody) async throws {
        guard let path = TitleSheets.path(titleId) else { throw APIError.server(404, "not_found", "No such title.") }
        let _: TitleSheets.ReviewSaved = try await send("PUT", path + "/review", body)
    }

    /// GET messages/recipients: who to send a title to
    func recipients() async throws -> TitleSheets.Recipients { try await get("messages/recipients") }

    /// POST conversations/:username/messages (with an X-Request-Id, so a resend doesn't send it twice)
    func sendMessage(to username: String, _ body: TitleSheets.MessageBody, requestId: String? = nil) async throws {
        let _: TitleSheets.MessageSent = try await send("POST", "conversations/\(username)/messages", body,
                                                        requestId: requestId)
    }
}
