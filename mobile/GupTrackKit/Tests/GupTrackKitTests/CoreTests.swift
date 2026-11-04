import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Test helpers: a title and an entry in a line.
enum Make {
    static let now = Clock.demoNow

    static func title(_ id: String = "anime:1", total: Int? = 12, media: MediaKind = .anime, name: String = "Show") -> Title {
        Title(id: id, media: media, name: name, format: "TV", total: total)
    }

    static func entry(_ id: String = "anime:1", _ status: ListStatus = .current, progress: Int = 0, total: Int? = 12,
                      media: MediaKind = .anime) -> LibraryEntry {
        LibraryEntry(title: title(id, total: total, media: media), status: status, progress: progress, updatedAt: now)
    }
}

final class ModelTests: XCTestCase {
    func testStatusWordsFollowTheMedia() {
        XCTAssertEqual(ListStatus.current.label(.anime), "Watching")
        XCTAssertEqual(ListStatus.current.label(.manga), "Reading")
        XCTAssertEqual(ListStatus.planned.label(.book), "Plan to Read")
        XCTAssertEqual(ListStatus.planned.label(.movie), "Plan to Watch")
        XCTAssertEqual(ListStatus.hold.label(.tv), "On-Hold")
        XCTAssertEqual(ListStatus.ordered.count, 5)
    }

    func testUnits() {
        XCTAssertEqual(MediaKind.anime.units(1), "1 episode")
        XCTAssertEqual(MediaKind.manga.units(12), "12 chapters")
        XCTAssertEqual(MediaKind.book.units(1200), "1,200 pages")
        XCTAssertEqual(MediaKind.movie.units(1), "")
        XCTAssertEqual(MediaKind.book.step, 10)
    }

    func testContinueLine() {
        var t = Make.title(total: 11)
        t.format = "ONA"
        let e = LibraryEntry(title: t, status: .current, progress: 6, updatedAt: Make.now)
        XCTAssertEqual(e.continueLine, "Anime · ONA · 5 episodes left")
        XCTAssertEqual(e.fraction!, 6.0 / 11, accuracy: 0.0001)
        t.format = "TV"
        XCTAssertEqual(LibraryEntry(title: t, status: .current, progress: 1, updatedAt: Make.now).continueLine,
                       "Anime · 10 episodes left")
        XCTAssertEqual(Make.title(media: .tv).kindLine, "TV")
    }

    func testProgressClampsAndFinishingCompletes() {
        let e = Make.entry(progress: 10).applying(LibraryPatch(progress: 40), at: Make.now)
        XCTAssertEqual(e.progress, 12)
        XCTAssertEqual(e.status, .completed)
        XCTAssertEqual(e.finished, "2026-11-03")
        XCTAssertEqual(Make.entry(progress: 3).applying(LibraryPatch(progress: -4), at: Make.now).progress, 0)
    }

    func testProgressOnAPlannedTitleStartsIt() {
        let e = Make.entry("anime:1", .planned).applying(LibraryPatch(progress: 1), at: Make.now)
        XCTAssertEqual(e.status, .current)
        // an explicit status wins
        XCTAssertEqual(Make.entry("anime:1", .planned).applying(LibraryPatch(status: .hold, progress: 1), at: Make.now).status, .hold)
    }

    func testUnknownTotalNeverCompletes() {
        let e = Make.entry(progress: 1100, total: nil).applying(LibraryPatch(progress: 1151), at: Make.now)
        XCTAssertEqual(e.progress, 1151)
        XCTAssertEqual(e.status, .current)
    }

    func testScoreAndDatesClear() {
        var e = Make.entry()
        e.score = 80
        e.started = "2026-01-01"
        e = e.applying(LibraryPatch(score: -1, started: ""), at: Make.now)
        XCTAssertNil(e.score)
        XCTAssertNil(e.started)
        XCTAssertEqual(Make.entry().applying(LibraryPatch(score: 150), at: Make.now).score, 100)
        XCTAssertEqual(Make.entry().applying(LibraryPatch(score: 85), at: Make.now).score10, "8.5")
    }

    func testPatchesMergeLaterWins() {
        let p = LibraryPatch(status: .current, progress: 1).merged(LibraryPatch(progress: 2, notes: "x"))
        XCTAssertEqual(p, LibraryPatch(status: .current, progress: 2, notes: "x"))
        XCTAssertTrue(LibraryPatch().isEmpty)
    }

    func testPatchJSONLeavesUnsetFieldsOut() throws {
        let d = try APIClient.encoder.encode(LibraryPatch(progress: 7))
        XCTAssertEqual(String(decoding: d, as: UTF8.self), #"{"progress":7}"#)
    }

    func testNewEntryDefaultsToPlanned() {
        let e = LibraryEntry.new(Make.title(), LibraryPatch(), at: Make.now)
        XCTAssertEqual(e.status, .planned)
        XCTAssertEqual(LibraryEntry.new(Make.title(), LibraryPatch(progress: 2), at: Make.now).status, .current)
    }
}

final class FormatTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func testNumbers() {
        XCTAssertEqual(Format.grouped(2775), "2,775")
        XCTAssertEqual(Format.grouped(1_234_567), "1,234,567")
        XCTAssertEqual(Format.grouped(-1000), "-1,000")
        XCTAssertEqual(Format.compact(48_869), "48.9K")
        XCTAssertEqual(Format.compact(1_200_000), "1.2M")
        XCTAssertEqual(Format.compact(999), "999")
        XCTAssertEqual(Format.score10(90), "9")
        XCTAssertEqual(Format.score10(85), "8.5")
        XCTAssertEqual(Format.days(minutes: 65_232), "45.3")
    }

    func testDemoClockIsTuesdayMorningInNewYork() {
        XCTAssertEqual(Format.day(Clock.now), "2026-11-03")
        XCTAssertEqual(Format.weekdayTime(Clock.now), "Tue 9:41 AM")
        XCTAssertEqual(Format.longDay(Clock.now), "Nov 3, 2026")
    }

    func testAiringLine() {
        let a = Airing(episode: 7, at: Date(timeIntervalSince1970: 1_793_952_000))
        XCTAssertEqual(Format.airing(a), "Ep 7 · Fri 3:00 AM · in 3 days")
        XCTAssertEqual(Format.until(Clock.now.addingTimeInterval(5 * 3600)), "in 5h")
        XCTAssertEqual(Format.until(Clock.now.addingTimeInterval(20 * 3600)), "tomorrow")
        XCTAssertEqual(Format.until(Clock.now.addingTimeInterval(-10)), "aired")
    }

    func testAgo() {
        XCTAssertEqual(Format.ago(Clock.now.addingTimeInterval(-30)), "now")
        XCTAssertEqual(Format.ago(Clock.now.addingTimeInterval(-7200)), "2h")
        XCTAssertEqual(Format.ago(Clock.now.addingTimeInterval(-3 * 86_400)), "3d")
        XCTAssertEqual(Format.agoLong(Clock.now.addingTimeInterval(-15 * 3600)), "15 hours ago")
        XCTAssertEqual(Format.agoLong(Clock.now.addingTimeInterval(-4 * 86_400)), "4 days ago")
        XCTAssertEqual(Format.agoLong(Clock.now.addingTimeInterval(-30 * 86_400)), "Oct 4")
    }

    func testParseDay() {
        XCTAssertEqual(Format.parseDay("2026-11-03").map(Format.day), "2026-11-03")
        XCTAssertNil(Format.parseDay("yesterday"))
    }
}

final class RouteTests: XCTestCase {
    func testEveryRouteRoundTripsThroughItsPath() {
        let all: [Route] = [.notifications, .calendar, .seasonChart, .search("one piece"), .title("anime:210482"),
                            .season("tv:95396", 2), .reviews("anime:1"), .review("r1"), .character("c1"),
                            .person("p1"), .studio("s1"), .author("a1"), .list(.manga), .customList("best-of-2026"),
                            .stats, .user("kenji"), .compare("kenji"), .friends, .activity("a1"),
                            .conversation("c1"), .messageRequest("m1"), .settings, .settingsPage(.connectedApps)]
        for r in all {
            XCTAssertEqual(Route(path: r.path), r, r.path)
            XCTAssertEqual(Route(url: r.url), r, r.url.absoluteString)
        }
        for p in SettingsPage.allCases { XCTAssertEqual(Route(path: Route.settingsPage(p).path), .settingsPage(p)) }
    }

    func testBadPathsAreRefused() {
        for p in ["", "title", "title/", "season/tv:1/x", "list/comics", "settings/nope", "nope", "stats/extra"] {
            XCTAssertNil(Route(path: p), p)
        }
        XCTAssertNil(Route(url: URL(string: "https://guptrack.example/title/anime:1")!))
    }

    func testLinksOpenOnTheirTab() {
        XCTAssertEqual(Route.title("anime:1").homeTab, .browse)
        XCTAssertEqual(Route.calendar.homeTab, .home)
        XCTAssertEqual(Route.conversation("c").homeTab, .social)
        XCTAssertEqual(Route.settingsPage(.privacy).homeTab, .profile)
    }

    func testSheetsRoundTrip() {
        let all: [SheetRoute] = [.editor("anime:1", expanded: true), .editor("anime:1", expanded: false),
                                 .addToList("anime:1"), .writeReview("anime:1"), .sendTo("anime:1"),
                                 .browseFilters(.anime), .newList, .editList("x"), .addFriend, .bioEditor, .newMessage]
        for s in all { XCTAssertEqual(SheetRoute(id: s.id), s, s.id) }
        XCTAssertEqual(SheetRoute(id: "editor/anime:1"), .editor("anime:1", expanded: false))
        XCTAssertNil(SheetRoute(id: "filters/comics"))
    }
}

final class AccountTests: XCTestCase {
    let code = "7KQ4-M2XD"

    /// the website builds the link with URLSearchParams (src/sync/sync.functions.ts)
    func testPairLink() {
        let link = "guptrack://pair?server=https%3A%2F%2Fpc.example.ts.net&code=\(code)"
        XCTAssertEqual(try PairLink.parse(link).get(), PairLink(baseURL: URL(string: "https://pc.example.ts.net")!, code: code))
        // a typed or damaged-looking code reads the way the website reads it
        let typed = "guptrack://pair?server=https%3A%2F%2Fpc.example.ts.net%3A8443%2F&code=7kq4+m2xd"
        XCTAssertEqual(try PairLink.parse(typed).get().code, code)
        XCTAssertEqual(try PairLink.parse(typed).get().baseURL.absoluteString, "https://pc.example.ts.net:8443")
        let local = "guptrack://pair?server=http%3A%2F%2Flocalhost%3A3000&code=\(code)"
        XCTAssertEqual(try PairLink.parse(local).get().baseURL.absoluteString, "http://localhost:3000")
    }

    func testPairingCodes() {
        XCTAssertEqual(PairLink.pairingCode("7KQ4-M2XD"), "7KQ4-M2XD")
        XCTAssertEqual(PairLink.pairingCode(" 7kq4 m2xd "), "7KQ4-M2XD")
        XCTAssertEqual(PairLink.pairingCode("OIL0-0000"), "0110-0000")
        XCTAssertNil(PairLink.pairingCode("7KQ4-M2X"))
        XCTAssertNil(PairLink.pairingCode("7KQ4-M2XU"), "U isn't a Crockford symbol")
        XCTAssertNil(PairLink.pairingCode("7KQ4-M2XD-1"))
    }

    func testPairLinkProblems() {
        func problem(_ s: String) -> PairLink.Problem? {
            if case .failure(let p) = PairLink.parse(s) { return p }
            return nil
        }
        XCTAssertEqual(problem("https://example.com"), .notOurs)
        XCTAssertEqual(problem("guptrack://title/anime:1"), .notOurs)
        XCTAssertEqual(problem("guptrack://pair?server=http://a.b&code=\(code)"), .badAddress)
        XCTAssertEqual(problem("guptrack://pair?server=https://a.b/path&code=\(code)"), .badAddress)
        XCTAssertEqual(problem("guptrack://pair?code=\(code)"), .badAddress)
        XCTAssertEqual(problem("guptrack://pair?server=https://a.b&code=short"), .badCode)
        XCTAssertEqual(problem("guptrack://pair?server=https://a.b"), .badCode)
        XCTAssertEqual(problem("guptrack://pair?server=https://a.b&server=https://c.d&code=\(code)"), .notOurs)
    }

    func testServerAddress() {
        XCTAssertEqual(PairLink.serverURL("pc.example.ts.net")?.absoluteString, "https://pc.example.ts.net")
        XCTAssertEqual(PairLink.serverURL(" https://PC.example.ts.net:8443/ ")?.absoluteString, "https://pc.example.ts.net:8443")
        XCTAssertNil(PairLink.serverURL("http://pc.example.ts.net"))
        XCTAssertNil(PairLink.serverURL("https://user" + "@" + "pc.example"))
        XCTAssertNil(PairLink.serverURL("https://pc"))
        XCTAssertEqual(PairLink.serverURL("http://127.0.0.1:3000")?.absoluteString, "http://127.0.0.1:3000")
        XCTAssertEqual(PairLink.serverURL("localhost")?.absoluteString, "https://localhost")
    }

    func testPasswordStrength() {
        XCTAssertEqual(PasswordStrength.of("short"), .tooShort)
        XCTAssertEqual(PasswordStrength.of("aaaaaaaaaaaaaaa"), .weak)
        XCTAssertEqual(PasswordStrength.of("aaaaaaaaaaaaaa1"), .fair)
        XCTAssertEqual(PasswordStrength.of("correct horse battery staple"), .strong)
    }

    func testMemoryTokenStore() {
        let s = MemoryTokenStore()
        XCTAssertNil(s.load())
        let a = Demo.account()
        s.save(a)
        XCTAssertEqual(s.load(), a)
        s.clear()
        XCTAssertNil(s.load())
    }
}
