import Foundation
import Observation

// Settings (55-64b): the account's settings in one struct (GET settings, PATCH settings with only what changed),
// and the pages that have their own data: backups, connected apps, accounts, import. Everything that isn't drawing
// lives here so it's tested on Linux (SettingsTests.swift).

// MARK: the account's settings

/// GET settings: everything Settings shows for the signed-in account. PATCH settings takes the changed fields only
/// (`AccountSettings.patch(from:to:)`), nested as here.
struct AccountSettings: Codable, Equatable, Sendable {
    var account: Account
    var profile: Profile
    var privacy: Privacy
    /// a theme's name from `SettingsThemes` ("Midnight")
    var theme: String
    var preferences: Preferences
    var notifications: Notifications
    /// the root page's values ("3 on", "Harbor", "Today", "4")
    var summary: Summary

    struct Account: Codable, Equatable, Sendable {
        var username: String
        /// "owner" | "member"
        var role: String
        var joined: Date

        var isOwner: Bool { role == "owner" }
        var roleLabel: String { role == "owner" ? "Owner" : "Member" }
    }

    struct Profile: Codable, Equatable, Sendable {
        var displayName: String
        var avatar: URL?
        var banner: URL?
        /// the title the banner comes from ("Frieren: Beyond Journey's End")
        var bannerName: String?
        /// markdown with {{list:…}} blocks (BioDocument)
        var bio: String
        var bioPreset: BioPreset
        /// 0-100: how dark the bottom of the banner gets
        var fade: Int
        var fadeColour: FadeColour
        var bannerText: BannerText
    }

    enum FadeColour: String, Codable, CaseIterable, Identifiable, Sendable {
        case dark, page
        var id: String { rawValue }
        var label: String { self == .dark ? "Dark" : "Page colour" }
    }

    enum BannerText: String, Codable, CaseIterable, Identifiable, Sendable {
        case auto, shadow, backing, none
        var id: String { rawValue }
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    enum BioPreset: String, Codable, CaseIterable, Identifiable, Sendable {
        case ledger, editorial, shelf, minimal
        var id: String { rawValue }
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    struct Privacy: Codable, Equatable, Sendable {
        var profile: Visibility
        /// per media ("anime", "manga", "tv", "movie", "book")
        var lists: [String: Visibility]
        var comments: Reach
        var messages: Reach

        func list(_ m: MediaKind) -> Visibility { lists[m.rawValue] ?? profile }
    }

    /// who can comment on your profile or message you
    enum Reach: String, Codable, CaseIterable, Identifiable, Sendable {
        case everyone, friends, nobody
        var id: String { rawValue }
        var label: String {
            switch self {
            case .everyone: return "Everyone signed in"
            case .friends: return "Friends"
            case .nobody: return "No one"
            }
        }
    }

    struct Preferences: Codable, Equatable, Sendable {
        var titleLanguage: TitleLanguage
        var adult: Bool
        var hideSpoilers: Bool
        var scoreFormat: ScoreFormat
        var smartProgress: Bool
        var autoDates: Bool
        var dateFormat: DateStyle
        var weekStart: WeekStart
    }

    enum TitleLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
        case english, romaji, native
        var id: String { rawValue }
        var label: String {
            switch self {
            case .english: return "English"
            case .romaji: return "Romaji"
            case .native: return "Native"
            }
        }
    }

    /// How scores show (the website keeps 0-100). `example` is the menu's sub line.
    enum ScoreFormat: String, Codable, CaseIterable, Identifiable, Sendable {
        case point10, point10Decimal, point100, stars5, smiley3
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

    enum DateStyle: String, Codable, CaseIterable, Identifiable, Sendable {
        case medium, dayFirst, iso, numeric
        var id: String { rawValue }

        private var pattern: String {
            switch self {
            case .medium: return "MMM d, yyyy"
            case .dayFirst: return "d MMM yyyy"
            case .iso: return "yyyy-MM-dd"
            case .numeric: return "M/d/yyyy"
            }
        }

        /// a date in this style: "Nov 3, 2026", "3 Nov 2026", "2026-11-03", "11/3/2026"
        func show(_ d: Date) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = Clock.zone
            f.dateFormat = pattern
            return f.string(from: d)
        }
    }

    enum WeekStart: String, Codable, CaseIterable, Identifiable, Sendable {
        case monday, sunday, saturday
        var id: String { rawValue }
        var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    struct Notifications: Codable, Equatable, Sendable {
        var newEpisodes: Bool
        var newSeasons: Bool
        var plannedReleases: Bool
        var friendRequests: Bool
        var profileComments: Bool
        var likesAndReplies: Bool
        var messages: Bool
    }

    struct Summary: Codable, Equatable, Sendable {
        var sourcesOn: Int
        var connectedApps: [String]
        var lastBackup: Date?
        var accounts: Int
    }

    /// "Owner · Joined Mar 14, 2025"
    var accountLine: String { "\(account.roleLabel) · Joined \(Format.longDay(account.joined))" }

    /// the root page's value for each row
    var connectedValue: String? { summary.connectedApps.isEmpty ? nil : summary.connectedApps.joined(separator: ", ") }

    var backupValue: String? { summary.lastBackup.map { SettingsText.dayName($0) } }

    /// only what changed between two versions, nested like the struct (nil when nothing did)
    static func patch(from old: AccountSettings, to new: AccountSettings) -> SettingsJSON? {
        guard let a = try? SettingsJSON(old), let b = try? SettingsJSON(new) else { return nil }
        return SettingsJSON.diff(a, b)
    }
}

// MARK: a JSON value (PATCH bodies)

/// Any JSON value, so a PATCH can carry just the changed fields.
enum SettingsJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SettingsJSON])
    case object([String: SettingsJSON])

    /// a Codable value as JSON (with the API's date format)
    init<T: Encodable>(_ value: T) throws {
        let data = try APIClient.encoder.encode(value)
        self = try APIClient.decoder.decode(SettingsJSON.self, from: data)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([SettingsJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: SettingsJSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if n == n.rounded(), abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> SettingsJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// what `new` changes from `old`: objects recurse (only changed keys), anything else is replaced whole;
    /// a key gone from `new` becomes null. nil when nothing changed.
    static func diff(_ old: SettingsJSON, _ new: SettingsJSON) -> SettingsJSON? {
        guard case .object(let a) = old, case .object(let b) = new else { return old == new ? nil : new }
        var out: [String: SettingsJSON] = [:]
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
}

// MARK: the shared copy the settings pages edit

/// The account's settings as the pages see them: loaded once, edited locally at once, sent a moment later as one
/// PATCH of what changed. Settings, its pages and the bio editor share it, so the root's values ("Midnight") and the
/// profile preview follow every edit.
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

    /// what would be sent (nil: nothing changed)
    var pendingPatch: SettingsJSON? {
        guard let saved, let settings else { return nil }
        return AccountSettings.patch(from: saved, to: settings)
    }

    /// send what changed; on failure the edits stay and the error comes back
    func save(using api: APIClient) async throws {
        guard let settings, let patch = pendingPatch else { return }
        let _: OKReply = try await api.patchSettings(patch)
        saved = settings
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

// MARK: backups

/// GET settings/backups: the PC's backups, newest first. POST settings/backups backs up now; POST
/// settings/backups/<id>/restore restores one (the server backs up first, so it can be undone).
struct BackupList: Codable, Equatable, Sendable {
    var automatic: Bool
    /// "Every night at 3:30 AM, keeps the last 10"
    var schedule: String
    var backups: [Backup]

    struct Backup: Codable, Identifiable, Equatable, Sendable {
        var id: String
        var at: Date
        var bytes: Int
        /// why it was made, when it wasn't the nightly one ("Before AniList import")
        var note: String?

        /// "Today, 3:30 AM", "Yesterday, 3:30 AM", "Nov 1, 3:30 AM"
        var when: String { SettingsText.dayName(at) + ", " + Format.time(at) }
        var size: String { SettingsText.size(bytes) }
    }
}

// MARK: connected apps

/// GET settings/connected-apps: a one-time code for pairing Harbor (or another iPhone) and the devices signed in.
/// DELETE settings/connected-apps/<id> disconnects one.
struct ConnectedDevices: Codable, Equatable, Sendable {
    var pairing: Pairing
    var devices: [Device]

    struct Pairing: Codable, Equatable, Sendable {
        /// six digits, shown "517-260"
        var code: String
        var expiresAt: Date
        /// the server address the QR carries
        var server: URL

        var shownCode: String {
            let d = code.filter(\.isNumber)
            guard d.count == 6 else { return code }
            return String(d.prefix(3)) + "-" + String(d.suffix(3))
        }

        /// what the QR encodes: guptrack://pair?code=517260&server=https://…
        var qrPayload: String {
            var c = URLComponents()
            c.scheme = "guptrack"
            c.host = "pair"
            c.queryItems = [URLQueryItem(name: "code", value: code.filter(\.isNumber)),
                            URLQueryItem(name: "server", value: server.absoluteString)]
            return c.string ?? "guptrack://pair"
        }

        /// "Expires in 8:15 · works once", "Expired: pull to get a new code"
        func expiry(now: Date = Clock.now) -> String {
            let left = Int(expiresAt.timeIntervalSince(now))
            if left <= 0 { return "Expired · pull down for a new code" }
            return String(format: "Expires in %d:%02d · works once", left / 60, left % 60)
        }
    }

    struct Device: Codable, Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        /// "iphone" | "harbor" | "web"
        var kind: String
        var lastSync: Date?
        /// titles it has synced (Harbor)
        var titles: Int?

        var symbol: String {
            switch kind {
            case "iphone": return "iphone"
            case "harbor": return "desktopcomputer"
            default: return "globe"
            }
        }

        /// "This iPhone · now", "Synced 6 min ago · 27 titles"
        func caption(thisDevice: Bool, now: Date = Clock.now) -> String {
            if thisDevice { return "This iPhone · now" }
            var parts: [String] = []
            if let lastSync { parts.append("Synced " + Format.agoLong(lastSync, now: now)) } else { parts.append("Never synced") }
            if let titles { parts.append("\(Format.grouped(titles)) title\(titles == 1 ? "" : "s")") }
            return parts.joined(separator: " · ")
        }

        /// synced in the last day: the green dot
        func isLive(now: Date = Clock.now) -> Bool {
            guard let lastSync else { return false }
            return now.timeIntervalSince(lastSync) < 86_400
        }
    }

    var harbor: Device? { devices.first { $0.kind == "harbor" } }
}

// MARK: accounts (owner only)

/// GET settings/accounts: every account on this GupTrack. POST settings/accounts/invite makes an invite link.
struct AccountList: Codable, Equatable, Sendable {
    var accounts: [Member]
    /// "open" | "invite" | "closed"
    var joining: String

    struct Member: Codable, Identifiable, Equatable, Sendable {
        var user: UserRef
        var role: String
        var joined: Date
        var you: Bool

        var id: String { user.username }
        var roleLabel: String { role == "owner" ? "Owner" : "Member" }
        /// "You · Joined Mar 14", "Joined Nov 4"
        var caption: String { (you ? "You · " : "") + "Joined " + SettingsText.shortDate(joined) }
    }

    static let joiningChoices: [(String, String)] = [("open", "Anyone"), ("invite", "Invite only"), ("closed", "No one")]

    static func joiningLabel(_ v: String) -> String { joiningChoices.first { $0.0 == v }?.1 ?? v }

    /// owner first, then by name
    var sorted: [Member] {
        accounts.sorted { a, b in
            if (a.role == "owner") != (b.role == "owner") { return a.role == "owner" }
            return a.user.name.localizedCaseInsensitiveCompare(b.user.name) == .orderedAscending
        }
    }
}

extension AccountList {
    /// POST settings/accounts/invite
    struct Invite: Codable, Equatable, Sendable {
        var url: URL
        var expiresAt: Date
    }
}

// MARK: import & export

/// GET settings/import: the last import and the importers. POST settings/import/<id> starts one.
struct ImportStatus: Codable, Equatable, Sendable {
    var last: LastImport?
    var sources: [Source]

    struct LastImport: Codable, Equatable, Sendable {
        var source: String
        var count: Int
        /// "anime"
        var media: String
        var account: String?
        var at: Date
        var ok: Bool

        var title: String { "Last import · " + source }
        /// "162 anime from mika · Oct 30, 6:52 PM"
        var caption: String {
            var s = "\(Format.grouped(count)) \(media)"
            if let account { s += " from \(account)" }
            return s + " · " + SettingsText.shortDate(at) + ", " + Format.time(at)
        }
    }

    struct Source: Codable, Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        /// shown in a ring instead of the service's logo ("AL")
        var initials: String
        var sub: String
        /// "username" (types a username) | "file" (an export file on the website)
        var by: String
        /// the username last used
        var account: String?
    }
}

/// The offline library as a file for the share sheet.
enum LibraryExport {
    static func json(_ entries: [LibraryEntry]) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(ISO8601.string(date))
        }
        return (try? e.encode(entries)) ?? Data("[]".utf8)
    }

    static let csvHeader = "id,media,title,status,progress,total,score,started,finished,favourite"

    static func csv(_ entries: [LibraryEntry]) -> String {
        var lines = [csvHeader]
        for e in entries {
            let fields: [String] = [e.id, e.media.rawValue, e.title.name, e.status.rawValue, String(e.progress),
                                    e.title.total.map(String.init) ?? "", e.score.map(String.init) ?? "",
                                    e.started ?? "", e.finished ?? "", e.favourite ? "yes" : ""]
            lines.append(fields.map(cell).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func cell(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "guptrack-library-2026-11-03.json"
    static func fileName(_ ext: String, now: Date = Clock.now) -> String { "guptrack-library-\(Format.day(now)).\(ext)" }
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

        var id: String { name }
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

    static let light: Look = named("Light")!
}

// MARK: the bio

/// The bio as the editor sees it: markdown text with {{list:<id>|<style>}} lines that pull a list from the library.
/// Text blocks are edited as text; list blocks are cards.
struct BioDocument: Equatable, Sendable {
    enum Block: Equatable, Sendable {
        case text(String)
        case list(ListRef)
    }

    struct ListRef: Equatable, Sendable {
        /// a custom list's id, or "favourites:<media>"
        var id: String
        /// "covers" (a cover row) | "list" (title lines)
        var style: String

        var favouritesMedia: MediaKind? {
            guard id.hasPrefix("favourites:") else { return nil }
            return MediaKind(rawValue: String(id.dropFirst("favourites:".count)))
        }

        var styleLabel: String { style == "list" ? "shown as a list" : "shown as a cover row" }

        var token: String { "{{list:\(id)|\(style)}}" }
    }

    var blocks: [Block]

    init(blocks: [Block]) { self.blocks = blocks }

    init(_ text: String) {
        var out: [Block] = []
        var run: [String] = []
        func flush() {
            // the blank line around a list block belongs to the layout, not the text
            while run.last?.isEmpty == true { run.removeLast() }
            while run.first?.isEmpty == true { run.removeFirst() }
            if !run.isEmpty { out.append(.text(run.joined(separator: "\n"))) }
            run = []
        }
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let ref = Self.listRef(line) {
                flush()
                out.append(.list(ref))
            } else {
                run.append(raw)
            }
        }
        flush()
        if out.isEmpty || { if case .list = out.last! { return true } else { return false } }() {
            out.append(.text(""))
        }
        blocks = out
    }

    static func listRef(_ line: String) -> ListRef? {
        guard line.hasPrefix("{{list:"), line.hasSuffix("}}") else { return nil }
        let inner = line.dropFirst("{{list:".count).dropLast(2)
        let parts = inner.split(separator: "|", maxSplits: 1).map(String.init)
        guard let id = parts.first, !id.isEmpty else { return nil }
        return ListRef(id: id, style: parts.count > 1 ? parts[1] : "covers")
    }

    var text: String {
        var parts: [String] = []
        for b in blocks {
            switch b {
            case .text(let s): if !s.isEmpty { parts.append(s) }
            case .list(let r): parts.append(r.token)
            }
        }
        return parts.joined(separator: "\n")
    }

    /// put a list after block `index` (the one being edited), with an empty text block after it to type on
    mutating func insert(_ ref: ListRef, after index: Int?) {
        let at = min(blocks.count, (index ?? blocks.count - 1) + 1)
        blocks.insert(.list(ref), at: at)
        if at + 1 >= blocks.count || { if case .list = blocks[at + 1] { return true } else { return false } }() {
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

    /// the bio's first line without markdown, for the Bio row ("Seasonal anime, slow manga")
    static func summary(_ text: String) -> String {
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || listRef(line) != nil { continue }
            return Line(line).plain
        }
        return ""
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
                else { lines[lines.count - 1] = prefix + Line(last).plainMarkers }
                return lines.joined(separator: "\n")
            }
            func append(_ s: String) -> String { text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") ? text + s : text + " " + s }
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
        enum Kind: Equatable, Sendable { case blank, heading1, heading2, bullet, quote, body }

        var kind: Kind
        /// the line without its block marker (inline markdown left in)
        var content: String

        init(_ raw: String) {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { kind = .blank; content = ""; return }
            for (p, k) in [("### ", Kind.heading2), ("## ", .heading2), ("# ", .heading1), ("- ", .bullet), ("* ", .bullet),
                           ("> ", .quote)] where s.hasPrefix(p) {
                kind = k
                content = String(s.dropFirst(p.count))
                return
            }
            if s == ">" { kind = .quote; content = ""; return }
            kind = .body
            content = s
        }

        /// without block markers (for re-prefixing)
        var plainMarkers: String { content }

        /// without any markdown: "**STEEL BALL RUN** every *Friday*" -> "STEEL BALL RUN every Friday"
        var plain: String {
            var s = content
            s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            for m in ["**", "__", "*", "_", "`", "~~"] { s = s.replacingOccurrences(of: m, with: "") }
            return s.trimmingCharacters(in: .whitespaces)
        }
    }

    static func lines(_ text: String) -> [Line] { text.components(separatedBy: "\n").map(Line.init) }
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

// MARK: the calls

extension APIClient {
    func accountSettings() async throws -> AccountSettings { try await get("settings") }

    /// PATCH settings with only the changed fields
    func patchSettings(_ changes: SettingsJSON) async throws -> OKReply { try await send("PATCH", "settings", changes) }

    func backups() async throws -> BackupList { try await get("settings/backups") }
    func backUpNow() async throws -> OKReply { try await send("POST", "settings/backups") }
    func restoreBackup(_ id: String) async throws -> OKReply { try await send("POST", "settings/backups/\(id)/restore") }

    func connectedDevices() async throws -> ConnectedDevices { try await get("settings/connected-apps") }
    func disconnectDevice(_ id: String) async throws -> OKReply { try await send("DELETE", "settings/connected-apps/\(id)") }

    func accountList() async throws -> AccountList { try await get("settings/accounts") }
    func createInvite() async throws -> AccountList.Invite { try await send("POST", "settings/accounts/invite") }
    /// PATCH settings/accounts: who can make an account ("open" | "invite" | "closed")
    func setJoining(_ joining: String) async throws -> OKReply {
        try await send("PATCH", "settings/accounts", ["joining": joining])
    }

    func importStatus() async throws -> ImportStatus { try await get("settings/import") }

    /// POST settings/import/<source> with the username to import from
    func startImport(_ source: String, username: String) async throws -> OKReply {
        try await send("POST", "settings/import/\(source)", ["username": username])
    }

    /// POST settings/picture: a new profile picture (JPEG, base64)
    func uploadPicture(_ jpeg: Data) async throws -> OKReply {
        try await send("POST", "settings/picture", ["image": jpeg.base64EncodedString()])
    }
}
