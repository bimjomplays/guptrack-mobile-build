import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The widgets' snapshot (65, 65b) from the demo library and home/live's next episodes, and a widget's +1.
final class WidgetTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { Demo.library() }
    private func catalog() throws -> ExtensionCatalog { try Demo.load(ExtensionCatalog.self, "api/extensions.json") }
    private func snapshot() throws -> WidgetSnapshot {
        WidgetSnapshot.make(library: try library(), catalog: try catalog(), now: Clock.demoNow)
    }

    func testExtensionsFixtureDecodes() throws {
        let c = try catalog()
        XCTAssertFalse(c.titles.isEmpty)
        XCTAssertEqual(c.seasons["tv:95396"], [9, 10])
        XCTAssertEqual(c.malIds["anime/61469"], "anime:210482", "the MAL id of the list's own entry wins")
        XCTAssertEqual(c.upcoming, try Demo.load(HomeLive.self, "api/home/live.json").upcoming,
                       "the widgets' next episodes are home/live's")
        let onList = Set(try library().map(\.id))
        for t in c.titles { XCTAssertFalse(onList.contains(t.id), "\(t.id) is on the list already") }
    }

    func testContinueRowsAreTheLatestTitlesYouAreOn() throws {
        let lib = try library()
        let snap = try snapshot()
        let expected = lib.filter { $0.status.isActive && Clock.demoNow.timeIntervalSince($0.updatedAt) <= 30 * 86_400 }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(WidgetSnapshot.maxItems).map(\.id)
        XCTAssertEqual(snap.items.map(\.id), Array(expected))
        XCTAssertEqual(snap.items.first?.id, "anime:210482")
        XCTAssertFalse(snap.items.contains { $0.id == "anime:20" }, "a stalled title stays out")
    }

    func testRowCaptionAndRingComeFromTheFixture() throws {
        let sbr = try XCTUnwrap(try library().first { $0.id == "anime:210482" })
        let item = try XCTUnwrap(try snapshot().items.first)
        XCTAssertEqual(item.progress, sbr.progress)
        XCTAssertEqual(item.total, 11)
        XCTAssertEqual(item.caption, "Ep \(sbr.progress) of 11")
        XCTAssertEqual(item.ringCaption, "of 11")
        XCTAssertEqual(item.fraction ?? 0, Double(sbr.progress) / 11, accuracy: 0.0001)
        XCTAssertTrue(item.canStep)
        XCTAssertEqual(item.url.absoluteString, "guptrack://title/anime:210482")
    }

    func testTVReadsAsSeasonAndEpisode() throws {
        let sev = try XCTUnwrap(try library().first { $0.id == "tv:95396" })
        let item = WidgetSnapshot.item(sev, seasons: [9, 10])
        let pos = try XCTUnwrap(SeasonPosition.of(progress: sev.progress, lengths: [9, 10]))
        XCTAssertEqual(item.caption, "S\(pos.season) · Ep \(pos.episode) of \(pos.total)")
        XCTAssertEqual(SeasonPosition.of(progress: 15, lengths: [9, 10]), SeasonPosition(season: 2, episode: 6, total: 10))
        XCTAssertEqual(SeasonPosition.of(progress: 9, lengths: [9, 10]), SeasonPosition(season: 2, episode: 0, total: 10))
        XCTAssertEqual(SeasonPosition.of(progress: 3, lengths: [9, 10]), SeasonPosition(season: 1, episode: 3, total: 9))
        XCTAssertEqual(SeasonPosition.of(progress: 40, lengths: [9, 10]), SeasonPosition(season: 2, episode: 10, total: 10))
        XCTAssertNil(SeasonPosition.of(progress: 4, lengths: nil))
        XCTAssertEqual(SeasonPosition.progress(season: 2, episode: 6, lengths: [9, 10]), 15)
        // without season lengths it's the plain count
        XCTAssertEqual(WidgetSnapshot.item(sev).caption, "Ep \(sev.progress)")
        XCTAssertEqual(WidgetSnapshot.item(sev).ringCaption, "ep")
    }

    func testOtherMediaCaptions() throws {
        let lib = try library()
        let book = WidgetSnapshot.item(try XCTUnwrap(lib.first { $0.id == "book:OL21745884W" }))
        XCTAssertTrue(book.caption.hasPrefix("p. "), book.caption)
        XCTAssertEqual(book.ringCaption, "of 496")
        let manga = WidgetSnapshot.item(try XCTUnwrap(lib.first { $0.id == "manga:105778" }))
        XCTAssertTrue(manga.caption.hasPrefix("Ch "), manga.caption)
        let film = WidgetSnapshot.item(try XCTUnwrap(lib.first { $0.id == "movie:693134" }))
        XCTAssertEqual(film.caption, "Film", "the library feed has no year")
        XCTAssertFalse(film.canStep)
        let op = WidgetSnapshot.item(try XCTUnwrap(lib.first { $0.id == "anime:21" }))
        XCTAssertNil(op.fraction, "no total, no bar")
        XCTAssertEqual(op.caption, "Ep 1,150")
    }

    func testSpotlightIsTheNextEpisodeOfWhatYouWatch() throws {
        let spot = try XCTUnwrap(try snapshot().spotlight)
        XCTAssertEqual(spot.id, "anime:210482")
        XCTAssertEqual(spot.label, "Next episode")
        XCTAssertEqual(spot.caption, "Ep 7 · Fri 3:00 AM")
        XCTAssertTrue(spot.inline.hasPrefix("Ep 7 · Fri 3:00 AM · STEEL BALL RUN"))
        XCTAssertNotNil(spot.at)
        XCTAssertEqual(spot.at, Date(timeIntervalSince1970: 1_793_952_000))
    }

    func testNextEpisodeCaptions() throws {
        let sbr = try XCTUnwrap(try catalog().upcoming.first { $0.titleId == "anime:210482" })
        // a week or more away: the day instead of the weekday
        var later = sbr
        later.number = 1181
        later.at = Millis.of(ExtensionsJSON.parse("2027-01-03T14:30:00Z")!)
        XCTAssertEqual(later.caption(now: Clock.demoNow), "Ep 1,181 · Jan 3")
        // TMDB knows only the day
        var tv = sbr
        tv.ref = TitleRef(kind: .tv, id: "95480")
        tv.dateOnly = true
        tv.number = 34
        tv.at = Millis.of(ExtensionsJSON.parse("2026-11-04T05:00:00Z")!)
        XCTAssertEqual(tv.caption(now: Clock.demoNow), "Ep 34 · Tomorrow")
        tv.at = Millis.of(ExtensionsJSON.parse("2026-11-06T05:00:00Z")!)
        XCTAssertEqual(tv.caption(now: Clock.demoNow), "Ep 34 · Fri")
    }

    func testOnlyWhatYouWatchGetsTheSpotlight() throws {
        let lib = try library()
        let up = try catalog().upcoming
        // Slow Horses (on hold) airs first, but only watching titles take the spotlight
        XCTAssertEqual(up.first?.titleId, "tv:95480")
        XCTAssertEqual(WidgetSnapshot.upcoming(up, library: lib, now: Clock.demoNow).map(\.titleId), ["anime:210482"])
        // once it has aired it's gone
        let after = Clock.demoNow.addingTimeInterval(4 * 86_400)
        XCTAssertTrue(WidgetSnapshot.upcoming(up, library: lib, now: after).isEmpty)
    }

    func testSpotlightFallsBackToUpNextWhenNothingAirs() throws {
        let lib = try library()
        let snap = WidgetSnapshot.make(library: lib, catalog: try catalog(), upcoming: [], now: Clock.demoNow)
        let first = try XCTUnwrap(snap.items.first)
        let spot = try XCTUnwrap(snap.spotlight)
        XCTAssertEqual(spot.id, first.id)
        XCTAssertEqual(spot.label, "Up next")
        XCTAssertEqual(spot.caption, "Ep \(first.progress + 1)")
        XCTAssertNil(spot.at)
    }

    func testEmptyLibraryHasNothingToShow() {
        let snap = WidgetSnapshot.make(library: [], now: Clock.demoNow)
        XCTAssertTrue(snap.items.isEmpty)
        XCTAssertNil(snap.spotlight)
    }

    func testPlusOneStepsAndKeepsTheChange() throws {
        let lib = try library()
        let before = try XCTUnwrap(lib.first { $0.id == "anime:210482" }).progress
        var box = WidgetOutbox()
        let after = box.step("anime:210482", in: lib, now: Clock.demoNow)
        XCTAssertEqual(after?.progress, before + 1)
        box.step("anime:210482", in: lib, now: Clock.demoNow)
        XCTAssertEqual(box.changes.count, 2)
        let applied = box.apply(to: lib)
        XCTAssertEqual(applied.first { $0.id == "anime:210482" }?.progress, before + 2)
        let snap = WidgetSnapshot.make(library: applied, now: Clock.demoNow)
        XCTAssertEqual(snap.items.first?.id, "anime:210482", "the title you just stepped is first")
        XCTAssertEqual(snap.items.first?.progress, before + 2)
    }

    func testPlusOneOnBooksAddsTenPagesAndStopsAtTheEnd() throws {
        let lib = try library()
        let book = try XCTUnwrap(lib.first { $0.id == "book:OL21745884W" })
        XCTAssertEqual(WidgetSnapshot.plusOne(book)?.progress, book.progress + 10)
        var near = book
        near.progress = 490
        XCTAssertEqual(WidgetSnapshot.plusOne(near)?.progress, 496)
        near.progress = 496
        XCTAssertNil(WidgetSnapshot.plusOne(near))
    }

    func testTheLastEpisodeCompletesTheTitleAndItLeavesContinue() throws {
        var lib = try library()
        let i = try XCTUnwrap(lib.firstIndex { $0.id == "anime:210482" })
        lib[i].progress = 10
        var box = WidgetOutbox()
        let done = box.step("anime:210482", in: lib, now: Clock.demoNow)
        XCTAssertEqual(done?.status, .completed)
        XCTAssertNil(box.step("anime:210482", in: lib, now: Clock.demoNow), "nothing left to add")
        let snap = WidgetSnapshot.make(library: box.apply(to: lib), now: Clock.demoNow)
        XCTAssertFalse(snap.items.contains { $0.id == "anime:210482" })
    }

    func testOutboxSurvivesUserDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "widget-tests-\(UUID().uuidString)"))
        XCTAssertEqual(WidgetOutbox.load(defaults), WidgetOutbox())
        var box = WidgetOutbox()
        box.step("anime:210482", in: try library(), now: Clock.demoNow)
        box.save(defaults)
        XCTAssertEqual(WidgetOutbox.load(defaults), box)
    }

    func testSnapshotRoundTripsAsJSON() throws {
        let snap = try snapshot()
        let data = try ExtensionsJSON.encoder.encode(snap)
        XCTAssertEqual(try ExtensionsJSON.decoder.decode(WidgetSnapshot.self, from: data), snap)
        XCTAssertNotNil(ExtensionsJSON.parse("2026-10-30T13:41:00.000Z"))
        XCTAssertNotNil(ExtensionsJSON.parse("2026-10-30T13:41:00Z"))
    }
}
