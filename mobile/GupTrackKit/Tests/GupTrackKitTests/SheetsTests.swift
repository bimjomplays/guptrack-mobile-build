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

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

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

    func testMangaVolumeAndTVSeason() throws {
        let manga = try entry("manga:105778")
        var m = TitleSheets.EditorDraft(entry: manga)
        m.stepVolume(1)
        XCTAssertEqual(m.patch, LibraryPatch(volume: (manga.volume ?? 0) + 1))
        let show = try XCTUnwrap(try library().first { $0.media == .tv && $0.status == .current })
        var t = TitleSheets.EditorDraft(entry: show)
        t.stepSeason(1)
        XCTAssertEqual(t.patch.season, (show.season ?? 1) + 1)
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

    func testNextLine() throws {
        let d = TitleSheets.EditorDraft(entry: try entry("anime:210482"))
        let next = try XCTUnwrap(d.title.next)
        XCTAssertEqual(d.nextLine, "Ep \(next.episode) airs \(Format.dayOffset(next.at) < 7 ? Format.weekday(next.at) : Format.shortDay(next.at))")
    }

    // MARK: add to a list

    func testListPicksTickAndCount() throws {
        let lists = try Demo.load([CustomList].self, "api/lists.json")
        var p = TitleSheets.ListPicks(titleId: "anime:210482", lists: lists)
        let on = lists.filter { p.isOn($0.id) }
        XCTAssertFalse(on.isEmpty, "SBR is on some lists already")
        XCTAssertTrue(p.changes.isEmpty)
        let off = try XCTUnwrap(lists.first { !p.isOn($0.id) })
        let first = try XCTUnwrap(on.first)
        p.toggle(off.id)
        p.toggle(first.id)
        XCTAssertEqual(p.count(off), off.items.count + 1)
        XCTAssertEqual(p.count(first), first.items.count - 1)
        let changes = p.changes.map { "\($0.listId):\($0.add)" }
        XCTAssertEqual(Set(changes), ["\(off.id):true", "\(first.id):false"])
        XCTAssertTrue(p.caption(first).hasSuffix("· " + first.visibility.label))
    }

    // MARK: review

    func testReviewDraft() {
        var r = TitleSheets.ReviewDraft(score: 85)
        XCTAssertEqual(r.scoreText, "8.5 / 10")
        XCTAssertFalse(r.canPost)
        r.text = String(repeating: "a", count: 196)
        XCTAssertEqual(r.countText, "196 / 5,000")
        XCTAssertTrue(r.canPost)
        r.pickScore(9)
        XCTAssertNil(r.body.score, "85 shows as 9, so tapping 9 clears it")
        r.pickScore(10)
        XCTAssertEqual(r.body.score, 100)
        r.text = String(repeating: "a", count: 5001)
        XCTAssertFalse(r.canPost)
        let data = try? APIClient.encoder.encode(TitleSheets.ReviewBody(score: nil, text: "x", spoilers: true,
                                                                          visibility: .friends))
        XCTAssertEqual(data.map { String(decoding: $0, as: UTF8.self) },
                       #"{"spoilers":true,"text":"x","visibility":"friends"}"#)
    }

    func testReviewLine() throws {
        let e = try entry("manga:105778")
        let line = TitleSheets.reviewLine(e.title, entry: e)
        XCTAssertEqual(line.kind, "Manga")
        XCTAssertEqual(line.status, .current)
        XCTAssertEqual(line.progress, "Ch \(e.progress)")
    }

    // MARK: send to

    func testSendToFixtureAndPicks() throws {
        let page = try Demo.load(TitleSheets.SendToPage.self, "api/send-to.json")
        XCTAssertEqual(page.friends.map(\.username), ["kenji", "noor.reads", "tobiwan", "lena", "sorawatches", "hal"])
        var p = TitleSheets.SendPicks()
        XCTAssertFalse(p.canSend)
        p.toggle("tobiwan")
        p.toggle("kenji")
        XCTAssertEqual(p.sendLabel, "Send 2")
        p.message = " watch the first three, trust me "
        XCTAssertEqual(p.body("anime:210482", friends: page.friends),
                       TitleSheets.SendToBody(titleId: "anime:210482", to: ["kenji", "tobiwan"],
                                              message: "watch the first three, trust me"))
        p.toggle("kenji")
        XCTAssertEqual(p.picked, ["tobiwan"])
        p.query = "NOOR"
        XCTAssertEqual(p.shown(page.friends).map(\.username), ["noor.reads"])
    }

    func testTitlePageGivesTheSheetItsTitle() throws {
        let t = try Demo.load(TitleSheets.TitleLookup.self, "api/titles/anime_210482.json").title
        XCTAssertEqual(t.id, "anime:210482")
        XCTAssertEqual(t.total, 11)
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
        let api = APIClient(transport: transport, token: "t")
        _ = try await api.sheetPickList("best-of-2026", titleId: "anime:1", on: true)
        _ = try await api.sheetPickList("best-of-2026", titleId: "anime:1", on: false)
        _ = try await api.sheetPostReview("manga:105778", TitleSheets.ReviewBody(score: 90, text: "x", spoilers: false,
                                                                               visibility: .public))
        let friends = try await api.sheetSendToFriends()
        XCTAssertEqual(friends.friends.count, 6)
        _ = try await api.sheetSendTitle(TitleSheets.SendToBody(titleId: "anime:1", to: ["kenji"], message: nil))
        XCTAssertEqual(transport.requests.map { "\($0.method) \($0.path)" },
                       ["POST lists/best-of-2026/items", "DELETE lists/best-of-2026/items/anime:1",
                        "POST titles/manga:105778/reviews", "GET send-to", "POST send-to"])
    }
}
