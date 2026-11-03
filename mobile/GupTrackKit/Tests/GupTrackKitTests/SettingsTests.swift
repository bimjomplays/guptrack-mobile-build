import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Settings (55-64b): the settings fixtures, the PATCH diff, score formats, captions, the bio document.
final class SettingsTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func settings() throws -> AccountSettings { try Demo.load(AccountSettings.self, "api/settings.json") }

    // MARK: fixtures

    func testSettingsDecode() throws {
        let s = try settings()
        XCTAssertEqual(s.account.username, "mika")
        XCTAssertTrue(s.account.isOwner)
        XCTAssertEqual(s.accountLine, "Owner · Joined Mar 14, 2025")
        XCTAssertEqual(s.theme, "Midnight")
        XCTAssertNotNil(SettingsThemes.named(s.theme))
        XCTAssertEqual(s.preferences.scoreFormat, .point10)
        XCTAssertEqual(s.privacy.list(.movie), .friends)
        XCTAssertEqual(s.privacy.list(.anime), .public)
        XCTAssertEqual(s.connectedValue, "Harbor")
        XCTAssertEqual(s.backupValue, "Today")
        XCTAssertEqual(s.profile.fade, 70)
        XCTAssertEqual(BioDocument.summary(s.profile.bio), "Seasonal anime, slow manga")
    }

    func testBackupsDecode() throws {
        let b = try Demo.load(BackupList.self, "api/settings/backups.json")
        XCTAssertTrue(b.automatic)
        XCTAssertEqual(b.backups.count, 5)
        XCTAssertEqual(b.backups[0].when, "Today, 3:30 AM")
        XCTAssertEqual(b.backups[1].when, "Yesterday, 3:30 AM")
        XCTAssertEqual(b.backups[2].when, "Nov 1, 3:30 AM")
        XCTAssertEqual(b.backups[3].when, "Oct 30, 6:47 PM")
        XCTAssertEqual(b.backups[3].note, "Before AniList import")
        XCTAssertEqual(b.backups[0].size, "1.8 MB")
    }

    func testConnectedAppsDecode() throws {
        let c = try Demo.load(ConnectedDevices.self, "api/settings/connected-apps.json")
        XCTAssertEqual(c.pairing.shownCode, "517-260")
        XCTAssertEqual(c.pairing.expiry(), "Expires in 8:15 · works once")
        XCTAssertEqual(c.pairing.expiry(now: c.pairing.expiresAt.addingTimeInterval(1)), "Expired · pull down for a new code")
        XCTAssertEqual(c.pairing.qrPayload, "guptrack://pair?code=517260&server=https://guptrack.example")
        XCTAssertEqual(c.devices.count, 2)
        let phone = c.devices[0], harbor = try XCTUnwrap(c.harbor)
        XCTAssertEqual(phone.caption(thisDevice: true), "This iPhone · now")
        XCTAssertEqual(harbor.caption(thisDevice: false), "Synced 6 min ago · 27 titles")
        XCTAssertTrue(harbor.isLive())
        XCTAssertEqual(harbor.symbol, "desktopcomputer")
        XCTAssertEqual(phone.id, Demo.account().deviceId, "the demo's own device is marked This iPhone")
    }

    func testAccountsDecode() throws {
        let a = try Demo.load(AccountList.self, "api/settings/accounts.json")
        XCTAssertEqual(a.accounts.count, 5)
        XCTAssertEqual(a.sorted.first?.user.username, "mika")
        XCTAssertEqual(a.sorted.first?.caption, "You · Joined Mar 14, 2025")
        XCTAssertEqual(AccountList.joiningLabel(a.joining), "Invite only")
        XCTAssertEqual(a.accounts.filter { $0.role == "owner" }.count, 1)
        let invite = try Demo.load(AccountList.Invite.self, "api/settings/accounts/invite.post.json")
        XCTAssertEqual(invite.url.host, "guptrack.example")
    }

    func testImportDecode() throws {
        let i = try Demo.load(ImportStatus.self, "api/settings/import.json")
        XCTAssertEqual(i.sources.map(\.initials), ["AL", "MAL", "LB", "TR", "GR"])
        let last = try XCTUnwrap(i.last)
        XCTAssertEqual(last.title, "Last import · AniList")
        XCTAssertEqual(last.caption, "162 anime from mika · Oct 30, 6:52 PM")
    }

    // MARK: PATCH

    func testPatchHasOnlyWhatChanged() throws {
        let old = try settings()
        var new = old
        XCTAssertNil(AccountSettings.patch(from: old, to: new))
        new.preferences.scoreFormat = .stars5
        new.privacy.lists["movie"] = .public
        new.theme = "Ocean"
        let p = try XCTUnwrap(AccountSettings.patch(from: old, to: new))
        XCTAssertEqual(p, .object([
            "preferences": .object(["scoreFormat": .string("stars5")]),
            "privacy": .object(["lists": .object(["movie": .string("public")])]),
            "theme": .string("Ocean"),
        ]))
        let body = String(decoding: try APIClient.encoder.encode(p), as: UTF8.self)
        XCTAssertEqual(body, #"{"preferences":{"scoreFormat":"stars5"},"privacy":{"lists":{"movie":"public"}},"theme":"Ocean"}"#)
    }

    func testPatchNumbersAndNulls() throws {
        let old = try settings()
        var new = old
        new.profile.fade = 45
        new.profile.banner = nil
        let p = try XCTUnwrap(AccountSettings.patch(from: old, to: new))
        let body = String(decoding: try APIClient.encoder.encode(p), as: UTF8.self)
        XCTAssertEqual(body, #"{"profile":{"banner":null,"fade":45}}"#)
    }

    @MainActor
    func testStoreSendsOnePatchAndForgetsIt() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "t")
        let store = AccountSettingsStore()
        store.loaded(try settings(), for: "mika")
        XCTAssertFalse(store.needsLoad(for: "mika"))
        XCTAssertTrue(store.needsLoad(for: "kenji"))
        store.edit { $0.notifications.likesAndReplies = true }
        XCTAssertNotNil(store.pendingPatch)
        try await store.save(using: api)
        XCTAssertNil(store.pendingPatch)
        let sent = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(sent.method, "PATCH")
        XCTAssertEqual(sent.path, "settings")
        XCTAssertEqual(String(decoding: try XCTUnwrap(sent.body), as: UTF8.self),
                       #"{"notifications":{"likesAndReplies":true}}"#)
        try await store.save(using: api)
        XCTAssertEqual(transport.requests.count, 1, "nothing changed: nothing sent")
    }

    // MARK: formats

    func testScoreFormatExamples() {
        XCTAssertEqual(AccountSettings.ScoreFormat.allCases.map(\.example), ["8", "8.5", "85", "★★★★☆", "🙂"])
        XCTAssertEqual(AccountSettings.ScoreFormat.point10Decimal.show(70), "7")
        XCTAssertEqual(AccountSettings.ScoreFormat.stars5.show(100), "★★★★★")
        XCTAssertEqual(AccountSettings.ScoreFormat.stars5.show(0), "☆☆☆☆☆")
        XCTAssertEqual(AccountSettings.ScoreFormat.smiley3.show(50), "😐")
        XCTAssertEqual(AccountSettings.ScoreFormat.smiley3.show(20), "🙁")
        XCTAssertEqual(AccountSettings.ScoreFormat.point100.show(140), "100")
    }

    func testDateStyles() {
        let now = Clock.now
        XCTAssertEqual(AccountSettings.DateStyle.allCases.map { $0.show(now) },
                       ["Nov 3, 2026", "3 Nov 2026", "2026-11-03", "11/3/2026"])
    }

    func testSizesAndCounts() {
        XCTAssertEqual(SettingsText.size(1_812_000), "1.8 MB")
        XCTAssertEqual(SettingsText.size(2_000_000), "2 MB")
        XCTAssertEqual(SettingsText.size(850_400), "850 KB")
        XCTAssertEqual(SettingsText.size(3_210_000_000), "3.2 GB")
        XCTAssertEqual(SettingsText.titles(1), "1 title")
        XCTAssertEqual(SettingsText.titles(1_204), "1,204 titles")
        XCTAssertEqual(SettingsText.synced(nil), "Not synced yet")
        XCTAssertEqual(SettingsText.synced(Clock.now.addingTimeInterval(-120)), "Synced 2 min ago")
        XCTAssertEqual(SettingsText.pending(0), "Everything is sent")
        XCTAssertEqual(SettingsText.pending(2), "2 changes waiting to send")
    }

    func testThemes() {
        XCTAssertEqual(SettingsThemes.all.count, 18)
        XCTAssertEqual(SettingsThemes.shelves.map(\.name), ["Classic", "Pastel", "Colourful", "Multicolour"])
        XCTAssertEqual(Set(SettingsThemes.all.map(\.name)).count, 18, "names are unique")
        XCTAssertTrue(SettingsThemes.named("Match system")!.split)
        XCTAssertNotNil(SettingsThemes.named("Neon")!.accent2)
    }

    // MARK: the bio

    func testBioSplitsIntoTextAndLists() throws {
        let doc = BioDocument(try settings().profile.bio)
        XCTAssertEqual(doc.blocks.count, 3)
        guard case .list(let ref) = doc.blocks[1] else { return XCTFail("the list is the second block") }
        XCTAssertEqual(ref.favouritesMedia, .anime)
        XCTAssertEqual(ref.styleLabel, "shown as a cover row")
        XCTAssertEqual(doc.blocks[2], .text("> ask me about the long-running ones"))
        // and back again (without the blank lines around the list)
        XCTAssertEqual(BioDocument(doc.text), doc)
    }

    func testBioInsertAndRemoveList() {
        var doc = BioDocument("Hello")
        XCTAssertEqual(doc.blocks, [.text("Hello")])
        doc.insert(.init(id: "comfort-rewatches", style: "list"), after: 0)
        XCTAssertEqual(doc.blocks, [.text("Hello"), .list(.init(id: "comfort-rewatches", style: "list")), .text("")])
        XCTAssertEqual(doc.text, "Hello\n{{list:comfort-rewatches|list}}")
        doc.blocks[2] = .text("Bye")
        doc.remove(at: 1)
        XCTAssertEqual(doc.blocks, [.text("Hello\nBye")])
        XCTAssertEqual(BioDocument("").blocks, [.text("")])
        XCTAssertEqual(BioDocument("{{list:x}}").blocks, [.list(.init(id: "x", style: "covers")), .text("")])
    }

    func testFormattingBar() {
        typealias S = BioDocument.Style
        XCTAssertEqual(S.bold.apply("Watching"), "Watching **bold**")
        XCTAssertEqual(S.italic.apply(""), "*italic*")
        XCTAssertEqual(S.heading.apply("a\nTop five"), "a\n## Top five")
        XCTAssertEqual(S.heading.apply("## Top five"), "Top five", "a second tap takes it off")
        XCTAssertEqual(S.quote.apply("# Big"), "> Big")
        XCTAssertEqual(S.list.apply("a"), "a\n- ")
        XCTAssertEqual(S.link.apply("see "), "see [link](https://)")
    }

    func testBioLines() {
        let lines = BioDocument.lines("# Title\n## Sub\n- item\n> said\n\nWatching **SBR** every *Friday*, [here](https://x)")
        XCTAssertEqual(lines.map(\.kind), [.heading1, .heading2, .bullet, .quote, .blank, .body])
        XCTAssertEqual(lines[5].plain, "Watching SBR every Friday, here")
        XCTAssertEqual(BioDocument.summary("\n{{list:x}}\n## **Big** news"), "Big news")
    }

    // MARK: export

    func testExport() throws {
        let lib = try Demo.load([LibraryEntry].self, "api/library.json")
        let csv = LibraryExport.csv(lib)
        let rows = csv.split(separator: "\n")
        XCTAssertEqual(rows.first.map(String.init), LibraryExport.csvHeader)
        XCTAssertEqual(rows.count, lib.count + 1)
        XCTAssertEqual(LibraryExport.cell("a, \"b\""), "\"a, \"\"b\"\"\"")
        let back = try APIClient.decoder.decode([LibraryEntry].self, from: LibraryExport.json(lib))
        XCTAssertEqual(back.count, lib.count)
        XCTAssertEqual(LibraryExport.fileName("csv"), "guptrack-library-2026-11-03.csv")
    }
}
