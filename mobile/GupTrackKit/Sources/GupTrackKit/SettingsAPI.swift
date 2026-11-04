import Foundation
import Observation

// Settings (55-64b) on the app API (docs/app-api.md §4.4, §5, §11.5, §12): the account's settings as the pages edit
// them (GET me + GET settings/privacy + GET settings/messages), saved per endpoint with only what changed, and the
// pages with their own data: account, connected apps, import, export, backups, the owner's accounts. Everything
// that isn't drawing lives here so it's tested on Linux (SettingsTests.swift).

// MARK: choices the website takes (src/settings/prefs.ts, src/social/types.ts)

enum SettingsChoices {
    static let titleLanguages: [(String, String)] = [("english", "English"), ("romaji", "Romaji"), ("native", "Native")]
    static let weekStarts: [(String, String)] = [("sunday", "Sunday"), ("monday", "Monday")]
    /// Prefs.notify.lists: which titles' releases to tell you about
    static let notifyLists: [(String, String)] = [("watching", "Watching"), ("planning", "Watching and planning")]
    /// CommentSetting (who may comment on your profile)
    static let comments: [(String, String)] = [("everyone", "Everyone signed in"), ("friends", "Friends"),
                                               ("nobody", "No one")]
    /// who may message you (§11.5)
    static let messages: [(String, String)] = [("everyone", "Everyone signed in"), ("friends", "Friends"),
                                               ("nobody", "No one")]

    static func label(_ value: String, in choices: [(String, String)]) -> String {
        choices.first { $0.0 == value }?.1 ?? value
    }
}

/// How scores show (Prefs.scoreFormat; the website keeps 0-100).
enum ScoreFormat: String, CaseIterable, Identifiable, Sendable {
    case point10 = "10", point10Decimal = "10.0", point100 = "100", stars5 = "5", smiley3 = "3"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .point10: return "10 point"
        case .point10Decimal: return "10 point decimal"
        case .point100: return "100 point"
        case .stars5: return "5 star"
        case .smiley3: return "3 point smiley"
        }
    }

    /// a 0-100 score in this format: 85 -> "8", "8.5", "85", "★★★★☆", "🙂"
    func show(_ score: Int) -> String {
        let s = max(0, min(100, score))
        switch self {
        case .point10: return String(s / 10)
        case .point10Decimal: return Format.trim(Double(s) / 10)
        case .point100: return String(s)
        case .stars5:
            let n = max(0, min(5, Int((Double(s) / 20).rounded())))
            return String(repeating: "★", count: n) + String(repeating: "☆", count: 5 - n)
        case .smiley3: return s >= 70 ? "🙂" : s >= 40 ? "😐" : "🙁"
        }
    }

    static let exampleScore = 85
    var example: String { show(Self.exampleScore) }
}

/// Prefs.dateFormat
enum DateStyle: String, CaseIterable, Identifiable, Sendable {
    case mdy, dmy, mdyNum = "mdy-num", dmyNum = "dmy-num", iso
    var id: String { rawValue }

    private var pattern: String {
        switch self {
        case .mdy: return "MMM d, yyyy"
        case .dmy: return "d MMM yyyy"
        case .mdyNum: return "MM/dd/yyyy"
        case .dmyNum: return "dd/MM/yyyy"
        case .iso: return "yyyy-MM-dd"
        }
    }

    /// "Nov 3, 2026", "3 Nov 2026", "11/03/2026", "03/11/2026", "2026-11-03"
    func show(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = Clock.zone
        f.dateFormat = pattern
        return f.string(from: d)
    }
}

// MARK: privacy (§12.3) and messages (§11.5)

/// GET settings/privacy
struct PrivacySettings: Codable, Equatable, Sendable {
    var visibility: WireVisibility
    /// per list, keyed by the API's plural media ("movies")
    var lists: [String: WireVisibility]
    /// CommentSetting: "friends" | "everyone" | "nobody"
    var comments: String

    func list(_ m: APIMedia) -> WireVisibility { lists[m.rawValue] ?? visibility }
}

/// PUT settings/privacy/visibility: the profile's, or one list's with `media`
struct VisibilityBody: Codable, Equatable, Sendable {
    var visibility: WireVisibility
    var media: APIMedia?
}

/// what PUT settings/privacy/visibility answers (the server leaves `comments` out)
struct VisibilityAnswer: Codable, Equatable, Sendable {
    var visibility: WireVisibility
    var lists: [String: WireVisibility]
}

/// PUT settings/privacy/comments, and its answer
struct CommentSettingBody: Codable, Equatable, Sendable { var setting: String }

/// GET / PUT settings/messages: who may message you ("everyone" | "friends" | "nobody")
struct SettingsMessages: Codable, Equatable, Sendable { var messages: String }

/// PATCH settings/prefs's answer
struct PrefsAnswer: Codable, Equatable, Sendable { var prefs: Prefs }

// MARK: the account's settings

/// Everything the settings pages edit: GET me's account, profile and preferences, plus privacy and who may message.
struct AccountSettings: Equatable, Sendable {
    var me: Me
    var profile: Profile
    var prefs: Prefs
    var privacy: PrivacySettings
    /// who may message you
    var messages: String

    var isOwner: Bool { me.role == "owner" }
    var roleLabel: String { isOwner ? "Owner" : "Member" }
    var joined: Date { Millis.date(profile.joined) }
    /// the name shown (the username until one is set)
    var displayName: String { profile.name.isEmpty ? me.username : profile.name }

    /// the profile picture as the answer gave it ("/media/…" stays relative: the image loader resolves it)
    var avatar: URL? { profile.avatar.flatMap { $0.isEmpty ? nil : URL(string: $0) } }

    /// "Owner · Joined Sep 8, 2025"
    var accountLine: String { "\(roleLabel) · Joined \(Format.longDay(joined))" }

    /// the bio with its banner (an empty one until something's written)
    var bio: BioState {
        get { BioState(profile.bio) }
        set { profile.bio = newValue.json }
    }

    var theme: SettingsThemes.Look? { SettingsThemes.look(prefs.theme) }
    var scoreFormat: ScoreFormat { ScoreFormat(rawValue: prefs.scoreFormat) ?? .point10Decimal }
    var dateStyle: DateStyle { DateStyle(rawValue: prefs.dateFormat) ?? .mdy }

    /// the calls that take `old` to `new`, each with only what changed
    static func changes(from old: AccountSettings, to new: AccountSettings) -> [SettingsChange] {
        var out: [SettingsChange] = []
        if old.prefs != new.prefs, let a = try? JSONValue(encoding: old.prefs), let b = try? JSONValue(encoding: new.prefs),
           let d = JSONValue.diff(a, b) {
            out.append(.prefs(d))
        }
        var p = ProfilePatch()
        if old.profile.name != new.profile.name { p.name = new.profile.name }
        if old.profile.bio != new.profile.bio { p.bio = new.profile.bio ?? .null }
        if p != ProfilePatch() { out.append(.profile(p)) }
        if old.privacy.visibility != new.privacy.visibility {
            out.append(.visibility(VisibilityBody(visibility: new.privacy.visibility)))
        }
        for m in APIMedia.allCases where old.privacy.list(m) != new.privacy.list(m) {
            out.append(.visibility(VisibilityBody(visibility: new.privacy.list(m), media: m)))
        }
        if old.privacy.comments != new.privacy.comments { out.append(.comments(new.privacy.comments)) }
        if old.messages != new.messages { out.append(.messages(new.messages)) }
        return out
    }
}

/// One save: PATCH settings/prefs, PATCH settings/profile, PUT settings/privacy/…, PUT settings/messages.
enum SettingsChange: Equatable, Sendable {
    case prefs(JSONValue)
    case profile(ProfilePatch)
    case visibility(VisibilityBody)
    case comments(String)
    case messages(String)
}

extension JSONValue {
    /// a Codable value as JSON (the API's encoding)
    init<T: Encodable>(encoding value: T) throws {
        self = try APIClient.decoder.decode(JSONValue.self, from: APIClient.encoder.encode(value))
    }

    /// back to a Codable value
    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try APIClient.decoder.decode(type, from: APIClient.encoder.encode(self))
    }

    var object: [String: JSONValue]? { if case .object(let o) = self { return o } else { return nil } }
    var array: [JSONValue]? { if case .array(let a) = self { return a } else { return nil } }
    subscript(key: String) -> JSONValue? { object?[key] }

    /// what `new` changes from `old` (a PATCH body): objects recurse to the changed keys, anything else (arrays
    /// too) is replaced whole; nil when nothing changed
    static func diff(_ old: JSONValue, _ new: JSONValue) -> JSONValue? {
        guard case .object(let a) = old, case .object(let b) = new else { return old == new ? nil : new }
        var out: [String: JSONValue] = [:]
        for (k, v) in b {
            if let was = a[k] {
                if let d = diff(was, v) { out[k] = d }
            } else {
                out[k] = v
            }
        }
        for k in a.keys where b[k] == nil { out[k] = .null }
        return out.isEmpty ? nil : .object(out)
    }

    /// the same object with `more`'s keys laid over it, objects merged key by key
    func merged(with more: JSONValue?) -> JSONValue {
        guard case .object(var a) = self, case .object(let b)? = more else { return more ?? self }
        for (k, v) in b { a[k] = (a[k] ?? .null).merged(with: v) }
        return .object(a)
    }
}

// MARK: the shared copy the settings pages edit

/// The account's settings as the pages see them: loaded once, edited locally at once, sent a moment later as the
/// calls for what changed. Settings, its pages and the bio editor share it, so the root's values ("Midnight") and
/// the banner preview follow every edit.
@Observable @MainActor
final class AccountSettingsStore {
    static let shared = AccountSettingsStore()

    /// as shown (with local edits)
    var settings: AccountSettings?
    /// as the server last had it
    private(set) var saved: AccountSettings?
    /// whose settings these are (a different account loads again)
    private(set) var owner: String?
    private var pendingSave: Task<Void, Never>?

    init() {}

    func loaded(_ s: AccountSettings, for username: String?) {
        settings = s
        saved = s
        owner = username
    }

    func needsLoad(for username: String?) -> Bool { settings == nil || owner != username }

    /// change something now; `save` sends it
    func edit(_ change: (inout AccountSettings) -> Void) {
        guard var s = settings else { return }
        change(&s)
        settings = s
    }

    /// what would be sent (empty: nothing changed)
    var pendingChanges: [SettingsChange] {
        guard let saved, let settings else { return [] }
        return AccountSettings.changes(from: saved, to: settings)
    }

    /// a profile the server answered with (a picture upload): shown and saved at once
    func took(_ profile: Profile) {
        saved?.profile = profile
        settings?.profile = profile
    }

    /// send what changed, one call per endpoint; on failure the edits not sent stay and the error comes back
    func save(using api: APIClient) async throws {
        guard let sent = settings, var base = saved else { return }
        for change in AccountSettings.changes(from: base, to: sent) {
            switch change {
            case .prefs(let body):
                let a = try await api.updatePrefs(body)
                base.prefs = a.prefs
                if settings?.prefs == sent.prefs { settings?.prefs = a.prefs }
            case .profile(let patch):
                let a = try await api.updateProfile(patch)
                base.profile = a.profile
                if settings?.profile == sent.profile { settings?.profile = a.profile }
            case .visibility(let body):
                let a = try await api.setVisibility(body)
                base.privacy.visibility = a.visibility
                base.privacy.lists = a.lists
            case .comments(let setting):
                base.privacy.comments = try await api.setCommentSetting(setting).setting
            case .messages(let who):
                base.messages = try await api.setSettingsMessages(who).messages
            }
            saved = base
        }
    }

    /// edit, then send after `delay` seconds without another edit (sliders, typing)
    func edit(_ change: (inout AccountSettings) -> Void, send: @escaping @MainActor () async -> Void,
              delay: Double = 0.5) {
        edit(change)
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await send()
        }
    }
}

/// The root page's values that come from other calls: the connected apps, the latest backup, the accounts.
struct SettingsSummary: Equatable, Sendable {
    var devices: DeviceList?
    var lastBackup: Date?
    var accounts: Int?

    /// the other apps' names ("Harbor"), nil when there are none
    var connectedValue: String? {
        guard let d = devices else { return nil }
        var names: [String] = []
        for x in d.devices where x.id != d.current && !names.contains(x.app) { names.append(x.app) }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var backupValue: String? { lastBackup.map { SettingsText.dayName($0) } }
}

// MARK: the bio (BioState, src/components/profile/bio/types.ts)

/// The bio and its banner as the website keeps it: the look (`style`), the banner with its fade, and the Tiptap
/// document. Missing keys take the website's defaults (`emptyBio`, src/settings/profile.ts).
struct BioState: Codable, Equatable, Sendable {
    var style: BioStyle
    var banner: BioBanner
    /// Tiptap JSON ({type: "doc", content: [...]}); BioDocument edits it
    var doc: JSONValue

    static let emptyDoc: JSONValue = .object(["type": .string("doc"), "content": .array([.object(["type": .string("paragraph")])])])

    static var empty: BioState {
        BioState(style: .standard, banner: BioBanner(), doc: emptyDoc)
    }

    /// a Profile's bio (null: the empty one)
    init(_ json: JSONValue?) {
        let defaults = (try? JSONValue(encoding: BioState.empty)) ?? .null
        let given = (json?.isNull ?? true) ? nil : json
        self = (try? defaults.merged(with: given).decoded(BioState.self)) ?? .empty
        if let doc = given?["doc"] { self.doc = doc }
    }

    init(style: BioStyle, banner: BioBanner, doc: JSONValue) {
        self.style = style
        self.banner = banner
        self.doc = doc
    }

    var json: JSONValue { (try? JSONValue(encoding: self)) ?? .null }
}

/// BioStyle: the bio's type and layout (src/components/profile/bio/style.ts)
struct BioStyle: Codable, Hashable, Sendable {
    var bodyFont = "site"
    var headingFont = "site"
    /// s | m | l
    var size = "m"
    /// tight | normal | airy
    var spacing = "normal"
    /// plain | rule | accent | quiet
    var headings = "plain"
    var accent = "brand"
    /// reading | wide
    var measure = "reading"
    /// left | center
    var align = "left"
    /// none | line | panel
    var frame = "none"
    /// none | short | tall
    var collapse = "none"

    static let standard = BioStyle()
}

/// BioBanner: the banner picture, where it sits, and its fade
struct BioBanner: Codable, Equatable, Sendable {
    /// "/media/…" (an upload, left relative: the image loader resolves it on the server) or an https address
    /// (a title's art); nil: no banner
    var src: URL?
    var posX: Double = 50
    var posY: Double = 50
    var zoom: Double = 1
    var aspect: Double = 6.5
    var fade = BannerFade()

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(src?.relativeString, forKey: .src)   // null, not left out: the website reads null as "no banner"
        try c.encode(posX, forKey: .posX)
        try c.encode(posY, forKey: .posY)
        try c.encode(zoom, forKey: .zoom)
        try c.encode(aspect, forKey: .aspect)
        try c.encode(fade, forKey: .fade)
    }
}

/// BannerFade (src/components/profile/bio/fade.ts)
struct BannerFade: Codable, Equatable, Sendable {
    var on = true
    /// 0-100
    var strength: Double = 74
    /// "dark" | "page"
    var color = "dark"
    /// how the name stays readable: "auto" | "shadow" | "backing" | "none"
    var text = "auto"

    static let colors: [(String, String)] = [("dark", "Dark"), ("page", "Page colour")]
    static let texts: [(String, String)] = [("auto", "Auto"), ("shadow", "Shadow"), ("backing", "Backing"),
                                            ("none", "None")]
}

/// The website's bio presets (src/components/profile/bio/presets.ts). On the website a preset also swaps in a
/// starter document; the app applies only its look and keeps what you wrote.
enum BioPreset: String, CaseIterable, Identifiable, Sendable {
    case ledger, editorial, shelf, index, letter, topTen = "top-ten", credits, marquee, notebook, quiet
    var id: String { rawValue }

    var label: String {
        switch self {
        case .ledger: return "Ledger"
        case .editorial: return "Editorial"
        case .shelf: return "Shelf"
        case .index: return "Index"
        case .letter: return "Letter"
        case .topTen: return "Top Ten"
        case .credits: return "Credits"
        case .marquee: return "Marquee"
        case .notebook: return "Notebook"
        case .quiet: return "Quiet"
        }
    }

    var style: BioStyle {
        var s = BioStyle.standard
        func set(_ body: String? = nil, _ heading: String? = nil, headings: String, size: String = "m",
                 spacing: String = "normal", measure: String = "reading", align: String = "left", frame: String = "none") {
            if let body { s.bodyFont = body }
            if let heading { s.headingFont = heading }
            s.headings = headings
            s.size = size
            s.spacing = spacing
            s.measure = measure
            s.align = align
            s.frame = frame
        }
        switch self {
        case .ledger: set("inter", "inter", headings: "rule", measure: "wide")
        case .editorial: set("lora", "fraunces", headings: "plain", size: "l", spacing: "airy")
        case .shelf: set(headings: "quiet", measure: "wide")
        case .index: set("inter", "jetbrains", headings: "quiet", size: "s", spacing: "tight", measure: "wide")
        case .letter: set("lora", "lora", headings: "plain", size: "l", frame: "panel")
        case .topTen: set("inter", "space-grotesk", headings: "accent")
        case .credits: set("inter", "playfair", headings: "plain", spacing: "airy", align: "center")
        case .marquee: set("inter", "playfair", headings: "plain", measure: "wide")
        case .notebook: set("inter", "caveat", headings: "plain", frame: "line")
        case .quiet: set(headings: "quiet")
        }
        return s
    }

    /// the preset a style is, if it is one
    static func matching(_ style: BioStyle) -> BioPreset? { allCases.first { $0.style == style } }
}

/// A list block in the bio (`listBlock`, ListBlockAttrs in src/components/profile/bio/types.ts). The attributes are
/// kept whole, so the website's own settings (layout, size, hand-picked items) survive an edit on the phone.
struct BioList: Equatable, Sendable {
    var attrs: [String: JSONValue]

    /// "current" | "completed" | "planned" | "favourites" | "top" | "characters" | "people" | "studios" |
    /// "authors" | "custom"
    var source: String { attrs["source"]?.string ?? "current" }
    /// an APIMedia or "all"
    var media: String { attrs["media"]?.string ?? "all" }
    var layout: String { attrs["layout"]?.string ?? "grid" }
    var count: Int { attrs["count"]?.int ?? 8 }

    /// the website's defaultListAttrs with a source and media
    static func make(source: String, media: APIMedia?) -> BioList {
        BioList(attrs: [
            "source": .string(source), "media": .string(media?.rawValue ?? "all"), "layout": .string("grid"),
            "size": .string("m"), "count": .number(8), "showScore": .bool(false), "showProgress": .bool(true),
            "showTitles": .bool(true), "showHeading": .bool(true), "heading": .string(""), "items": .array([]),
        ])
    }

    /// the sources the app can fill from your library
    static let titleSources: [(String, String)] = [("current", "Currently watching or reading"),
                                                   ("completed", "Recently completed"), ("planned", "Up next"),
                                                   ("favourites", "Favourite titles"), ("top", "Top rated")]

    var showsTitles: Bool { Self.titleSources.contains { $0.0 == source } }

    /// "cover" layouts show posters; the others lines of text
    var showsCovers: Bool { ["grid", "strip", "scroller", "cards"].contains(layout) }

    /// the heading it shows: your own, or the website's defaultHeading
    var heading: String {
        if let h = attrs["heading"]?.string, !h.trimmingCharacters(in: .whitespaces).isEmpty { return h }
        let watch = ["anime": "anime", "manga": "manga", "tv": "shows", "movies": "movies", "books": "books"]
        let what = media == "all" ? "" : " " + (watch[media] ?? media)
        let reading = media == "manga" || media == "books"
        switch source {
        case "current": return media == "all" ? "Currently watching & reading" : reading ? "Currently reading" : "Currently watching"
        case "completed": return "Recently finished" + what
        case "planned": return "Up next"
        case "favourites": return media == "all" ? "Favourites" : "Favourite" + what
        case "top": return media == "all" ? "Top rated" : "Top rated" + what
        case "characters": return "Favourite characters"
        case "people": return "Favourite people"
        case "studios": return "Favourite studios"
        case "authors": return "Favourite authors"
        default: return "My picks"
        }
    }

    var showHeading: Bool { attrs["showHeading"]?.bool ?? true }

    /// the titles it shows, from the library on this phone (the profile's own copy comes from the server)
    func titles(_ library: [LibraryEntry]) -> [Title] {
        var pool = library
        if media != "all", let m = APIMedia(rawValue: media) { pool = pool.filter { $0.media == m.kind } }
        switch source {
        case "current": pool = pool.filter { $0.status == .current || $0.status == .repeating }
        case "completed": pool = pool.filter { $0.status == .completed }
        case "planned": pool = pool.filter { $0.status == .planned }
        case "favourites": pool = pool.filter(\.favourite)
        case "top": pool = pool.filter { ($0.score ?? 0) > 0 }.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
        default: return []
        }
        if source != "top" { pool.sort { $0.updatedAt > $1.updatedAt } }
        return pool.prefix(max(1, count)).map(\.title)
    }
}

/// The bio's document as the editor sees it: runs of plain text (paragraphs, headings, lists, quotes with bold,
/// italic and links) written as markdown lines, list blocks as cards, and anything the phone can't edit without
/// losing it (pictures, columns, sections, styled text) kept as it is and shown as a card you can remove.
struct BioDocument: Equatable, Sendable {
    enum Block: Equatable, Sendable {
        case text(String)
        case list(BioList)
        case kept(JSONValue)
    }

    var blocks: [Block]

    init(blocks: [Block]) { self.blocks = blocks }

    init(doc: JSONValue) {
        var out: [Block] = []
        var run: [JSONValue] = []
        func flush() {
            if !run.isEmpty { out.append(.text(BioMarkdown.markdown(run))) }
            run = []
        }
        for n in doc["content"]?.array ?? [] {
            if n["type"]?.string == "listBlock" {
                flush()
                out.append(.list(BioList(attrs: n["attrs"]?.object ?? [:])))
            } else if BioMarkdown.editable(n) {
                // two lists (or quotes) in a row would join up as one in markdown: a new text block keeps them apart
                if let last = run.last, BioMarkdown.joins(last, n) { flush() }
                run.append(n)
            } else {
                flush()
                out.append(.kept(n))
            }
        }
        flush()
        if case .text? = out.last {} else { out.append(.text("")) }
        blocks = out
    }

    /// back to Tiptap JSON; a last empty text block (where you'd type next) isn't written
    var doc: JSONValue {
        var bs = blocks
        if bs.count > 1, case .text("")? = bs.last { bs.removeLast() }
        var content: [JSONValue] = []
        for b in bs {
            switch b {
            case .text(let s): content += BioMarkdown.nodes(s)
            case .list(let l): content.append(.object(["type": .string("listBlock"), "attrs": .object(l.attrs)]))
            case .kept(let n): content.append(n)
            }
        }
        if content.isEmpty { content = [.object(["type": .string("paragraph")])] }
        return .object(["type": .string("doc"), "content": .array(content)])
    }

    /// put a list after block `index` (the one being edited), with an empty text block after it to type on
    mutating func insert(_ list: BioList, after index: Int?) {
        let at = min(blocks.count, (index ?? blocks.count - 1) + 1)
        blocks.insert(.list(list), at: at)
        if at + 1 >= blocks.count || { if case .text = blocks[at + 1] { return false } else { return true } }() {
            blocks.insert(.text(""), at: at + 1)
        }
    }

    mutating func remove(at index: Int) {
        guard blocks.indices.contains(index) else { return }
        blocks.remove(at: index)
        // two text blocks that meet join up
        if index > 0, index < blocks.count, case .text(let a) = blocks[index - 1], case .text(let b) = blocks[index] {
            blocks[index - 1] = .text([a, b].filter { !$0.isEmpty }.joined(separator: "\n"))
            blocks.remove(at: index)
        }
        if blocks.isEmpty { blocks = [.text("")] }
    }

    /// the bio's first words without markdown, for the Bio row ("Seasonal anime, slow manga")
    static func summary(_ doc: JSONValue) -> String {
        for n in doc["content"]?.array ?? [] {
            let s = BioMarkdown.plainText(n).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return ""
    }

    /// what a kept block is, for its card ("A picture", "Columns")
    static func keptLabel(_ n: JSONValue) -> String {
        switch n["type"]?.string {
        case "image": return "A picture"
        case "columns": return "Columns"
        case "section": return "A section"
        case "horizontalRule": return "A divider"
        default: return "Styled text"
        }
    }

    /// The formatting bar's buttons, applied to the text being edited (no selection on iPhone: they add to the end).
    enum Style: String, CaseIterable, Sendable {
        case bold, italic, heading, list, quote, link

        var symbol: String {
            switch self {
            case .bold: return "bold"
            case .italic: return "italic"
            case .heading: return "textformat.size"
            case .list: return "list.bullet"
            case .quote: return "text.quote"
            case .link: return "link"
            }
        }

        var label: String {
            switch self {
            case .bold: return "Bold"
            case .italic: return "Italic"
            case .heading: return "Heading"
            case .list: return "Bulleted list"
            case .quote: return "Quote"
            case .link: return "Link"
            }
        }

        func apply(_ text: String) -> String {
            var lines = text.components(separatedBy: "\n")
            let last = lines.last ?? ""
            func onLastLine(_ prefix: String) -> String {
                if last.hasPrefix(prefix) { lines[lines.count - 1] = String(last.dropFirst(prefix.count)) }
                else { lines[lines.count - 1] = prefix + Line(last).content }
                return lines.joined(separator: "\n")
            }
            func append(_ s: String) -> String {
                text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? text + s : text + " " + s
            }
            switch self {
            case .bold: return append("**bold**")
            case .italic: return append("*italic*")
            case .link: return append("[link](https://)")
            case .heading: return onLastLine("## ")
            case .quote: return onLastLine("> ")
            case .list: return text.isEmpty ? "- " : text + "\n- "
            }
        }
    }

    /// one line of bio markdown, for the preview
    struct Line: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case blank, heading1, heading2, heading3, bullet, numbered(Int), quote, rule, body }

        var kind: Kind
        /// the line without its block marker (inline markdown left in)
        var content: String

        init(_ raw: String) {
            let s = raw
            if s.trimmingCharacters(in: .whitespaces).isEmpty { kind = .blank; content = ""; return }
            if s == "---" { kind = .rule; content = ""; return }
            for (p, k) in [("### ", Kind.heading3), ("## ", .heading2), ("# ", .heading1), ("- ", .bullet), ("> ", .quote)]
            where s.hasPrefix(p) {
                kind = k
                content = String(s.dropFirst(p.count))
                return
            }
            if s == ">" { kind = .quote; content = ""; return }
            if let n = BioMarkdown.numbered(s) { kind = .numbered(n.0); content = n.1; return }
            kind = .body
            content = s
        }

        /// without any markdown: "**Frieren** every *Friday*" -> "Frieren every Friday"
        var plain: String {
            BioMarkdown.inline(content).map { $0["text"]?.string ?? "" }.joined()
        }
    }

    static func lines(_ text: String) -> [Line] { text.components(separatedBy: "\n").map(Line.init) }
}

/// Markdown lines <-> the Tiptap nodes they stand for. A node is editable as markdown only when writing it out and
/// reading it back gives the very same node, so nothing the website wrote is ever lost by editing on the phone.
enum BioMarkdown {
    private static func node(_ type: String, _ more: [String: JSONValue] = [:]) -> JSONValue {
        var o = more
        o["type"] = .string(type)
        return .object(o)
    }

    private static func block(_ type: String, attrs: [String: JSONValue]? = nil, _ content: [JSONValue]) -> JSONValue {
        var o: [String: JSONValue] = [:]
        if let attrs { o["attrs"] = .object(attrs) }
        if !content.isEmpty { o["content"] = .array(content) }
        return node(type, o)
    }

    /// "12. text" -> (12, "text")
    static func numbered(_ s: String) -> (Int, String)? {
        guard let dot = s.range(of: ". "), let n = Int(s[s.startIndex..<dot.lowerBound]), n >= 0,
              s[s.startIndex..<dot.lowerBound].allSatisfy(\.isNumber) else { return nil }
        return (n, String(s[dot.upperBound...]))
    }

    // MARK: markdown -> nodes

    static func nodes(_ text: String) -> [JSONValue] {
        var out: [JSONValue] = []
        var list: (type: String, items: [JSONValue])?
        var quote: [JSONValue]?
        func end() {
            if let l = list { out.append(block(l.type, l.items)) }
            if let q = quote { out.append(block("blockquote", attrs: ["variant": .string("bar")], q)) }
            list = nil
            quote = nil
        }
        for raw in text.components(separatedBy: "\n") {
            let line = DocLine(raw)
            switch line {
            case .bullet(let s), .ordered(let s):
                let type: String = { if case .bullet = line { return "bulletList" } else { return "orderedList" } }()
                if list?.type != type { end() }
                let item = block("listItem", [block("paragraph", inline(s))])
                list = (type, (list?.items ?? []) + [item])
            case .quote(let s):
                if quote == nil { end() }
                quote = (quote ?? []) + [block("paragraph", inline(s))]
            default:
                end()
                switch line {
                case .heading(let level, let s):
                    out.append(block("heading", attrs: ["level": .number(Double(level))], inline(s)))
                case .rule: out.append(block("horizontalRule", attrs: ["variant": .string("line")], []))
                case .paragraph(let s): out.append(block("paragraph", inline(s)))
                default: break
                }
            }
        }
        end()
        return out
    }

    private enum DocLine {
        case paragraph(String), heading(Int, String), bullet(String), ordered(String), quote(String), rule

        init(_ s: String) {
            if s == "---" { self = .rule; return }
            for level in [3, 2, 1] {
                let p = String(repeating: "#", count: level) + " "
                if s.hasPrefix(p) { self = .heading(level, String(s.dropFirst(p.count))); return }
            }
            if s.hasPrefix("- ") { self = .bullet(String(s.dropFirst(2))); return }
            if s.hasPrefix("> ") { self = .quote(String(s.dropFirst(2))); return }
            if s == ">" { self = .quote(""); return }
            if let n = BioMarkdown.numbered(s) { self = .ordered(n.1); return }
            self = .paragraph(s)
        }
    }

    /// inline markdown -> Tiptap text nodes: **bold**, *italic*, [text](https://…)
    static func inline(_ s: String) -> [JSONValue] {
        var out: [(String, [JSONValue])] = []
        parse(Array(s), marks: [], into: &out)
        // neighbours with the same marks are one text node
        var merged: [(String, [JSONValue])] = []
        for (t, m) in out where !t.isEmpty {
            if let last = merged.last, last.1 == m { merged[merged.count - 1].0 += t } else { merged.append((t, m)) }
        }
        return merged.map { t, m in
            var o: [String: JSONValue] = ["type": .string("text"), "text": .string(t)]
            if !m.isEmpty { o["marks"] = .array(m) }
            return .object(o)
        }
    }

    private static func find(_ c: [Character], _ token: String, from: Int, strict: Bool) -> Int? {
        let t = Array(token)
        var i = from
        while i + t.count <= c.count {
            if Array(c[i..<(i + t.count)]) == t {
                // a closing * that's part of ** (or *** for bold) belongs to the next marker
                if !strict || i + t.count >= c.count || c[i + t.count] != "*" { return i }
            }
            i += 1
        }
        return nil
    }

    private static func parse(_ c: [Character], marks: [JSONValue], into out: inout [(String, [JSONValue])]) {
        var plain = ""
        var i = 0
        func flush() { if !plain.isEmpty { out.append((plain, marks)); plain = "" } }
        while i < c.count {
            if c[i] == "*", i + 1 < c.count, c[i + 1] == "*", let close = find(c, "**", from: i + 3, strict: true) {
                flush()
                parse(Array(c[(i + 2)..<close]), marks: marks + [node("bold")], into: &out)
                i = close + 2
            } else if c[i] == "*", let close = find(c, "*", from: i + 2, strict: true) {
                flush()
                parse(Array(c[(i + 1)..<close]), marks: marks + [node("italic")], into: &out)
                i = close + 1
            } else if c[i] == "[", let mid = find(c, "](", from: i + 1, strict: false),
                      let close = find(c, ")", from: mid + 2, strict: false), close > mid + 2 {
                flush()
                let href = String(c[(mid + 2)..<close])
                parse(Array(c[(i + 1)..<mid]), marks: marks + [node("link", ["attrs": .object(["href": .string(href)])])],
                      into: &out)
                i = close + 1
            } else {
                plain.append(c[i])
                i += 1
            }
        }
        flush()
    }

    // MARK: nodes -> markdown

    /// the markdown lines for editable top-level nodes, one per line
    static func markdown(_ nodes: [JSONValue]) -> String {
        nodes.compactMap(lines).flatMap { $0 }.joined(separator: "\n")
    }

    /// a node's markdown lines; nil when it has something markdown here can't say
    static func lines(_ n: JSONValue) -> [String]? {
        let attrs = n["attrs"]?.object ?? [:]
        let kids = n["content"]?.array ?? []
        switch n["type"]?.string {
        case "paragraph":
            guard attrs.isEmpty, let s = inlineText(kids) else { return nil }
            return [s]
        case "heading":
            guard let level = attrs["level"]?.int, (1...3).contains(level), attrs.count == 1,
                  let s = inlineText(kids) else { return nil }
            return [String(repeating: "#", count: level) + " " + s]
        case "horizontalRule":
            return attrs["variant"]?.string ?? "line" == "line" ? ["---"] : nil
        case "bulletList", "orderedList":
            guard attrs.isEmpty, !kids.isEmpty else { return nil }
            var out: [String] = []
            for (i, item) in kids.enumerated() {
                guard item["type"]?.string == "listItem", item["attrs"] == nil, let p = item["content"]?.array, p.count == 1,
                      p[0]["type"]?.string == "paragraph", p[0]["attrs"] == nil,
                      let s = inlineText(p[0]["content"]?.array ?? []) else { return nil }
                out.append((n["type"]?.string == "bulletList" ? "- " : "\(i + 1). ") + s)
            }
            return out
        case "blockquote":
            guard attrs["variant"]?.string ?? "bar" == "bar", !kids.isEmpty else { return nil }
            var out: [String] = []
            for p in kids {
                guard p["type"]?.string == "paragraph", p["attrs"] == nil,
                      let s = inlineText(p["content"]?.array ?? []) else { return nil }
                out.append(s.isEmpty ? ">" : "> " + s)
            }
            return out
        default:
            return nil
        }
    }

    private static func inlineText(_ nodes: [JSONValue]) -> String? {
        var s = ""
        for n in nodes {
            guard n["type"]?.string == "text", var t = n["text"]?.string else { return nil }
            var bold = false, italic = false
            var href: String?
            for m in n["marks"]?.array ?? [] {
                switch m["type"]?.string {
                case "bold": bold = true
                case "italic": italic = true
                case "link": guard let h = m["attrs"]?["href"]?.string else { return nil }; href = h
                default: return nil
                }
            }
            if italic { t = "*\(t)*" }
            if bold { t = "**\(t)**" }
            if let href { t = "[\(t)](\(href))" }
            s += t
        }
        return s
    }

    /// whether a node can be edited as markdown without losing anything
    static func editable(_ n: JSONValue) -> Bool {
        guard let ls = lines(n) else { return false }
        let back = nodes(ls.joined(separator: "\n"))
        return back.count == 1 && normal(back[0]) == normal(n)
    }

    /// two nodes markdown would read as one (two lists, two quotes)
    static func joins(_ a: JSONValue, _ b: JSONValue) -> Bool {
        let t = a["type"]?.string
        return t == b["type"]?.string && ["bulletList", "orderedList", "blockquote"].contains(t ?? "")
    }

    /// for comparing: marks in one order, empty content left out
    static func normal(_ v: JSONValue) -> JSONValue {
        switch v {
        case .object(var o):
            if o["content"]?.array?.isEmpty == true { o["content"] = nil }
            for (k, x) in o { o[k] = normal(x) }
            if let marks = o["marks"]?.array {
                o["marks"] = .array(marks.sorted { ($0["type"]?.string ?? "") < ($1["type"]?.string ?? "") })
            }
            return .object(o)
        case .array(let a): return .array(a.map(normal))
        default: return v
        }
    }

    /// a node's words without formatting
    static func plainText(_ n: JSONValue) -> String {
        if let t = n["text"]?.string { return t }
        let parts = (n["content"]?.array ?? []).map(plainText)
        return parts.joined(separator: n["type"]?.string == "paragraph" ? "" : " ")
    }
}


// MARK: the account (§4.4)

/// GET account: Settings › Account (`AccountInfo`, src/auth/auth.functions.ts, plus the connected apps)
struct AccountInfo: Codable, Equatable, Sendable {
    struct Recovery: Codable, Equatable, Sendable {
        var total: Int
        var left: Int
        var createdAt: Int64?
        /// when a recovery code last set a new password
        var lastUsed: Int64?
    }

    var username: String
    var role: String
    var recovery: Recovery
    var sessions: [SessionInfo]
    /// added and removed on the website only
    var passkeys: [PasskeyInfo]
    var devices: [Device]
    var serverTime: Int64

    /// "8 of 10 left" / "None made yet"
    var recoveryLine: String {
        recovery.total == 0 ? "None made yet" : "\(recovery.left) of \(recovery.total) left"
    }

    /// "1 passkey" / "No passkeys"
    var passkeyLine: String {
        passkeys.isEmpty ? "No passkeys" : "\(passkeys.count) passkey\(passkeys.count == 1 ? "" : "s")"
    }
}

/// A browser signed in to the website (`SessionInfo`, src/auth/accounts.server.ts)
struct SessionInfo: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var createdAt: Int64
    var lastSeen: Int64
    var expiresAt: Int64
    var userAgent: String?
    var ip: String?
    /// the browser asking (never this phone: the app signs in with a device token, not a session)
    var current: Bool

    /// "Firefox on Linux", "Safari on iPhone", "A browser"
    var name: String {
        guard let ua = userAgent, !ua.isEmpty else { return "A browser" }
        let browser: String? = ua.contains("Firefox/") ? "Firefox" : ua.contains("Edg/") ? "Edge"
            : ua.contains("OPR/") ? "Opera" : ua.contains("Chrome/") ? "Chrome" : ua.contains("Safari/") ? "Safari" : nil
        let system: String? = ua.contains("iPhone") ? "iPhone" : ua.contains("iPad") ? "iPad"
            : ua.contains("Android") ? "Android" : ua.contains("Mac OS X") || ua.contains("Macintosh") ? "Mac"
            : ua.contains("Windows") ? "Windows" : ua.contains("CrOS") ? "ChromeOS" : ua.contains("Linux") ? "Linux" : nil
        switch (browser, system) {
        case let (b?, s?): return "\(b) on \(s)"
        case let (b?, nil): return b
        case let (nil, s?): return "A browser on \(s)"
        default: return "A browser"
        }
    }

    /// "Last seen 2 min ago"
    func seenLine(now: Date = Clock.now) -> String {
        "Last seen " + Format.agoLong(Millis.date(lastSeen), now: now)
    }
}

/// A passkey (`PasskeyInfo`): listed, not added, on the phone
struct PasskeyInfo: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String?
    var createdAt: Int64
    var deviceType: String
    var backedUp: Bool
}

/// POST account/password
struct PasswordBody: Codable, Equatable, Sendable {
    var current: String
    var next: String
}

/// POST account/recovery-codes
struct RecoveryCodesBody: Codable, Equatable, Sendable { var password: String }

/// the new recovery codes (shown once)
struct NewRecoveryCodes: Codable, Equatable, Sendable { var codes: [String] }

// MARK: connected apps (§4.4)

/// GET devices
struct DeviceList: Codable, Equatable, Sendable {
    var devices: [Device]
    /// this phone's id
    var current: Int

    var this: Device? { devices.first { $0.id == current } }
    var others: [Device] { devices.filter { $0.id != current } }
}

extension Device {
    /// Harbor connects with the "sync" scope
    var isHarbor: Bool { scope == "sync" }

    var symbol: String {
        if isHarbor { return "play.tv" }
        let p = platform.lowercased()
        if p.contains("ipad") { return "ipad" }
        if p.contains("mac") { return "laptopcomputer" }
        return "iphone"
    }

    /// "Harbor · Windows 11 · Used 3 hr ago"
    func caption(now: Date = Clock.now) -> String {
        var parts = [app, platform].filter { !$0.isEmpty }
        if let used = lastUsedAt { parts.append("Used " + Format.agoLong(Millis.date(used), now: now)) }
        else { parts.append("Connected " + SettingsText.shortDate(Millis.date(createdAt), now: now)) }
        return parts.joined(separator: " · ")
    }
}

/// POST devices/pairing: {"for": "harbor"} or {"for": "app"}
struct PairingBody: Codable, Equatable, Sendable {
    enum For: String, Codable, Sendable { case harbor, app }
    var target: For

    enum CodingKeys: String, CodingKey { case target = "for" }
}

/// A pairing code to connect Harbor or another phone from this one: type the code, or open the link
struct Pairing: Codable, Equatable, Sendable {
    /// "XXXX-XXXX"
    var code: String
    var expiresAt: Int64
    /// seconds it lasts
    var ttl: Int
    /// the address the other app connects to
    var server: String
    /// nuvio://auth/guptrack?… (Harbor) or guptrack://pair?… (an iPhone): the QR code
    var link: String

    var expires: Date { Millis.date(expiresAt) }

    /// "Works for 10 more minutes" / "This code has run out"
    func expiryLine(now: Date = Clock.now) -> String {
        let left = Int(expires.timeIntervalSince(now))
        if left <= 0 { return "This code has run out" }
        let minutes = (left + 59) / 60
        return "Works for \(minutes) more minute\(minutes == 1 ? "" : "s")"
    }
}

/// POST devices/pairing/check: the device once the code was used
struct DevicePairingCheck: Codable, Equatable, Sendable {
    var device: Device?
    var expired: Bool
}

// MARK: import (§12.4)

/// An import while it runs, its preview and its result (`ImportJob`, src/library/import/types.ts). The parts the
/// app shows; the rest (matches to look over, conflicts) are on the website.
struct ImportJob: Codable, Equatable, Identifiable, Sendable {
    struct Plan: Codable, Equatable, Sendable {
        struct Decisions: Codable, Equatable, Sendable {
            var added: Int
            var updated: Int
            var unchanged: Int
            var kept: Int
        }

        var media: APIMedia
        var entries: Int
        var decisions: Decisions
    }

    struct Miss: Codable, Equatable, Identifiable, Sendable {
        var key: String
        var media: APIMedia
        var title: String
        var year: Int?
        var reason: String?
        var skipped: Bool?
        var id: String { key }
    }

    struct Counts: Codable, Equatable, Sendable {
        var added: Int
        var updated: Int
        var unchanged: Int
        var kept: Int
        var reviews: Int?
        var lists: Int?
    }

    var id: String
    /// "anilist" | "mal" | "letterboxd" | "trakt" | "goodreads"
    var source: String
    var name: String
    /// "fetching" | "matching" | "ready" | "importing" | "done" | "failed"
    var phase: String
    var done: Int
    var total: Int
    var started: Int64
    var plan: [Plan]
    var unmatched: [Miss]
    var notes: [String]?
    var result: Counts?
    var error: String?

    /// still working: ask again in a second
    var running: Bool { phase == "fetching" || phase == "matching" || phase == "importing" }

    var sourceName: String { ImportSource(rawValue: source)?.label ?? source }

    /// "Reading AniList · 120 of 480", "Ready to import", "Imported"
    var phaseLine: String {
        switch phase {
        case "fetching": return total > 0 ? "Reading \(sourceName) · \(done) of \(total)" : "Reading \(sourceName)"
        case "matching": return total > 0 ? "Matching titles · \(done) of \(total)" : "Matching titles"
        case "ready": return "Ready to import"
        case "importing": return "Importing"
        case "done": return "Imported"
        default: return error ?? "The import didn't work"
        }
    }

    /// 0...1 while it runs
    var progress: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }

    /// "142 new, 12 updated, 300 unchanged"
    static func countsLine(added: Int, updated: Int, unchanged: Int, kept: Int) -> String {
        var parts: [String] = ["\(Format.grouped(added)) new", "\(Format.grouped(updated)) updated",
                               "\(Format.grouped(unchanged)) unchanged"]
        if kept > 0 { parts.append("\(Format.grouped(kept)) kept as you have them") }
        return parts.joined(separator: ", ")
    }

    var resultLine: String? {
        result.map { Self.countsLine(added: $0.added, updated: $0.updated, unchanged: $0.unchanged, kept: $0.kept) }
    }

    /// unmatched titles that aren't left out yet
    var openMisses: [Miss] { unmatched.filter { $0.skipped != true } }
}

/// Where an import comes from
enum ImportSource: String, CaseIterable, Identifiable, Sendable {
    case anilist, mal, letterboxd, trakt, goodreads
    var id: String { rawValue }

    var label: String {
        switch self {
        case .anilist: return "AniList"
        case .mal: return "MyAnimeList"
        case .letterboxd: return "Letterboxd"
        case .trakt: return "Trakt"
        case .goodreads: return "Goodreads"
        }
    }

    /// what to pick in Files
    var fileHint: String {
        switch self {
        case .anilist: return "Your AniList username"
        case .mal: return "The anime or manga list XML from MyAnimeList's export (unzipped)"
        case .letterboxd: return "The CSV files from Letterboxd's export"
        case .trakt: return "The JSON files from Trakt's export"
        case .goodreads: return "goodreads_library_export.csv"
        }
    }
}

/// POST import/anilist
struct AniListImportBody: Codable, Equatable, Sendable { var name: String }

/// POST import/mal: the XML text of 1-4 export files
struct MALImportBody: Codable, Equatable, Sendable { var files: [String] }

/// POST import/file
struct FileImportBody: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        var name: String
        var data: String
        var base64: Bool?
    }

    var source: String
    var files: [File]

    /// a file from Files: text as it is, anything else base64
    static func file(name: String, data: Data) -> File {
        if let text = String(data: data, encoding: .utf8) { return File(name: name, data: text) }
        return File(name: name, data: data.base64EncodedString(), base64: true)
    }
}

/// POST import/:id/fix with skip
struct ImportSkipBody: Codable, Equatable, Sendable {
    var key: String
    var skip: Bool
}

/// POST import/:id/commit
struct ImportCommitBody: Codable, Equatable, Sendable {
    var force: Bool?
}

/// `{ job }`
struct ImportJobAnswer: Codable, Equatable, Sendable { var job: ImportJob? }

// MARK: export (§12.5)

/// GET export/:kind: a file to save (`ExportFile`, src/library/export/export.ts)
struct ExportFile: Codable, Equatable, Sendable {
    var name: String
    /// its MIME type
    var type: String
    var text: String
    var count: Int?
    var skipped: Int?
}

enum ExportKind: String, CaseIterable, Identifiable, Sendable {
    case csv, json, malAnime = "mal-anime", malManga = "mal-manga", messages
    var id: String { rawValue }

    var label: String {
        switch self {
        case .csv: return "Every list as CSV"
        case .json: return "Every list as JSON"
        case .malAnime: return "Anime for MyAnimeList"
        case .malManga: return "Manga for MyAnimeList"
        case .messages: return "Your messages"
        }
    }

    var symbol: String {
        switch self {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .malAnime, .malManga: return "arrow.up.doc"
        case .messages: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: backups (§12.6)

/// a backup kept before a restore or reset (`SavedBackup`)
struct SavedBackup: Codable, Equatable, Identifiable, Sendable {
    var name: String
    /// "restore" | "reset"
    var reason: String
    var at: Int64
    var id: String { name }

    /// "Before a restore"
    var label: String { reason == "reset" ? "Before a reset" : "Before a restore" }
}

/// GET backups
struct SavedBackups: Codable, Equatable, Sendable { var saved: [SavedBackup] }

/// what a restore answers: the titles put back, and the backup made first
struct RestoreAnswer: Codable, Equatable, Sendable {
    var restored: Int
    var saved: SavedBackup

    var line: String { "Restored \(SettingsText.titles(restored)). What you had is kept under Saved backups." }
}

/// one nightly copy on the PC (`AutoBackup`)
struct AutoBackup: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var at: Int64
    var size: Int
    var files: Int
    var id: String { name }
}

/// GET / PUT backups/nightly (`AutoBackupInfo`): the owner's nightly backups
struct AutoBackupInfo: Codable, Equatable, Sendable {
    var enabled: Bool
    /// newest first
    var backups: [AutoBackup]
    var bytes: Int
    var checkedAt: Int64?
    var nextAt: Int64?
}

/// PUT backups/nightly
struct NightlyBody: Codable, Equatable, Sendable { var enabled: Bool }

/// POST backups/nightly/now: `made` is null when nothing changed since the last
struct NightlyNow: Codable, Equatable, Sendable {
    var made: AutoBackup?
    var info: AutoBackupInfo
}

// MARK: accounts and invites (§12.7)

struct AccountRow: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var username: String
    var role: String
    var createdAt: Int64
    /// browsers signed in
    var sessions: Int
}

struct Invite: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var createdAt: Int64
    var expiresAt: Int64
    var usedAt: Int64?
    var usedBy: String?

    /// "Used by @lena", "Expired", "Open until Nov 10"
    func state(now: Date = Clock.now) -> String {
        if let by = usedBy { return "Used by @\(by)" }
        if usedAt != nil { return "Used" }
        if Millis.date(expiresAt) <= now { return "Expired" }
        return "Open until " + SettingsText.shortDate(Millis.date(expiresAt), now: now)
    }

    func isOpen(now: Date = Clock.now) -> Bool { usedAt == nil && Millis.date(expiresAt) > now }
}

/// GET accounts
struct AccountsAnswer: Codable, Equatable, Sendable {
    var accounts: [AccountRow]
    var invites: [Invite]
}

/// POST accounts/invites: the code (shown once) and the invite
struct NewInvite: Codable, Equatable, Sendable {
    var code: String
    var invite: Invite

    /// the website's join page for it
    func link(on base: URL?) -> String {
        guard let base else { return code }
        return base.appendingPathComponent("join").absoluteString + "?code=" + code
    }
}

// MARK: the calls

extension APIClient {
    // §12.1-12.3, §11.5

    /// GET me + GET settings/privacy + GET settings/messages: what the settings pages edit
    func accountSettings() async throws -> AccountSettings {
        async let me = me()
        async let privacy = privacySettings()
        async let messages = settingsMessages()
        let m = try await me
        return AccountSettings(me: m.me, profile: m.profile, prefs: m.prefs, privacy: try await privacy,
                               messages: try await messages.messages)
    }

    /// PATCH settings/prefs with only the fields to change
    func updatePrefs(_ changed: JSONValue) async throws -> PrefsAnswer { try await send("PATCH", "settings/prefs", changed) }

    func privacySettings() async throws -> PrivacySettings { try await get("settings/privacy") }

    func setVisibility(_ body: VisibilityBody) async throws -> VisibilityAnswer {
        try await send("PUT", "settings/privacy/visibility", body)
    }

    func setCommentSetting(_ setting: String) async throws -> CommentSettingBody {
        try await send("PUT", "settings/privacy/comments", CommentSettingBody(setting: setting))
    }

    func settingsMessages() async throws -> SettingsMessages { try await get("settings/messages") }

    func setSettingsMessages(_ who: String) async throws -> SettingsMessages {
        try await send("PUT", "settings/messages", SettingsMessages(messages: who))
    }

    // §12.2 pictures (§5)

    func uploadAvatar(_ data: Data, contentType: String) async throws -> ProfileAnswer {
        try await upload("settings/profile/avatar", data, contentType: contentType)
    }

    func uploadBanner(_ data: Data, contentType: String) async throws -> ProfileAnswer {
        try await upload("settings/profile/banner", data, contentType: contentType)
    }

    func removeAvatar() async throws -> ProfileAnswer { try await send("DELETE", "settings/profile/avatar") }

    func removeBanner() async throws -> ProfileAnswer { try await send("DELETE", "settings/profile/banner") }

    // §4.4 the account

    func account() async throws -> AccountInfo { try await get("account") }

    /// a new sign-in answer for this phone: every other sign-in ends
    func changePassword(current: String, next: String) async throws -> SignInAnswer {
        try await send("POST", "account/password", PasswordBody(current: current, next: next))
    }

    func newRecoveryCodes(password: String) async throws -> NewRecoveryCodes {
        try await send("POST", "account/recovery-codes", RecoveryCodesBody(password: password))
    }

    func endSession(_ id: String) async throws {
        let _: JSONValue = try await send("POST", "account/sessions/\(Self.segment(id))/end")
    }

    /// every browser and app, this phone too
    func signOutEverywhere() async throws {
        let _: JSONValue = try await send("POST", "account/sign-out-everywhere")
    }

    func devices() async throws -> DeviceList { try await get("devices") }

    func disconnectDevice(_ id: Int) async throws -> OKReply { try await send("DELETE", "devices/\(id)") }

    func startPairing(for target: PairingBody.For) async throws -> Pairing {
        try await send("POST", "devices/pairing", PairingBody(target: target))
    }

    func checkDevicePairing(code: String) async throws -> DevicePairingCheck {
        try await send("POST", "devices/pairing/check", PairCheckBody(code: code))
    }

    // §12.4 import

    func importAniList(_ name: String) async throws -> ImportJob {
        try await send("POST", "import/anilist", AniListImportBody(name: name))
    }

    func importMAL(_ xml: [String]) async throws -> ImportJob { try await send("POST", "import/mal", MALImportBody(files: xml)) }

    func importFiles(_ source: ImportSource, _ files: [FileImportBody.File]) async throws -> ImportJob {
        try await send("POST", "import/file", FileImportBody(source: source.rawValue, files: files))
    }

    func importJob(_ id: String) async throws -> ImportJob? {
        let a: ImportJobAnswer = try await get("import/\(Self.segment(id))")
        return a.job
    }

    /// leave an unmatched title out (fixing it to a title is on the website)
    func skipImported(_ id: String, key: String) async throws -> ImportJob {
        try await send("POST", "import/\(Self.segment(id))/fix", ImportSkipBody(key: key, skip: true))
    }

    func commitImport(_ id: String) async throws -> ImportJob? {
        let a: ImportJobAnswer = try await send("POST", "import/\(Self.segment(id))/commit", ImportCommitBody())
        return a.job
    }

    // §12.5 export

    func exportFile(_ kind: ExportKind) async throws -> ExportFile { try await get("export/\(kind.rawValue)") }

    /// the whole backup, kept as it came (to save as guptrack-backup.json)
    func exportBackup() async throws -> JSONValue { try await get("export/backup") }

    // §12.6 backups

    func savedBackups() async throws -> SavedBackups { try await get("backups") }

    /// a backup file from Files
    func restoreBackup(_ json: Data) async throws -> RestoreAnswer {
        try await upload("backups/restore", json, contentType: "application/json")
    }

    func restoreSaved(_ name: String) async throws -> RestoreAnswer {
        try await send("POST", "backups/saved/\(Self.segment(name))/restore")
    }

    func nightlyBackups() async throws -> AutoBackupInfo { try await get("backups/nightly") }

    func setNightly(_ enabled: Bool) async throws -> AutoBackupInfo {
        try await send("PUT", "backups/nightly", NightlyBody(enabled: enabled))
    }

    func backUpNow() async throws -> NightlyNow { try await send("POST", "backups/nightly/now") }

    func restoreNightly(_ name: String) async throws -> RestoreAnswer {
        try await send("POST", "backups/nightly/\(Self.segment(name))/restore")
    }

    // §12.7 accounts

    func accounts() async throws -> AccountsAnswer { try await get("accounts") }

    func createInvite() async throws -> NewInvite { try await send("POST", "accounts/invites") }

    func takeBackInvite(_ id: Int) async throws {
        let _: JSONValue = try await send("DELETE", "accounts/invites/\(id)")
    }

    /// the root page's other values; each part is left out when its call fails (members have no nightly backups
    /// or accounts)
    func settingsSummary(owner: Bool) async -> SettingsSummary {
        async let devices = try? self.devices()
        async let saved = try? savedBackups()
        async let nightly = owner ? try? nightlyBackups() : nil
        async let accounts = owner ? try? self.accounts() : nil
        let times = ((await saved)?.saved.map(\.at) ?? []) + ((await nightly)?.backups.map(\.at) ?? [])
        return SettingsSummary(devices: await devices, lastBackup: times.max().map(Millis.date),
                               accounts: (await accounts)?.accounts.count)
    }
}

// MARK: themes

/// The website's 18 themes for Settings › Appearance, with the colours of their mini previews.
enum SettingsThemes {
    struct Look: Identifiable, Equatable, Sendable {
        var name: String
        var page: UInt32
        var card: UInt32
        var accent: UInt32
        var ink: UInt32
        /// multicolour themes' second accent
        var accent2: UInt32?
        /// Match system: half Midnight, half Light
        var split = false

        /// Prefs.theme ("midnight", "system", "rose")
        var key: String {
            switch name {
            case "Match system": return "system"
            case "Rosé": return "rose"
            default: return name.lowercased()
            }
        }

        var id: String { key }
    }

    struct Shelf: Identifiable, Sendable {
        var name: String
        var themes: [Look]
        var id: String { name }
    }

    private static func t(_ n: String, _ p: UInt32, _ c: UInt32, _ a: UInt32, _ i: UInt32, _ a2: UInt32? = nil) -> Look {
        Look(name: n, page: p, card: c, accent: a, ink: i, accent2: a2)
    }

    static let shelves: [Shelf] = [
        Shelf(name: "Classic", themes: [
            t("Midnight", 0x0E0F12, 0x1A1B20, 0x0A84FF, 0xFFFFFF),
            t("Dark", 0x1C1C1E, 0x2C2C2E, 0x0A84FF, 0xFFFFFF),
            t("Light", 0xF5F5F7, 0xFFFFFF, 0x0A7CFF, 0x1C1C1E),
            t("Paper", 0xF2EBDD, 0xFBF6EC, 0xB5651D, 0x2B2418),
            t("Ocean", 0x0A1826, 0x12263A, 0x3AB0FF, 0xFFFFFF),
            t("Forest", 0x0E1812, 0x17261C, 0x4CC27A, 0xFFFFFF),
            Look(name: "Match system", page: 0x0E0F12, card: 0x1A1B20, accent: 0x0A84FF, ink: 0xFFFFFF, split: true),
        ]),
        Shelf(name: "Pastel", themes: [
            t("Lavender", 0xEBE5F7, 0xF6F2FD, 0x8B6FD6, 0x2A2340),
            t("Mint", 0xE1F3EA, 0xF1FBF6, 0x36A577, 0x16302A),
            t("Sakura", 0xF8E5EB, 0xFDF3F6, 0xD9668B, 0x3A1D28),
            t("Sky", 0xE3EEFB, 0xF3F8FE, 0x4A8FD9, 0x16263A),
            t("Dusk", 0x262033, 0x332B44, 0xC49BD8, 0xFFFFFF),
            t("Rosé", 0x33232A, 0x432F37, 0xEAA2AD, 0xFFFFFF),
        ]),
        Shelf(name: "Colourful", themes: [
            t("Teal", 0x05282A, 0x0B3A3C, 0x14C8B8, 0xFFFFFF),
            t("Sunset", 0x2A1411, 0x3D1D17, 0xFF7A3D, 0xFFFFFF),
            t("Orchid", 0x22102E, 0x331843, 0xD65CF0, 0xFFFFFF),
        ]),
        Shelf(name: "Multicolour", themes: [
            t("Neon", 0x0A0A14, 0x151527, 0xFF3D9A, 0xFFFFFF, 0x22D3EE),
            t("Meadow", 0x0F1A10, 0x192A1A, 0x8BD448, 0xFFFFFF, 0xF5C84B),
        ]),
    ]

    static var all: [Look] { shelves.flatMap(\.themes) }

    static func named(_ name: String) -> Look? { all.first { $0.name == name } }

    /// the theme Prefs.theme names
    static func look(_ key: String) -> Look? { all.first { $0.key == key } }

    static let light: Look = named("Light")!
}


// MARK: widgets

/// Settings › Widgets: what the app's widgets are and how to add them.
enum WidgetGuide {
    struct Item: Identifiable, Sendable {
        var name: String
        var symbol: String
        var sizes: String
        var about: String
        var id: String { name }
    }

    static let widgets: [Item] = [
        Item(name: "Up Next", symbol: "play.rectangle", sizes: "Small, medium",
             about: "The next episode or chapter of what you're on, with +1 right on the widget."),
    ]

    static let steps: [String] = [
        "Touch and hold an empty part of the Home Screen until the apps jiggle.",
        "Tap Edit, then Add Widget.",
        "Search for GupTrack, pick a size and tap Add Widget.",
    ]
}

// MARK: small text helpers

enum SettingsText {
    /// "Today", "Yesterday", "Nov 1"
    static func dayName(_ d: Date, now: Date = Clock.now) -> String {
        switch Format.dayOffset(d, now: now) {
        case 0: return "Today"
        case -1: return "Yesterday"
        default: return Format.shortDay(d)
        }
    }

    /// "Nov 1" this year, "Mar 14, 2025" before
    static func shortDate(_ d: Date, now: Date = Clock.now) -> String {
        Clock.calendar.component(.year, from: d) == Clock.calendar.component(.year, from: now)
            ? Format.shortDay(d) : Format.longDay(d)
    }

    /// 1_800_000 -> "1.8 MB", 850_000 -> "850 KB"
    static func size(_ bytes: Int) -> String {
        if bytes >= 1_000_000_000 { return Format.trim((Double(bytes) / 1e8).rounded() / 10) + " GB" }
        if bytes >= 1_000_000 { return Format.trim((Double(bytes) / 1e5).rounded() / 10) + " MB" }
        if bytes >= 1_000 { return "\(Int((Double(bytes) / 1e3).rounded())) KB" }
        return "\(bytes) bytes"
    }

    /// "42 titles"
    static func titles(_ n: Int) -> String { "\(Format.grouped(n)) title\(n == 1 ? "" : "s")" }

    /// "Synced 2 min ago" / "Not synced yet"
    static func synced(_ d: Date?, now: Date = Clock.now) -> String {
        guard let d else { return "Not synced yet" }
        return "Synced " + Format.agoLong(d, now: now)
    }

    /// "1 change waiting to send"
    static func pending(_ n: Int) -> String {
        n == 0 ? "Everything is sent" : "\(n) change\(n == 1 ? "" : "s") waiting to send"
    }
}

