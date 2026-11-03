import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Settings (55-64b) on the app API (docs/app-api.md §4.4, §5, §11.5, §12): the fixtures, the doc's shapes, the calls
/// (method, path, body, request id), the save diff, the bio's Tiptap bridge, and the small text helpers.
final class SettingsTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func demo() -> APIClient { APIClient(transport: DemoTransport(), token: "demo") }

    private func body(_ r: APIRequest?) -> String { r?.body.map { String(decoding: $0, as: UTF8.self) } ?? "" }

    private func json(_ s: String) throws -> JSONValue { try APIClient.decoder.decode(JSONValue.self, from: Data(s.utf8)) }

    // MARK: fixtures

    func testAccountSettingsFromTheDemo() async throws {
        let s = try await demo().accountSettings()
        XCTAssertEqual(s.me.username, "mika")
        XCTAssertTrue(s.isOwner)
        XCTAssertEqual(s.displayName, "Mika")
        XCTAssertEqual(s.accountLine, "Owner · Joined Sep 9, 2025")
        XCTAssertEqual(s.theme?.name, "Dark")
        XCTAssertEqual(s.scoreFormat, .point10Decimal)
        XCTAssertEqual(s.privacy.visibility, .public)
        XCTAssertEqual(s.privacy.list(.books), .private)
        XCTAssertEqual(s.privacy.comments, "friends")
        XCTAssertEqual(s.messages, "friends")
        let bio = s.bio
        XCTAssertEqual(bio.banner.src?.scheme, "https")
        XCTAssertEqual(bio.banner.posY, 42)
        XCTAssertEqual(bio.banner.fade, BannerFade())
        XCTAssertEqual(BioPreset.matching(bio.style), .editorial)
        XCTAssertEqual(BioDocument.summary(bio.doc), "Seasonal anime, slow manga, one book a month.")
    }

    func testAccountAndDevicesFixtures() async throws {
        let api = demo()
        let a = try await api.account()
        XCTAssertEqual(a.recoveryLine, "8 of 10 left")
        XCTAssertEqual(a.passkeyLine, "1 passkey")
        XCTAssertEqual(a.sessions.map(\.name), ["Firefox on Linux", "Safari on Mac"])
        XCTAssertEqual(a.sessions[0].seenLine(), "Last seen 12 min ago")
        let d = try await api.devices()
        XCTAssertEqual(d.current, 1)
        XCTAssertEqual(d.this?.name, "iPhone")
        XCTAssertEqual(d.others.map(\.id), [7, 9])
        XCTAssertTrue(d.others[0].isHarbor)
        XCTAssertEqual(d.others[0].symbol, "play.tv")
        XCTAssertEqual(d.others[0].caption(), "Harbor · Windows 11 · Used 3 hours ago")
        let p = try await api.startPairing(for: .harbor)
        XCTAssertEqual(p.code, "7KQ4-M2XD")
        XCTAssertTrue(p.link.hasPrefix("nuvio://auth/guptrack?"))
        XCTAssertEqual(p.expiryLine(), "Works for 10 more minutes")
        XCTAssertEqual(p.expiryLine(now: p.expires), "This code has run out")
        let check = try await api.checkDevicePairing(code: p.code)
        XCTAssertNil(check.device)
        XCTAssertFalse(check.expired)
        let summary = await api.settingsSummary(owner: true)
        XCTAssertEqual(summary.connectedValue, "Harbor, GupTrack")
        XCTAssertEqual(summary.accounts, 5)
        XCTAssertEqual(summary.backupValue, "Yesterday", "last night's, at 3am UTC")
    }

    func testImportExportBackupsAccountsFixtures() async throws {
        let api = demo()
        let job = try await api.importAniList("mika_watches")
        XCTAssertEqual(job.phase, "ready")
        XCTAssertFalse(job.running)
        XCTAssertEqual(job.phaseLine, "Ready to import")
        XCTAssertEqual(job.plan.map(\.media), [.anime, .manga])
        XCTAssertEqual(job.openMisses.count, 2)
        let again = try await api.importJob(job.id)
        XCTAssertEqual(again, job)
        let fixed = try await api.skipImported(job.id, key: job.unmatched[0].key)
        XCTAssertEqual(fixed.openMisses.count, 1)
        let done = try await api.commitImport(job.id)
        XCTAssertEqual(done?.phaseLine, "Imported")
        XCTAssertEqual(done?.resultLine, "21 new, 7 updated, 456 unchanged, 2 kept as you have them")

        for kind in ExportKind.allCases {
            let f = try await api.exportFile(kind)
            XCTAssertFalse(f.name.isEmpty, kind.rawValue)
        }
        let backup = try await api.exportBackup()
        XCTAssertEqual(backup["format"]?.string, "guptrack-backup")

        let saved = try await api.savedBackups()
        XCTAssertEqual(saved.saved.first?.label, "Before a restore")
        let nightly = try await api.nightlyBackups()
        XCTAssertTrue(nightly.enabled)
        XCTAssertEqual(nightly.backups.map { SettingsText.size($0.size) }, ["1.8 MB", "1.8 MB", "1.8 MB"])
        let now = try await api.backUpNow()
        XCTAssertNil(now.made)
        let r = try await api.restoreNightly(nightly.backups[1].name)
        XCTAssertEqual(r.line, "Restored 486 titles. What you had is kept under Saved backups.")

        let accounts = try await api.accounts()
        XCTAssertEqual(accounts.accounts.map(\.username), ["mika", "kenji", "noor.reads", "tobiwan", "lena"])
        XCTAssertEqual(accounts.invites.map { $0.state() }, ["Open until Nov 9", "Used by @lena"])
        let invite = try await api.createInvite()
        XCTAssertTrue(invite.code.hasPrefix("demo-"))
        XCTAssertEqual(invite.link(on: Demo.server), "https://guptrack.example/join?code=demo-invite-5")
    }

    // MARK: the doc's shapes

    func testDocShapedAnswersDecode() throws {
        let d = try APIClient.decoder.decode(DeviceList.self, from: Data(#"""
        {"devices":[{"id":3,"scope":"app","app":"GupTrack","name":"iPhone","platform":"iOS 26.1","createdAt":1,"lastUsedAt":null},
        {"id":4,"scope":"sync","app":"Harbor","name":"PC","platform":"Windows","createdAt":2,"lastUsedAt":5}],"current":3}
        """#.utf8))
        XCTAssertEqual(d.this?.id, 3)
        XCTAssertEqual(d.others.first?.id, 4)

        let a = try APIClient.decoder.decode(AccountInfo.self, from: Data(#"""
        {"username":"a","role":"member","recovery":{"total":10,"left":10,"createdAt":1,"lastUsed":null},
         "sessions":[{"id":"s","createdAt":1,"lastSeen":2,"expiresAt":3,"userAgent":null,"ip":null,"current":true}],
         "passkeys":[],"devices":[],"serverTime":4}
        """#.utf8))
        XCTAssertEqual(a.sessions[0].name, "A browser")
        XCTAssertEqual(a.passkeyLine, "No passkeys")

        let p = try APIClient.decoder.decode(PrivacySettings.self, from: Data(#"""
        {"visibility":"friends","lists":{"anime":"public"},"comments":"nobody"}
        """#.utf8))
        XCTAssertEqual(p.list(.anime), .public)
        XCTAssertEqual(p.list(.manga), .friends, "a list without its own setting follows the profile")

        let job = try APIClient.decoder.decode(ImportJobAnswer.self, from: Data(#"""
        {"job":{"id":"j","source":"letterboxd","name":"x","phase":"matching","done":5,"total":20,"started":1,"plan":[],
         "unmatched":[],"matches":{"high":1,"medium":0,"low":0},"check":[],"conflicts":[]}}
        """#.utf8))
        XCTAssertEqual(job.job?.phaseLine, "Matching titles · 5 of 20")
        XCTAssertEqual(job.job?.progress, 0.25)
        XCTAssertNil(try APIClient.decoder.decode(ImportJobAnswer.self, from: Data(#"{"job":null}"#.utf8)).job)

        let info = try APIClient.decoder.decode(AutoBackupInfo.self, from: Data(#"""
        {"enabled":false,"backups":[],"bytes":0,"checkedAt":null,"nextAt":null}
        """#.utf8))
        XCTAssertFalse(info.enabled)

        let r = try APIClient.decoder.decode(RestoreAnswer.self, from: Data(#"""
        {"restored":1,"saved":{"name":"before-restore-20261103T144100Z.json","reason":"restore","at":1}}
        """#.utf8))
        XCTAssertEqual(r.line, "Restored 1 title. What you had is kept under Saved backups.")

        let inv = try APIClient.decoder.decode(NewInvite.self, from: Data(#"""
        {"code":"abc","invite":{"id":1,"createdAt":1,"expiresAt":2,"usedAt":null,"usedBy":null}}
        """#.utf8))
        XCTAssertEqual(inv.invite.state(), "Expired")
    }

    // MARK: the calls

    func testCallsSendTheDocsRequests() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "t")
        func last() -> APIRequest? { t.sent.last }

        t.reply(#"{"visibility":"public","lists":{},"comments":"friends"}"#)
        _ = try await api.setVisibility(VisibilityBody(visibility: .friends, media: .movies))
        XCTAssertEqual(last()?.method, "PUT")
        XCTAssertEqual(last()?.path, "settings/privacy/visibility")
        XCTAssertEqual(body(last()), #"{"media":"movies","visibility":"friends"}"#)
        XCTAssertNotNil(last()?.requestId)

        t.reply(#"{"setting":"nobody"}"#)
        _ = try await api.setCommentSetting("nobody")
        XCTAssertEqual(body(last()), #"{"setting":"nobody"}"#)

        t.reply(#"{"messages":"everyone"}"#)
        _ = try await api.setSettingsMessages("everyone")
        XCTAssertEqual(last()?.path, "settings/messages")
        XCTAssertEqual(last()?.method, "PUT")

        t.reply(#"{"profile":{"name":"","avatar":"/media/a.webp","bio":null,"joined":1}}"#)
        let up = try await api.uploadAvatar(Data([0xFF, 0xD8]), contentType: "image/jpeg")
        XCTAssertEqual(up.profile.avatar, "/media/a.webp")
        XCTAssertEqual(last()?.path, "settings/profile/avatar")
        XCTAssertEqual(last()?.method, "POST")
        XCTAssertEqual(last()?.contentType, "image/jpeg")
        _ = try await api.removeBanner()
        XCTAssertEqual(last()?.method, "DELETE")
        XCTAssertEqual(last()?.path, "settings/profile/banner")

        // the secret calls never carry X-Request-Id (§4.4, §12.7)
        t.reply(#"{"token":"demo-new","device":{"id":1,"scope":"app","app":"GupTrack","name":"iPhone","platform":"iOS","createdAt":1,"lastUsedAt":null},"user":{"username":"a","role":"member"},"serverTime":1}"#)
        let signIn = try await api.changePassword(current: "old pass", next: "new pass")
        XCTAssertEqual(signIn.token, "demo-new")
        XCTAssertEqual(last()?.path, "account/password")
        XCTAssertEqual(body(last()), #"{"current":"old pass","next":"new pass"}"#)
        XCTAssertNil(last()?.requestId)

        t.reply(#"{"codes":["a","b"]}"#)
        _ = try await api.newRecoveryCodes(password: "pw")
        XCTAssertEqual(last()?.path, "account/recovery-codes")
        XCTAssertEqual(body(last()), #"{"password":"pw"}"#)
        XCTAssertNil(last()?.requestId)

        t.reply(#"{"code":"7KQ4-M2XD","expiresAt":1,"ttl":600,"server":"https://h","link":"guptrack://pair?code=7KQ4-M2XD"}"#)
        _ = try await api.startPairing(for: .app)
        XCTAssertEqual(last()?.path, "devices/pairing")
        XCTAssertEqual(body(last()), #"{"for":"app"}"#)
        XCTAssertNil(last()?.requestId)

        t.reply(#"{"code":"x","invite":{"id":1,"createdAt":1,"expiresAt":2,"usedAt":null,"usedBy":null}}"#)
        _ = try await api.createInvite()
        XCTAssertEqual(last()?.path, "accounts/invites")
        XCTAssertNil(last()?.requestId)

        t.reply(#"{"device":null,"expired":true}"#)
        _ = try await api.checkDevicePairing(code: "7KQ4-M2XD")
        XCTAssertEqual(last()?.path, "devices/pairing/check")
        XCTAssertEqual(body(last()), #"{"code":"7KQ4-M2XD"}"#)

        t.reply(#"{"ok":true}"#)
        _ = try await api.disconnectDevice(7)
        XCTAssertEqual(last()?.method, "DELETE")
        XCTAssertEqual(last()?.path, "devices/7")
        try await api.endSession("abc")
        XCTAssertEqual(last()?.path, "account/sessions/abc/end")
        try await api.signOutEverywhere()
        XCTAssertEqual(last()?.path, "account/sign-out-everywhere")
        try await api.takeBackInvite(4)
        XCTAssertEqual(last()?.method, "DELETE")
        XCTAssertEqual(last()?.path, "accounts/invites/4")

        let job = #"{"id":"j","source":"anilist","name":"x","phase":"ready","done":0,"total":0,"started":1,"plan":[],"unmatched":[]}"#
        t.reply(job)
        _ = try await api.importAniList("someone")
        XCTAssertEqual(body(last()), #"{"name":"someone"}"#)
        _ = try await api.importFiles(.letterboxd, [FileImportBody.file(name: "watched.csv", data: Data("a,b".utf8)),
                                                   FileImportBody.file(name: "x.bin", data: Data([0xFF, 0xFE, 0x00]))])
        XCTAssertEqual(last()?.path, "import/file")
        XCTAssertEqual(body(last()),
                       #"{"files":[{"data":"a,b","name":"watched.csv"},{"base64":true,"data":"\/\/4A","name":"x.bin"}],"source":"letterboxd"}"#)
        _ = try await api.skipImported("j", key: "anime:1")
        XCTAssertEqual(last()?.path, "import/j/fix")
        XCTAssertEqual(body(last()), #"{"key":"anime:1","skip":true}"#)
        t.reply(#"{"job":\#(job)}"#)
        _ = try await api.commitImport("j")
        XCTAssertEqual(last()?.path, "import/j/commit")
        XCTAssertEqual(body(last()), "{}")

        t.reply(#"{"restored":1,"saved":{"name":"n","reason":"restore","at":1}}"#)
        _ = try await api.restoreBackup(Data("{}".utf8))
        XCTAssertEqual(last()?.path, "backups/restore")
        XCTAssertEqual(last()?.contentType, "application/json")
        _ = try await api.restoreSaved("before-restore-1.json")
        XCTAssertEqual(last()?.path, "backups/saved/before-restore-1.json/restore")

        t.reply(#"{"enabled":true,"backups":[],"bytes":0,"checkedAt":null,"nextAt":null}"#)
        _ = try await api.setNightly(true)
        XCTAssertEqual(last()?.method, "PUT")
        XCTAssertEqual(body(last()), #"{"enabled":true}"#)
    }

    func testWrongPasswordIsAnOrdinaryError() async {
        let t = StubTransport()
        t.reply(#"{"error":"wrong_password","message":"That isn't your password.","serverTime":1}"#, 401)
        await assertThrows(APIError.server(401, "wrong_password", "That isn't your password.")) {
            _ = try await APIClient(transport: t, token: "t").newRecoveryCodes(password: "x")
        }
    }

    // MARK: saving

    func testChangesHaveOnlyWhatChanged() async throws {
        let old = try await demo().accountSettings()
        var new = old
        new.prefs.theme = "ocean"
        new.prefs.notify.sequels = false
        new.profile.name = "Mika R."
        new.privacy.lists["tv"] = .public
        new.messages = "nobody"
        let changes = AccountSettings.changes(from: old, to: new)
        XCTAssertEqual(changes, [
            .prefs(try json(#"{"notify":{"sequels":false},"theme":"ocean"}"#)),
            .profile(ProfilePatch(name: "Mika R.")),
            .visibility(VisibilityBody(visibility: .public, media: .tv)),
            .messages("nobody"),
        ])
        XCTAssertEqual(AccountSettings.changes(from: old, to: old), [])

        var bio = new
        bio.bio.banner.fade.strength = 40
        guard case .profile(let p)? = AccountSettings.changes(from: new, to: bio).first else { return XCTFail() }
        XCTAssertNil(p.name)
        XCTAssertEqual(p.bio?["banner"]?["fade"]?["strength"]?.double, 40)
        XCTAssertEqual(p.bio?["banner"]?["src"], bio.profile.bio?["banner"]?["src"])
    }

    @MainActor
    func testStoreSavesEachEndpointAndAdoptsTheAnswers() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "demo")
        let store = AccountSettingsStore()
        store.loaded(try await api.accountSettings(), for: "mika")
        XCTAssertFalse(store.needsLoad(for: "mika"))
        XCTAssertTrue(store.needsLoad(for: "kenji"))
        store.edit { $0.prefs.adult = true; $0.privacy.comments = "nobody" }
        XCTAssertEqual(store.pendingChanges.count, 2)
        let before = transport.requests.count
        try await store.save(using: api)
        let sent = transport.requests.dropFirst(before)
        XCTAssertEqual(sent.map { "\($0.method) \($0.path)" }, ["PATCH settings/prefs", "PUT settings/privacy/comments"])
        XCTAssertEqual(body(sent.first), #"{"adult":true}"#)
        // the demo's server keeps what was written, and the store takes its answers
        XCTAssertEqual(store.settings?.prefs.adult, true)
        XCTAssertEqual(store.saved?.prefs.adult, true)
        XCTAssertEqual(store.saved?.privacy.comments, "nobody")
        XCTAssertTrue(store.pendingChanges.isEmpty)
    }

    @MainActor
    func testStoreAdoptsAnAnswerThatDiffers() async throws {
        let transport = DemoTransport()
        transport.handle("PUT", "settings/privacy/comments") { _ in DemoTransport.json(CommentSettingBody(setting: "friends")) }
        let api = APIClient(transport: transport, token: "demo")
        let store = AccountSettingsStore()
        store.loaded(try await api.accountSettings(), for: "mika")
        store.edit { $0.privacy.comments = "nobody" }
        try await store.save(using: api)
        XCTAssertEqual(store.settings?.privacy.comments, "nobody", "the shown copy keeps an edit the answer didn't touch")
        XCTAssertEqual(store.saved?.privacy.comments, "friends")
    }

    /// the demo's pairing code is live when it's made (it ran out on screen when it kept the file's time)
    func testDemoPairingCodeIsLive() async throws {
        let p = try await demo().startPairing(for: .harbor)
        XCTAssertGreaterThan(p.expiresAt, Millis.of(Clock.now))
        XCTAssertEqual(p.code, "7KQ4-M2XD")
    }

    @MainActor
    func testDemoKeepsPrivacyWrites() async throws {
        let api = APIClient(transport: DemoTransport(), token: "demo")
        let store = AccountSettingsStore()
        store.loaded(try await api.accountSettings(), for: "mika")
        store.edit { $0.privacy.visibility = .private; $0.privacy.lists["tv"] = .public; $0.messages = "nobody" }
        try await store.save(using: api)
        XCTAssertTrue(store.pendingChanges.isEmpty)
        XCTAssertEqual(store.saved?.privacy.visibility, .private)
        XCTAssertEqual(store.saved?.privacy.lists["tv"], .public)
        let again = try await api.accountSettings()
        XCTAssertEqual(again.privacy.visibility, .private)
        XCTAssertEqual(again.privacy.lists["tv"], .public)
        XCTAssertEqual(again.messages, "nobody")
    }

    // MARK: the bio

    func testEmptyBioHasTheWebsitesDefaults() {
        let b = BioState(nil)
        XCTAssertEqual(b, .empty)
        XCTAssertNil(b.banner.src)
        XCTAssertEqual(b.banner.aspect, 6.5)
        XCTAssertEqual(b.style, .standard)
        XCTAssertEqual(b.doc, BioState.emptyDoc)
        // a partial bio keeps the given keys and fills the rest
        let partial = BioState(.object(["banner": .object(["src": .string("/media/b.webp"), "fade": .object(["on": .bool(false)])])]))
        XCTAssertEqual(partial.banner.src?.relativeString, "/media/b.webp", "GupTrack's own addresses stay relative")
        XCTAssertFalse(partial.banner.fade.on)
        XCTAssertEqual(partial.banner.fade.strength, 74)
        XCTAssertEqual(partial.json["banner"]?["src"]?.string, "/media/b.webp")
        XCTAssertEqual(BioState.empty.json["banner"]?["src"], .null, "no banner is written as null")
    }

    func testPresetsAreTheWebsitesLooks() {
        XCTAssertEqual(BioPreset.allCases.count, 10)
        XCTAssertEqual(Set(BioPreset.allCases.map(\.style)).count, 10, "every preset looks different")
        XCTAssertEqual(BioPreset.letter.style.frame, "panel")
        XCTAssertEqual(BioPreset.credits.style.align, "center")
        XCTAssertNil(BioPreset.matching(.standard))
    }

    func testBioDocumentRoundTripsTheDemoBio() async throws {
        let doc = try await demo().accountSettings().bio.doc
        let d = BioDocument(doc: doc)
        XCTAssertEqual(d.blocks.count, 3)
        guard d.blocks.count == 3, case .text(let first) = d.blocks[0], case .list(let list) = d.blocks[1],
              case .text(let after) = d.blocks[2] else { return XCTFail("text, list, text") }
        XCTAssertEqual(first, "Seasonal anime, slow manga, one book a month.\nWatching **Frieren** every Friday. Comfort rewatch: *Code Geass*.\n## On repeat")
        XCTAssertEqual(list.source, "favourites")
        XCTAssertEqual(list.heading, "Favourite anime")
        XCTAssertFalse(list.showHeading)
        XCTAssertEqual(after, "> Ask me about the long ones.")
        XCTAssertEqual(BioMarkdown.normal(d.doc), BioMarkdown.normal(doc), "editing nothing changes nothing")
    }

    func testBioMarkdownToTiptap() throws {
        let nodes = BioMarkdown.nodes("# Hi\n- a\n- **b**\n1. one\n2. two\n> q\n>\n---\n\nsee [here](https://x.example)")
        XCTAssertEqual(nodes.map { $0["type"]?.string ?? "" },
                       ["heading", "bulletList", "orderedList", "blockquote", "horizontalRule", "paragraph", "paragraph"])
        XCTAssertEqual(nodes[1]["content"]?.array?.count, 2)
        XCTAssertEqual(nodes[3]["content"]?.array?.count, 2, "a bare > is an empty quote line")
        XCTAssertEqual(nodes[5], .object(["type": .string("paragraph")]), "a blank line is an empty paragraph")
        XCTAssertEqual(nodes[6]["content"]?.array?[1]["marks"], try json(#"[{"type":"link","attrs":{"href":"https://x.example"}}]"#))
        XCTAssertEqual(BioMarkdown.inline("***both***"),
                       [try json(#"{"type":"text","text":"both","marks":[{"type":"bold"},{"type":"italic"}]}"#)])
        XCTAssertEqual(BioMarkdown.inline("a * b"), [try json(#"{"type":"text","text":"a * b"}"#)])
    }

    func testBioKeepsWhatThePhoneCantEdit() throws {
        let doc = try json(#"""
        {"type":"doc","content":[
          {"type":"paragraph","attrs":{"textAlign":"center"},"content":[{"type":"text","text":"centred"}]},
          {"type":"paragraph","content":[{"type":"text","text":"red","marks":[{"type":"textStyle","attrs":{"color":"red"}}]}]},
          {"type":"image","attrs":{"src":"/media/p.webp"}},
          {"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"a"}]}]}]},
          {"type":"bulletList","content":[{"type":"listItem","content":[{"type":"paragraph","content":[{"type":"text","text":"b"}]}]}]}
        ]}
        """#)
        let d = BioDocument(doc: doc)
        XCTAssertEqual(d.blocks.count, 5)
        guard case .kept(let centred) = d.blocks[0], case .kept = d.blocks[1], case .kept(let picture) = d.blocks[2] else {
            return XCTFail("styled text and pictures are kept as they are")
        }
        XCTAssertEqual(BioDocument.keptLabel(centred), "Styled text")
        XCTAssertEqual(BioDocument.keptLabel(picture), "A picture")
        XCTAssertEqual(d.blocks[3], .text("- a"))
        XCTAssertEqual(d.blocks[4], .text("- b"), "two lists in a row stay two lists")
        XCTAssertEqual(BioMarkdown.normal(d.doc), BioMarkdown.normal(doc))
    }

    func testBioInsertAndRemoveList() {
        var d = BioDocument(doc: BioState.emptyDoc)
        XCTAssertEqual(d.blocks, [.text("")])
        XCTAssertEqual(d.doc, BioState.emptyDoc)
        d.blocks[0] = .text("Hello")
        let list = BioList.make(source: "current", media: .anime)
        XCTAssertEqual(list.heading, "Currently watching")
        XCTAssertEqual(BioList.make(source: "current", media: nil).heading, "Currently watching & reading")
        XCTAssertEqual(BioList.make(source: "completed", media: .books).heading, "Recently finished books")
        XCTAssertEqual(BioList.make(source: "current", media: .manga).heading, "Currently reading")
        d.insert(list, after: 0)
        XCTAssertEqual(d.blocks, [.text("Hello"), .list(list), .text("")])
        XCTAssertEqual(d.doc["content"]?.array?.map { $0["type"]?.string ?? "" }, ["paragraph", "listBlock"])
        XCTAssertEqual(d.doc["content"]?.array?[1]["attrs"]?["count"]?.int, 8)
        d.blocks[2] = .text("Bye")
        d.remove(at: 1)
        XCTAssertEqual(d.blocks, [.text("Hello\nBye")])
    }

    func testBioListTitlesFromTheLibrary() {
        let lib = Demo.library()
        let current = BioList.make(source: "current", media: .anime).titles(lib)
        XCTAssertFalse(current.isEmpty)
        XCTAssertTrue(current.allSatisfy { $0.media == .anime })
        XCTAssertLessThanOrEqual(current.count, 8)
        XCTAssertTrue(BioList.make(source: "characters", media: nil).titles(lib).isEmpty)
        XCTAssertFalse(BioList.make(source: "characters", media: nil).showsTitles)
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
        let lines = BioDocument.lines("# Title\n## Sub\n- item\n3. third\n> said\n---\n\nWatching **SBR** every *Friday*, [here](https://x)")
        XCTAssertEqual(lines.map(\.kind), [.heading1, .heading2, .bullet, .numbered(3), .quote, .rule, .blank, .body])
        XCTAssertEqual(lines[7].plain, "Watching SBR every Friday, here")
    }

    // MARK: text helpers

    func testScoreFormatExamples() {
        XCTAssertEqual(ScoreFormat.allCases.map(\.example), ["8", "8.5", "85", "★★★★☆", "🙂"])
        XCTAssertEqual(ScoreFormat.point10Decimal.show(70), "7")
        XCTAssertEqual(ScoreFormat.stars5.show(100), "★★★★★")
        XCTAssertEqual(ScoreFormat.stars5.show(0), "☆☆☆☆☆")
        XCTAssertEqual(ScoreFormat.smiley3.show(50), "😐")
        XCTAssertEqual(ScoreFormat.smiley3.show(20), "🙁")
        XCTAssertEqual(ScoreFormat.point100.show(140), "100")
    }

    func testDateStyles() {
        XCTAssertEqual(DateStyle.allCases.map { $0.show(Clock.now) },
                       ["Nov 3, 2026", "3 Nov 2026", "11/03/2026", "03/11/2026", "2026-11-03"])
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
        XCTAssertEqual(Set(SettingsThemes.all.map(\.key)).count, 18, "keys are unique")
        XCTAssertEqual(SettingsThemes.look("system")?.name, "Match system")
        XCTAssertTrue(SettingsThemes.look("system")!.split)
        XCTAssertEqual(SettingsThemes.look("rose")?.name, "Rosé")
        XCTAssertNotNil(SettingsThemes.look("neon")!.accent2)
        XCTAssertNil(SettingsThemes.look("Midnight"), "Prefs.theme holds keys, not names")
    }
}
