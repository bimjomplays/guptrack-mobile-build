import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Home's shelves from the demo library (05, 06).
final class HomeTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    func testContinueStartsWithTheAnimeYouJustWatched() throws {
        let lib = try library()
        let cont = HomeShelves.continuing(lib)
        XCTAssertEqual(cont.prefix(4).map(\.id), ["anime:210482", "anime:195539", "anime:178789", "anime:166240"])
        XCTAssertFalse(cont.contains { $0.id == "anime:20" }, "a stalled title isn't in Continue")
        XCTAssertEqual(HomeShelves.inProgress(lib).count, cont.count + HomeShelves.stalled(lib).count)
    }

    func testStalledIsNarutoAt52() throws {
        let stalled = HomeShelves.stalled(try library())
        XCTAssertEqual(stalled.first?.id, "anime:20")
        XCTAssertEqual(stalled.first?.progress, 52)
        XCTAssertEqual(stalled.first.map { Format.monthYear($0.updatedAt) }, "Jun 2024")
    }

    func testUpcomingIsWatchingFirstThenPlanned() throws {
        let up = HomeShelves.upcoming(try library())
        XCTAssertEqual(up.prefix(3).map(\.id), ["anime:210482", "anime:21", "anime:195516"])
        let sbr = up[0].title.next!
        XCTAssertEqual(HomeShelves.upcomingCaption(sbr), "Ep 7 · Fri 3:00 AM")
        XCTAssertEqual(HomeShelves.upcomingCaption(up[1].title.next!), "Ep 1181 · Jan 3")
    }

    func testStartSomethingPicksTheNewestPlanned() throws {
        let pick = HomeShelves.startCandidates(try library()).first
        XCTAssertEqual(pick?.id, "anime:21170")
        XCTAssertEqual(pick.map { HomeShelves.startLine($0.title) }, "TV · 25 episodes · Lerche")
    }

    func testHomeFeedDecodes() throws {
        let feed = try Demo.load(HomeFeed.self, "api/home.json")
        XCTAssertGreaterThanOrEqual(feed.trending.count, 6)
        XCTAssertGreaterThan(feed.unreadNotifications, 0)
    }

    func testTrendingCaption() {
        var t = Make.title()
        XCTAssertNil(HomeShelves.trendingCaption(t))
        t.next = Airing(episode: 6, at: Clock.demoNow.addingTimeInterval(86_400))
        XCTAssertEqual(HomeShelves.trendingCaption(t), "Ep 5 out")
    }
}
