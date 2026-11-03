import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The sheets over a title page: the list editor's draft (18, 19), lists to tick (26), a review (27), send-to (53).
final class SheetsTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { Demo.library() }

    private func entry(_ id: String) throws -> LibraryEntry {
        try XCTUnwrap(try library().first { $0.id == id })
    }

    private let today = "2026-11-03"

    // MARK: editor

    func testUntouchedDraftSendsNothing() throws {
        let e = try entry("anime:210482")
        let d = TitleSheets.EditorDraft(entry: e)
        XCTAssertTrue(d.patch.isEmpty)
        XCTAssertFalse(d.hasChanges)
        XCTAssertEqual(d.progressCaption, "Episode \(e.progress) of 11")
        XCTAssertEqual(d.unitWord, "Episode")
    }

    func testStepsScoreAndFavouriteMakeOnePatch() throws {
        let e = try entry("anime:210482")
        XCTAssertNil(e.score)
        var d = TitleSheets.EditorDraft(entry: e)
        d.step(1)
        d.pickScore(6)
        d.favourite = true
        XCTAssertEqual(d.patch, LibraryPatch(status: .current, progress: e.progress + 1, score: 60, favourite: true))
        d.pickScore(6)
        XCTAssertNil(d.score, "tapping the chosen dot clears the score")
        XCTAssertNil(d.patch.score, "it was unscored, so clearing changes nothing")
    }

    func testClearingAScoreSendsMinusOne() throws {
        let scored = try XCTUnwrap(try library().first { $0.media == .anime && $0.score != nil })
        var d = TitleSheets.EditorDraft(entry: scored)
        let dot = try XCTUnwrap(d.scoreDot)
        d.pickScore(dot)
        XCTAssertEqual(d.patch, LibraryPatch(score: -1))
    }

    func testScoreDotsRoundHalfUp() {
        XCTAssertEqual(TitleSheets.scoreDot(85), 9)
        XCTAssertEqual(TitleSheets.scoreDot(80), 8)
        XCTAssertEqual(TitleSheets.scoreDot(100), 10)
        XCTAssertNil(TitleSheets.scoreDot(nil))
        XCTAssertNil(TitleSheets.scoreDot(0))
        XCTAssertEqual(TitleSheets.pick(9, current: 85), nil)
        XCTAssertEqual(TitleSheets.pick(3, current: 85), 30)
    }

    func testLastEpisodeCompletesWithTodaysDate() throws {
        var d = TitleSheets.EditorDraft(entry: try entry("anime:210482"))
        d.setProgress(11, today: today)
        XCTAssertEqual(d.status, .completed)
        XCTAssertEqual(d.finished, today)
        XCTAssertFalse(d.canStepUp)
        d.step(1, today: today)
        XCTAssertEqual(d.progress, 11, "progress stops at the total")
        XCTAssertEqual(d.patch.status, .completed)
        XCTAssertEqual(d.patch.finished, today)
    }

    func testCompletingFillsProgress() throws {
        let e = try entry("anime:210482")
        var d = TitleSheets.EditorDraft(entry: e)
        d.setStatus(.completed, today: today)
        XCTAssertEqual(d.progress, 11)
        XCTAssertEqual(d.finished, today)
        XCTAssertEqual(d.started, e.started, "an existing start stays")
    }

    func testStartingAPlannedTitle() throws {
        let planned = try XCTUnwrap(try library().first { $0.media == .anime && $0.status == .planned })
        var d = TitleSheets.EditorDraft(entry: planned)
        d.step(1, today: today)
        XCTAssertEqual(d.status, .current)
        XCTAssertEqual(d.started, today)
        XCTAssertEqual(d.patch, LibraryPatch(status: .current, progress: 1, started: today))
    }

    func testBooksStepByTenPages() throws {
        let b = try XCTUnwrap(try library().first { $0.media == .book && $0.status == .current })
        var d = TitleSheets.EditorDraft(entry: b)
        d.step(1)
        XCTAssertEqual(d.progress, b.progress + 10)
        XCTAssertTrue(d.progressCaption.hasPrefix("Page \(b.progress + 10)"))
    }

    func testMangaVolume() throws {
        let manga = try entry("manga:105778")
        var m = TitleSheets.EditorDraft(entry: manga)
        m.stepVolume(1)
        XCTAssertEqual(m.patch, LibraryPatch(volume: (manga.volume ?? 0) + 1))
    }

    func testFilmsHaveNoProgress() throws {
        let film = try XCTUnwrap(try library().first { $0.media == .movie && $0.status == .planned })
        var d = TitleSheets.EditorDraft(entry: film)
        XCTAssertFalse(d.hasProgress)
        d.setStatus(.completed, today: today)
        XCTAssertEqual(d.patch, LibraryPatch(status: .completed, progress: 1, finished: today))
    }

    func testDatesNotesAndRewatches() throws {
        var d = TitleSheets.EditorDraft(entry: try entry("anime:210482"))
        XCTAssertEqual(TitleSheets.EditorDraft.dateText("2026-09-14"), "Sep 14, 2026")
        XCTAssertNil(TitleSheets.EditorDraft.dateText(nil))
        d.started = nil
        d.finished = "2026-11-01"
        d.notes = "  on Friday nights \n"
        d.stepRepeats(1)
        d.stepRepeats(-5)
        XCTAssertEqual(d.repeats, 0)
        d.stepRepeats(1)
        XCTAssertEqual(d.patch, LibraryPatch(repeats: 1, started: "", finished: "2026-11-01",
                                             notes: "on Friday nights"))
    }

    func testANewTitleGoesOnWithItsStatus() throws {
        let t = Title(id: "anime:1", media: .anime, name: "Cowboy Bebop", total: 26)
        var d = TitleSheets.EditorDraft(title: t)
        XCTAssertTrue(d.isNew)
        XCTAssertTrue(d.hasChanges)
        XCTAssertEqual(d.patch, LibraryPatch(status: .planned))
        d.setStatus(.current, today: today)
        d.pickScore(9)
        XCTAssertEqual(d.patch, LibraryPatch(status: .current, score: 90, started: today))
    }

    /// The library feed carries no next episode (§7.1), so the line shows only for a title that has one.
    func testNextLine() throws {
        var e = try entry("anime:210482")
        XCTAssertNil(e.title.next)
        XCTAssertNil(TitleSheets.EditorDraft(entry: e).nextLine)
        e.title.next = Airing(episode: 8, at: Clock.demoNow.addingTimeInterval(86_400))
        XCTAssertEqual(TitleSheets.EditorDraft(entry: e).nextLine, "Ep 8 airs tomorrow")
        e.title.next = Airing(episode: 8, at: Clock.demoNow.addingTimeInterval(-60))
        XCTAssertNil(TitleSheets.EditorDraft(entry: e).nextLine, "already out")
    }

    // MARK: add to a list

    func testListChoicesFixtureAndPicks() throws {
        let choices = try Demo.load(ListWire.Choices.self, "api/titles/anime/210482/lists.json")
        XCTAssertEqual(choices.profile, .public)
        let lists = Dictionary(uniqueKeysWithValues: try ["rainy-sundays", "start-here"].map {
            let l = try Demo.load(MyList.self, "api/lists/\($0).json").customList()
            return (l.id, l)
        })
        var p = TitleSheets.ListPicks(titleId: "anime:210482", choices: choices)
        XCTAssertEqual(choices.lists.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(choices.lists.filter { p.isOn($0.id) }.map(\.id), [1, 2, 3], "SBR is on three lists already")
        XCTAssertTrue(p.changes.isEmpty)
        let rainy = choices.lists[0], start = choices.lists[3]
        XCTAssertEqual(p.caption(rainy, list: lists["1"]), "12 titles · Public")
        p.toggle(start.id)
        p.toggle(rainy.id)
        XCTAssertEqual(p.count(start, list: lists["4"]), 5)
        XCTAssertEqual(p.count(rainy, list: lists["1"]), 11)
        XCTAssertNil(p.caption(rainy, list: nil), "no count without the phone's copy")
        XCTAssertEqual(p.changes.map { "\($0.listId):\($0.add)" }, ["1:false", "4:true"])
        p.made(5, name: "Winter evenings")
        XCTAssertEqual(p.choices.first?.name, "Winter evenings")
        XCTAssertTrue(p.isOn(5))
        XCTAssertEqual(p.changes.count, 2, "a list made with the title on it is already saved")
    }

    func testListChoicesDecodeTheDocShape() throws {
        let json = #"{"profile":"friends","lists":[{"id":7,"name":"Cozy","has":false,"extra":1}]}"#
        let c = try APIClient.decoder.decode(ListWire.Choices.self, from: Data(json.utf8))
        XCTAssertEqual(c.profile, .friends)
        XCTAssertEqual(c.lists, [ListWire.Choice(id: 7, name: "Cozy", has: false)])
    }

    // MARK: review

    func testReviewDraft() throws {
        var r = TitleSheets.ReviewDraft(score: 85)
        XCTAssertEqual(r.scoreText, "8.5 / 10")
        XCTAssertFalse(r.canPost)
        r.text = String(repeating: "a", count: 196)
        XCTAssertEqual(r.countText, "196 / 10,000")
        XCTAssertTrue(r.canPost)
        r.pickScore(9)
        XCTAssertNil(r.score, "85 shows as 9, so tapping 9 clears it")
        r.pickScore(10)
        XCTAssertEqual(r.score, 100)
        r.text = String(repeating: "a", count: 10_001)
        XCTAssertFalse(r.canPost)
        r.text = "  Still great.  "
        r.spoilers = true
        let t = Title(id: "manga:105778", media: .manga, name: "Chainsaw Man",
                      cover: URL(string: "https://s4.anilist.co/file/x.jpg"), format: "Manga")
        let json = String(decoding: try APIClient.encoder.encode(r.body(t)), as: UTF8.self)
        XCTAssertEqual(json, #"{"body":"Still great.","meta":{"cover":"https:\/\/s4.anilist.co\/file\/x.jpg","format":"Manga","title":"Chainsaw Man"},"spoiler":true}"#)
        var own = t
        own.cover = URL(string: "/media/covers/1.jpg")
        own.format = nil
        XCTAssertEqual(r.body(own).meta, .init(title: "Chainsaw Man", cover: "", format: ""), "https covers only")
    }

    func testMyReviewDecodesTitleReviews() throws {
        let json = #"{"mine":{"id":3,"body":"Loved it","spoiler":false,"score":90,"at":1},"reviews":[],"visibility":"friends"}"#
        let r = try APIClient.decoder.decode(TitleSheets.MyReview.self, from: Data(json.utf8))
        XCTAssertEqual(r.mine, .init(body: "Loved it", spoiler: false))
        XCTAssertEqual(r.visibility, .friends)
        let none = try APIClient.decoder.decode(TitleSheets.MyReview.self,
                                                from: Data(#"{"mine":null,"reviews":[],"visibility":"public"}"#.utf8))
        XCTAssertNil(none.mine)
    }

    func testReviewLine() throws {
        let e = try entry("manga:105778")
        let line = TitleSheets.reviewLine(e.title, entry: e)
        XCTAssertEqual(line.kind, "Manga")
        XCTAssertEqual(line.status, .current)
        XCTAssertEqual(line.progress, "Ch \(e.progress)")
    }

    // MARK: send to

    func testRecipientsFixtureAndPicks() throws {
        let page = try Demo.load(TitleSheets.Recipients.self, "api/messages/recipients.json").recipients
        XCTAssertEqual(page.map(\.username), ["kenji", "noor.reads", "tobiwan", "lena", "sorawatches", "hal"])
        XCTAssertTrue(page.allSatisfy(\.canSend))
        var p = TitleSheets.SendPicks()
        XCTAssertFalse(p.canSend)
        p.toggle("tobiwan")
        p.toggle("kenji")
        XCTAssertEqual(p.sendLabel, "Send 2")
        XCTAssertEqual(p.to(page), ["kenji", "tobiwan"], "in the sheet's order")
        XCTAssertEqual(p.body("anime:210482"),
                       TitleSheets.MessageBody(body: nil, card: .init(kind: "anime", id: "210482", mine: false)))
        p.message = " watch the first three, trust me "
        let json = String(decoding: try APIClient.encoder.encode(p.body("movie:603")), as: UTF8.self)
        XCTAssertEqual(json, #"{"body":"watch the first three, trust me","card":{"id":"603","kind":"movie","mine":false}}"#)
        p.toggle("kenji")
        XCTAssertEqual(p.picked, ["tobiwan"])
        p.query = "NOOR"
        XCTAssertEqual(p.shown(page).map(\.username), ["noor.reads"])
    }

    func testTitleDetailGivesTheSheetItsTitle() throws {
        let json = #"{"title":{"ref":{"kind":"anime","id":"210482"},"media":"anime","title":"Steel Ball Run","alt":["JoJo Part 7"],"cover":"/media/covers/a.jpg","banner":null,"format":"TV","status":"RELEASING","statusText":"Airing","year":2026,"count":11,"minutes":24,"genres":[]}}"#
        let t = try XCTUnwrap(try APIClient.decoder.decode(TitleSheets.TitleLookup.self, from: Data(json.utf8)).sheetTitle())
        XCTAssertEqual(t.id, "anime:210482")
        XCTAssertEqual(t.total, 11)
        XCTAssertEqual(t.subtitle, "JoJo Part 7")
        XCTAssertEqual(t.cover?.absoluteString, "/media/covers/a.jpg", "GupTrack's own address stays as it came")
        XCTAssertEqual(TitleSheets.path("movie:603"), "titles/movie/603")
    }

    func testSummary() {
        let t = Title(id: "anime:210482", media: .anime, name: "SBR", season: "Fall 2026", total: 11)
        XCTAssertEqual(TitleSheets.summary(t), "Anime · 11 episodes · Fall 2026")
    }
}

@MainActor
final class SheetsModelTests: XCTestCase {
    override func tearDown() {
        Demo.args = ["app"]
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func model() async -> AppModel {
        Demo.args = ["app", "-demo"]
        let m = AppModel.make()
        await m.refresh()
        return m
    }

    func testSaveChangesTheEntryAndDiscardDoesNot() async throws {
        let m = await model()
        let id = "anime:210482"
        let before = try XCTUnwrap(m.entry(id))
        var d = TitleSheets.EditorDraft(entry: before)
        d.step(1)
        d.pickScore(6)
        // ✕: the draft goes away, nothing changes
        XCTAssertEqual(m.entry(id), before)
        XCTAssertTrue(d.save(to: m))
        let after = try XCTUnwrap(m.entry(id))
        XCTAssertEqual(after.progress, before.progress + 1)
        XCTAssertEqual(after.score, 60)
        XCTAssertEqual(after.status, .current)
        XCTAssertFalse(TitleSheets.EditorDraft(entry: after).save(to: m), "nothing changed, nothing sent")
    }

    func testRemove() async throws {
        let m = await model()
        let d = TitleSheets.EditorDraft(entry: try XCTUnwrap(m.entry("anime:210482")))
        d.remove(from: m)
        XCTAssertNil(m.entry("anime:210482"))
    }

    func testListsReviewAndSendGoToTheServer() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "demo-token")
        let choices = try await api.listChoices("anime:210482")
        XCTAssertEqual(choices.lists.count, 4)
        let t = ListWire.ListTitle(media: .anime, id: "1", title: "X", cover: nil, format: "TV", year: 2001)
        _ = try await api.putOnList(4, t)
        _ = try await api.takeOffList(1, t.ref)
        let mine = try? await api.myReview("manga:105778")
        _ = mine
        let r = TitleSheets.ReviewBody(body: "x", spoiler: false, meta: .init(title: "X", cover: "", format: "Manga"))
        try await api.putReview("manga:105778", r)
        let people = try await api.recipients()
        XCTAssertEqual(people.recipients.count, 6)
        let card = TitleSheets.MessageBody(body: nil, card: .init(kind: "anime", id: "1", mine: false))
        try await api.sendMessage(to: "kenji", card)
        XCTAssertEqual(transport.requests.map { "\($0.method) \($0.path)" },
                       ["GET titles/anime/210482/lists", "POST lists/4/items", "POST lists/1/items",
                        "GET titles/manga/105778/reviews", "PUT titles/manga/105778/review", "GET messages/recipients",
                        "POST conversations/kenji/messages"])
        let bodies = transport.requests.compactMap { $0.body.map { String(decoding: $0, as: UTF8.self) } }
        XCTAssertEqual(bodies, [
            #"{"title":{"format":"TV","id":"1","media":"anime","title":"X","year":2001}}"#,
            #"{"on":false,"title":{"id":"1","media":"anime"}}"#,
            #"{"body":"x","meta":{"cover":"","format":"Manga","title":"X"},"spoiler":false}"#,
            #"{"card":{"id":"1","kind":"anime","mine":false}}"#,
        ])
        XCTAssertTrue(transport.requests.allSatisfy { $0.query.isEmpty })
    }
}
