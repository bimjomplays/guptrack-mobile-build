import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Home (05, 06): Continue and Stalled from the offline library; Upcoming and Trending from GET home/live; Start
/// something from POST home/picks (docs/app-api.md §6).
final class HomeTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() -> [LibraryEntry] { Demo.library() }
    private func live() throws -> HomeLive { try Demo.load(HomeLive.self, "api/home/live.json") }

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: shelves

    func testContinueStartsWithTheAnimeYouJustWatched() {
        let lib = library()
        let cont = HomeShelves.continuing(lib)
        XCTAssertEqual(cont.prefix(4).map(\.id), ["anime:210482", "anime:195539", "anime:178789", "anime:166240"])
        XCTAssertFalse(cont.contains { $0.id == "anime:20" }, "a stalled title isn't in Continue")
        XCTAssertEqual(HomeShelves.inProgress(lib).count, cont.count + HomeShelves.stalled(lib).count)
    }

    func testStalledIsNarutoAt52() {
        let stalled = HomeShelves.stalled(library())
        XCTAssertEqual(stalled.first?.id, "anime:20")
        XCTAssertEqual(stalled.first?.progress, 52)
        XCTAssertEqual(stalled.first.map { Format.monthYear($0.updatedAt) }, "Jun 2024")
    }

    func testUpcomingComesFromHomeLive() throws {
        let up = HomeShelves.upcoming(try live().upcoming, library: library())
        XCTAssertEqual(up.prefix(3).map(\.titleId), ["tv:95480", "anime:210482", "anime:195516"])
        XCTAssertEqual(HomeShelves.upcomingCaption(up[0]), "Ep 34 · Tomorrow", "TMDB knows the day only")
        XCTAssertEqual(HomeShelves.upcomingCaption(up[1]), "Ep 7 · Fri 3:00 AM")
    }

    func testUpcomingDropsWhatHasAiredOrLeftYourList() throws {
        let next = try live().upcoming
        var lib = library()
        let i = try XCTUnwrap(lib.firstIndex { $0.id == "anime:210482" })
        lib[i].status = .dropped
        XCTAssertFalse(HomeShelves.upcoming(next, library: lib).contains { $0.titleId == "anime:210482" })
        // Friday 9 AM: SBR's 3 AM episode is out, Slow Horses' Wednesday too
        let fri = Clock.demoNow.addingTimeInterval(3 * 86_400)
        let left = HomeShelves.upcoming(next, library: library(), now: fri).map(\.titleId)
        XCTAssertFalse(left.contains("anime:210482"))
        XCTAssertFalse(left.contains("tv:95480"))
    }

    func testStartSomethingFollowsThePicks() throws {
        let picks = try Demo.load([OnTheGo].self, "api/home/picks.post.json")
        let lib = library()
        let start = HomeShelves.startCandidates(picks, library: lib)
        XCTAssertEqual(start.first?.id, "anime:21170")
        XCTAssertEqual(start.first.map { HomeShelves.startLine($0.title) }, "TV · 25 episodes")
        XCTAssertTrue(start.allSatisfy { $0.status == .planned })
        // started since the answer came: it leaves the shelf
        var started = lib
        let i = try XCTUnwrap(started.firstIndex { $0.id == "anime:21170" })
        started[i].status = .current
        XCTAssertNotEqual(HomeShelves.startCandidates(picks, library: started).first?.id, "anime:21170")
        // offline: the planned titles, newest first
        XCTAssertFalse(HomeShelves.startCandidates(nil, library: lib).isEmpty)
    }

    func testAvoidKeysUseTheListsMedia() {
        let shown = (0..<12).map { "anime:\($0)" } + ["movie:1078605", "book:OL1W"]
        let keys = HomeShelves.avoid(shown)
        XCTAssertEqual(keys.count, 10)
        XCTAssertEqual(keys.suffix(2), ["movies:1078605", "books:OL1W"])
    }

    func testTrendingCardsCarryTheServersNote() throws {
        let t = try live().trending
        XCTAssertFalse(t.isEmpty)
        XCTAssertLessThanOrEqual(t.count, 15)
        XCTAssertTrue(t.allSatisfy { $0.ref.kind == .anime && !$0.note.isEmpty })
        XCTAssertEqual(t.first?.id, "anime:\(t.first?.ref.id ?? "")")
    }

    func testHomeFixtureIsTheLibrarysCurrentTitles() throws {
        let h = try Demo.load(HomeLibrary.self, "api/home.json")
        XCTAssertEqual(h.current.first?.titleId, "anime:210482", "last touched first")
        XCTAssertTrue(h.current.allSatisfy { $0.entry.status == .current })
        XCTAssertEqual(h.total, library().count)
        let sbr = try XCTUnwrap(h.current.first).library()
        XCTAssertEqual(sbr.updatedAt.timeIntervalSince1970,
                       try XCTUnwrap(library().first { $0.id == "anime:210482" }).updatedAt.timeIntervalSince1970,
                       accuracy: 60, "updated is days since the last change")
    }

    // MARK: the contract (§6)

    func testHomeLibraryDecodesTheDocsShape() throws {
        let h = try decode(HomeLibrary.self, """
        {"current":[{"media":"anime","entry":{"id":"21","title":"A Show","alt":[],"cover":"https://img.example/a.jpg",
          "format":"TV","status":"current","progress":3,"total":12,"score":null,"minutes":24,"updated":1.5,"position":0,
          "volumes":null,"readVolumes":0,"repeats":0,"rewatch":null,"started":null,"finished":null,"notes":"",
          "favourite":false,"idMal":null,"added":1790000000000}}],
         "week":{"episodes":4,"chapters":0,"pages":12,"minutes":96},"activity":[{"id":1,"kind":"progress"}],
         "friends":{"count":2,"activity":[]},"total":40,"at":1793724171075,"later":true}
        """)
        XCTAssertEqual(h.current.first?.titleId, "anime:21")
        XCTAssertEqual(h.week, Week(episodes: 4, chapters: 0, pages: 12, minutes: 96))
        XCTAssertEqual(h.friends.count, 2)
        XCTAssertEqual(h.total, 40)
        XCTAssertEqual(h.current[0].library(now: Clock.demoNow).updatedAt, Clock.demoNow.addingTimeInterval(-1.5 * 86_400))
    }

    func testHomeLiveDecodesTheDocsShape() throws {
        let l = try decode(HomeLive.self, """
        {"upcoming":[{"ref":{"kind":"tv","id":"95396"},"media":"tv","id":"95396","title":"A Show","cover":"",
          "number":20,"at":1793768400000,"dateOnly":true}],
         "announced":[{"ref":{"kind":"anime","id":"7"},"title":"Sequel","cover":"https://img.example/s.jpg",
          "what":"Sequel","when":"April 2027","link":"Follows A Show"}],
         "recommended":[{"ref":{"kind":"movie","id":"9"},"title":"A Film","cover":"/media/x.jpg",
          "note":"Because you watched A Show"}],
         "comingSoon":[],"trending":[{"ref":{"kind":"anime","id":"8"},"title":"New","cover":"","note":"Ep 6 out"}]}
        """)
        let n = try XCTUnwrap(l.upcoming.first)
        XCTAssertEqual(n.titleId, "tv:95396")
        XCTAssertEqual(n.media, .tv)
        XCTAssertNil(n.cover, "\"\" is no picture")
        XCTAssertTrue(n.dateOnly)
        XCTAssertEqual(l.announced.first?.when, "April 2027")
        XCTAssertEqual(l.recommended.first?.id, "movie:9")
        XCTAssertEqual(l.recommended.first?.cover?.relativeString, "/media/x.jpg", "GupTrack's own pictures stay relative")
        XCTAssertEqual(l.trending.first?.note, "Ep 6 out")
    }

    func testCalls() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "demo-token")
        t.reply(#"{"current":[],"week":{"episodes":0,"chapters":0,"pages":0,"minutes":0},"activity":[],"friends":{"count":0,"activity":[]},"total":0,"at":1}"#)
        _ = try await api.home()
        t.reply(#"{"upcoming":[],"announced":[],"recommended":[],"comingSoon":[],"trending":[]}"#)
        _ = try await api.homeLive()
        t.reply("[]")
        let long = String(repeating: "x", count: 41)
        _ = try await api.picks(avoid: ["anime:21170", "movies:1078605", long])
        t.reply(#"{"title":{"kind":"anime","id":"154587"}}"#)
        let found = try await api.resolve(url: "https://anilist.co/anime/154587")
        t.reply(#"{"title":null}"#)
        let none = try await api.resolve(url: "https://example.com/")

        XCTAssertEqual(t.sent.map { "\($0.method) \($0.path)" },
                       ["GET home", "GET home/live", "POST home/picks", "GET resolve", "GET resolve"])
        let body = try JSONDecoder().decode(JSONValue.self, from: try XCTUnwrap(t.sent[2].body))
        XCTAssertEqual(body, try JSONDecoder().decode(JSONValue.self, from: Data(#"{"avoid":["anime:21170","movies:1078605"]}"#.utf8)))
        XCTAssertEqual(t.sent[3].query, [URLQueryItem(name: "url", value: "https://anilist.co/anime/154587")])
        XCTAssertEqual(found, TitleRef(kind: .anime, id: "154587"))
        XCTAssertNil(none)
    }

    func testDemoResolvesTheSharedLinks() async throws {
        let api = APIClient(transport: DemoTransport(), token: "demo-token")
        let sev = try await api.resolve(url: "https://themoviedb.org/tv/95396")
        XCTAssertEqual(sev?.titleId, "tv:95396")
        let dune = try await api.resolve(url: "http://imdb.com/title/tt15239678")
        XCTAssertEqual(dune?.titleId, "movie:693134")
        let unknown = try await api.resolve(url: "https://example.com/nothing")
        XCTAssertNil(unknown)
    }
}
