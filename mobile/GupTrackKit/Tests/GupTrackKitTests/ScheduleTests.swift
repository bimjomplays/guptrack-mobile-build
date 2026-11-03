import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The calendar (09, 10): the demo schedule with the demo library's statuses.
final class ScheduleTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    private func items(_ months: [String]) throws -> [AiringSchedule.Item] {
        try months.flatMap { try Demo.load(AiringSchedule.self, "api/schedule/\($0).json").items }
    }

    private func date(_ s: String) -> Date { Format.parseDay(s)! }

    func testEveryMonthDecodesAndStaysInItsMonth() throws {
        for m in ["2026-10", "2026-11", "2026-12"] {
            let s = try Demo.load(AiringSchedule.self, "api/schedule/\(m).json")
            XCTAssertEqual(s.month, m)
            XCTAssertFalse(s.items.isEmpty, m)
            for i in s.items {
                XCTAssertEqual(AiringSchedule.monthKey(i.at), m, i.title.name)
                XCTAssertNotNil(i.title.cover, i.title.id)
                XCTAssertTrue([.anime, .tv, .movie].contains(i.title.media))
            }
        }
    }

    func testTheDemoWeekIsNovFirstToSeventh() {
        let start = AiringSchedule.weekStart(Clock.now)
        XCTAssertEqual(Format.day(start), "2026-11-01")
        XCTAssertEqual(AiringSchedule.weekLabel(start), "Nov 1 – 7, 2026")
        XCTAssertEqual(AiringSchedule.monthsToLoad(Clock.now, mode: .week), ["2026-11"])
        XCTAssertEqual(AiringSchedule.monthsToLoad(Clock.now, mode: .month), ["2026-11"])
        XCTAssertEqual(AiringSchedule.weekDays(start).map(AiringSchedule.dayLabel).first, "Sun, Nov 1")
        XCTAssertEqual(AiringSchedule.longDayLabel(date("2026-11-06")), "Friday, Nov 6")
        XCTAssertEqual(AiringSchedule.monthLabel(Clock.now), "November 2026")
    }

    func testWeeksAcrossMonthsAndYears() {
        let back = AiringSchedule.shift(Clock.now, mode: .week, by: -1)
        XCTAssertEqual(AiringSchedule.weekLabel(back), "Oct 25 – 31, 2026")
        let late = AiringSchedule.shift(Clock.now, mode: .week, by: 4)
        XCTAssertEqual(AiringSchedule.weekLabel(late), "Nov 29 – Dec 5, 2026")
        XCTAssertEqual(AiringSchedule.monthsToLoad(late, mode: .week), ["2026-11", "2026-12"])
        let newYear = AiringSchedule.weekStart(date("2026-12-30"))
        XCTAssertEqual(AiringSchedule.weekLabel(newYear), "Dec 27, 2026 – Jan 2, 2027")
        XCTAssertEqual(AiringSchedule.monthKey(AiringSchedule.shift(Clock.now, mode: .month, by: 1)), "2026-12")
        XCTAssertEqual(AiringSchedule.monthKey(AiringSchedule.shift(Clock.now, mode: .month, by: -11)), "2025-12")
    }

    func testMonthGridStartsOnSunday() {
        let grid = AiringSchedule.monthGrid(Clock.now)
        XCTAssertEqual(grid.count, 30, "Nov 1 2026 is a Sunday: no blanks")
        XCTAssertEqual(grid.first??.timeIntervalSince1970, AiringSchedule.monthStart(Clock.now).timeIntervalSince1970)
        let dec = AiringSchedule.monthGrid(date("2026-12-10"))
        XCTAssertEqual(dec.prefix(2).filter { $0 == nil }.count, 2, "Dec 1 2026 is a Tuesday")
        XCTAssertEqual(dec.compactMap { $0 }.count, 31)
    }

    func testTodayMatchesTheMockup() throws {
        let rows = AiringSchedule.rows(try items(["2026-11"]), library: try library())
        let today = AiringSchedule.days(rows, on: [AiringSchedule.weekStart(Clock.now)] + AiringSchedule.weekDays(AiringSchedule.weekStart(Clock.now)).dropFirst())
        let tue = today[2]
        XCTAssertTrue(AiringSchedule.isToday(tue.date))
        XCTAssertEqual(tue.rows.map { Format.time($0.item.at) }, ["7:26 AM", "8:00 AM", "9:00 AM", "10:00 AM"])
        XCTAssertEqual(tue.rows.first?.item.title.name, "Nia Liston: The Merciless Maiden")
        XCTAssertEqual(tue.rows.first?.item.what, "Episode 5")
        XCTAssertEqual(AiringSchedule.nowIndex(tue.rows), 3, "the now line sits before 10:00 AM")
        XCTAssertTrue(AiringSchedule.isOut(tue.rows[2]))
        XCTAssertFalse(AiringSchedule.isOut(tue.rows[3]))
        XCTAssertEqual(AiringSchedule.countLabel(tue.rows), "4 episodes")
        XCTAssertTrue(AiringSchedule.isPast(today[0].date))
        XCTAssertEqual(AiringSchedule.countLabel(today[1].rows), "Nothing airing", "Mon has only titles not on the list")
    }

    func testLibraryStatusWinsOverTheServers() throws {
        let item = AiringSchedule.Item(title: Make.title("anime:7"), at: Clock.now, episode: 3, status: .planned)
        let lib = [Make.entry("anime:7", .current)]
        XCTAssertEqual(AiringSchedule.rows([item], library: lib).first?.status, .current)
        XCTAssertEqual(AiringSchedule.rows([item], library: []).first?.status, .planned)
        // a server-only status still filters like any other
        var f = AiringSchedule.Filter()
        f.shows = [.completed]
        XCTAssertTrue(AiringSchedule.rows([item], library: lib, filter: f).isEmpty)
    }

    func testFilters() throws {
        let all = try items(["2026-11"])
        let lib = try library()
        let def = AiringSchedule.rows(all, library: lib)
        XCTAssertTrue(def.allSatisfy { [.current, .repeating, .planned].contains($0.status) })
        var everything = AiringSchedule.Filter()
        everything.shows = Set(AiringSchedule.Show.allCases)
        let every = AiringSchedule.rows(all, library: lib, filter: everything)
        XCTAssertEqual(every.count, Set(all.map(\.id)).count)
        XCTAssertTrue(every.contains { $0.status == nil }, "popular titles not on the list")
        everything.media = .tv
        XCTAssertTrue(AiringSchedule.rows(all, library: lib, filter: everything).allSatisfy { $0.item.title.media == .tv })
        XCTAssertFalse(AiringSchedule.rows(all, library: lib, filter: everything).isEmpty)
        var f = AiringSchedule.Filter()
        f.toggle(.planning)
        XCTAssertEqual(f.shows, [.watching])
        f.toggle(.completed)
        XCTAssertEqual(f.shows, [.watching, .completed])
        XCTAssertEqual(AiringSchedule.Filter().mediaLabel, "All types")
        XCTAssertEqual(AiringSchedule.Filter(media: .movie).mediaLabel, "Movies")
    }

    func testFridayAndTheMonthDots() throws {
        let rows = AiringSchedule.rows(try items(["2026-11"]), library: try library())
        let fri = AiringSchedule.days(rows, on: [date("2026-11-06")])[0]
        XCTAssertEqual(fri.rows.first?.item.title.id, "anime:210482")
        XCTAssertEqual(fri.rows.first.map { Format.time($0.item.at) }, "3:00 AM")
        XCTAssertEqual(fri.rows.first?.status, .current)
        XCTAssertEqual(AiringSchedule.dots(fri.rows), [.current, .planned])
        let sat = AiringSchedule.days(rows, on: [date("2026-11-07")])[0]
        XCTAssertEqual(AiringSchedule.dots(sat.rows), [.current, .planned])
        var f = AiringSchedule.Filter()
        f.shows.insert(.completed)
        let sat2 = AiringSchedule.days(AiringSchedule.rows(try items(["2026-11"]), library: try library(), filter: f),
                                       on: [date("2026-11-07")])[0]
        XCTAssertEqual(AiringSchedule.dots(sat2.rows), [.current, .planned, .completed])
        XCTAssertEqual(AiringSchedule.legend(sat2.rows), [.current, .planned, .completed])
        XCTAssertEqual(AiringSchedule.dots([]), [])
    }

    func testWhatAndCounts() {
        var film = AiringSchedule.Item(title: Title(id: "anime:143103", media: .anime, name: "Film", format: "Movie"),
                                       at: Clock.now, episode: nil)
        XCTAssertEqual(film.what, "Film")
        XCTAssertTrue(film.isFilm)
        let tv = AiringSchedule.Item(title: Make.title("tv:1", media: .tv), at: Clock.now, episode: 4, season: 6)
        XCTAssertEqual(tv.what, "Season 6 · Episode 4")
        film.episode = 1
        let rows = [AiringSchedule.Row(item: film, status: nil), AiringSchedule.Row(item: tv, status: .current)]
        XCTAssertEqual(AiringSchedule.countLabel(rows), "2 releases")
        XCTAssertEqual(AiringSchedule.countLabel([rows[1]]), "1 episode")
        XCTAssertEqual(AiringSchedule.statusLabel(nil, media: .anime), "Not on your list")
        XCTAssertEqual(AiringSchedule.statusLabel(.planned, media: .tv), "Plan to Watch")
    }

    func testTheSlowHorsesSeasonIsTV() throws {
        let slow = try items(["2026-11"]).filter { $0.title.media == .tv }
        XCTAssertFalse(slow.isEmpty)
        let wed = slow.first { Format.day($0.at) == "2026-11-04" }
        XCTAssertEqual(wed.map { Format.time($0.at) }, "12:00 AM")
        XCTAssertEqual(wed?.what, "Season 6 · Episode 4")
    }

    func testTheCallAsksForTheMonth() async throws {
        let t = DemoTransport()
        let api = APIClient(transport: t)
        let items = try await api.airingSchedule(months: ["2026-10", "2026-11"])
        XCTAssertGreaterThan(items.count, 100)
        XCTAssertEqual(t.requests.map(\.path), ["schedule", "schedule"])
        XCTAssertEqual(t.requests.last?.query.first?.value, "2026-11")
    }
}
