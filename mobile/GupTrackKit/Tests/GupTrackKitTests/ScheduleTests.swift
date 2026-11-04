import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The calendar (09, 10): GET calendar?from=&to= (docs/app-api.md §6) with the demo library's statuses.
final class ScheduleTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() -> [LibraryEntry] { Demo.library() }

    private func date(_ s: String) -> Date { Format.parseDay(s)! }

    /// a month's answer, as the demo has it (by `from`)
    private func month(_ day: String) throws -> CalendarData {
        let from = AiringSchedule.monthStart(date(day))
        return try Demo.load(CalendarData.self, Demo.file("calendar", variant: String(Millis.of(from))))
    }

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: the contract

    func testDecodesTheDocsShape() throws {
        let d = try decode(CalendarData.self, """
        {"items":[
          {"key":"anime:7:ep5","media":"anime","id":"7","ref":{"kind":"anime","id":"7"},"title":"A Show",
           "cover":"https://img.example/a.jpg","kind":"episode","number":5,"label":"Ep 5","note":"Finale",
           "at":1793952000000,"dateOnly":false,"news":null},
          {"key":"movies:9:release","media":"movies","id":"9","ref":{"kind":"movie","id":"9"},"title":"A Film",
           "cover":"","kind":"release","number":null,"label":"Film","note":"In cinemas","at":1793768400000,
           "dateOnly":true,"news":null},
          {"key":"anime:8:ep1","media":"anime","id":"8","ref":{"kind":"anime","id":"8"},"title":"A Sequel",
           "cover":"","kind":"episode","number":1,"label":"Ep 1","note":"Premiere","at":1793952000000,
           "dateOnly":false,"news":{"sequelOf":"A Show"}},
          {"key":"tv:3:s2e4","media":"tv","id":"3","ref":{"kind":"tv","id":"3"},"title":"Old Show","cover":"",
           "kind":"episode","number":14,"label":"S2 · E4","note":null,"at":1793768400000,"dateOnly":true,
           "news":{"sequelOf":null}}],
         "entries":{"anime:7":{"id":"7","title":"A Show","alt":[],"cover":"","format":"TV","status":"current",
           "progress":4,"total":5,"score":null,"minutes":24,"updated":2,"position":0,"volumes":null,"readVolumes":0,
           "repeats":0,"rewatch":null,"started":null,"finished":null,"notes":"","favourite":false,"idMal":null,
           "added":1},
           "tv:3":{"id":"3","title":"Old Show","alt":[],"cover":"","format":"TV","status":"completed","progress":10,
           "total":10,"score":80,"minutes":50,"updated":200,"position":0,"volumes":null,"readVolumes":0,"repeats":0,
           "rewatch":null,"started":null,"finished":null,"notes":"","favourite":false,"idMal":null,"added":1}},
         "from":1793505600000,"to":1796101200000,"tmdb":true,"at":1793724171075}
        """)
        XCTAssertEqual(d.items.map(\.titleId), ["anime:7", "movie:9", "anime:8", "tv:3"])
        XCTAssertEqual(d.items[1].entryKey, "movies:9")
        XCTAssertTrue(d.items[1].isFilm)
        XCTAssertNil(d.items[1].cover)
        XCTAssertEqual(d.items[0].what, "Episode 5")
        XCTAssertEqual(d.items[3].what, "Season 2 · Episode 4")
        XCTAssertEqual(AiringSchedule.detail(d.items[0]), "Episode 5 · Finale")
        XCTAssertEqual(AiringSchedule.detail(d.items[2]), "Sequel to A Show · Episode 1 · Premiere")
        XCTAssertEqual(AiringSchedule.timeLabel(d.items[1]), "All day")

        var every = AiringSchedule.Filter()
        every.shows = Set(AiringSchedule.Show.allCases)
        let rows = AiringSchedule.rows(d, library: [], filter: every)
        let status = Dictionary(rows.map { ($0.titleId, $0.status) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(status["anime:7"], .current, "from the entry the answer came with")
        XCTAssertEqual(status["tv:3"], .completed, "a Completed show's new episode")
        XCTAssertEqual(status["anime:8"], .some(nil), "a sequel you haven't added")
        XCTAssertEqual(status["movie:9"], .some(nil))
        // day-only things come first on their day; then by time
        XCTAssertEqual(rows.map(\.titleId), ["movie:9", "tv:3", "anime:8", "anime:7"], "by time, day-only first, then title")
    }

    func testTheCallAsksForTheMonthInMs() async throws {
        let t = DemoTransport()
        let api = APIClient(transport: t, token: "demo-token")
        let d = try await api.calendar(months: AiringSchedule.monthsToLoad(Clock.now, mode: .week)
                                       + [AiringSchedule.shift(Clock.now, mode: .month, by: 1)])
        XCTAssertEqual(t.requests.map(\.path), ["calendar", "calendar"])
        XCTAssertEqual(t.requests[0].query, [URLQueryItem(name: "from", value: "1793505600000"),
                                             URLQueryItem(name: "to", value: "1796101200000")])
        XCTAssertEqual(t.requests[1].query.first?.value, "1796101200000")
        XCTAssertEqual(d.from, 1_793_505_600_000)
        XCTAssertEqual(d.to, 1_798_779_600_000)
        XCTAssertEqual(Set(d.items.map(\.key)).count, d.items.count)
        XCTAssertNotNil(d.entries["anime:210482"])
    }

    // MARK: the demo months

    func testEveryMonthDecodesAndStaysInItsMonth() throws {
        for m in ["2026-10-15", "2026-11-15", "2026-12-15"] {
            let d = try month(m)
            XCTAssertFalse(d.items.isEmpty, m)
            for i in d.items {
                XCTAssertTrue(i.at >= d.from && i.at < d.to, i.key)
                XCTAssertEqual(AiringSchedule.monthKey(i.date), String(m.prefix(7)), i.key)
                XCTAssertNotNil(d.entries[i.entryKey], "\(i.key) is on the list")
                XCTAssertTrue(AiringSchedule.Filter.kinds.contains(i.titleKind))
            }
        }
    }

    func testTheDemoWeekIsNovFirstToSeventh() {
        let start = AiringSchedule.weekStart(Clock.now)
        XCTAssertEqual(Format.day(start), "2026-11-01")
        XCTAssertEqual(AiringSchedule.weekLabel(start), "Nov 1 – 7, 2026")
        XCTAssertEqual(AiringSchedule.monthsToLoad(Clock.now, mode: .week).map(AiringSchedule.monthKey), ["2026-11"])
        XCTAssertEqual(AiringSchedule.monthsToLoad(Clock.now, mode: .month).map(AiringSchedule.monthKey), ["2026-11"])
        XCTAssertEqual(AiringSchedule.weekDays(start).map(AiringSchedule.dayLabel).first, "Sun, Nov 1")
        XCTAssertEqual(AiringSchedule.longDayLabel(date("2026-11-06")), "Friday, Nov 6")
        XCTAssertEqual(AiringSchedule.monthLabel(Clock.now), "November 2026")
    }

    func testWeeksAcrossMonthsAndYears() {
        let back = AiringSchedule.shift(Clock.now, mode: .week, by: -1)
        XCTAssertEqual(AiringSchedule.weekLabel(back), "Oct 25 – 31, 2026")
        let late = AiringSchedule.shift(Clock.now, mode: .week, by: 4)
        XCTAssertEqual(AiringSchedule.weekLabel(late), "Nov 29 – Dec 5, 2026")
        XCTAssertEqual(AiringSchedule.monthsToLoad(late, mode: .week).map(AiringSchedule.monthKey), ["2026-11", "2026-12"])
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

    func testTheWeekOfTheDemo() throws {
        let rows = AiringSchedule.rows(try month("2026-11-15"), library: library())
        let week = AiringSchedule.days(rows, on: AiringSchedule.weekDays(AiringSchedule.weekStart(Clock.now)))
        let tue = week[2]
        XCTAssertTrue(AiringSchedule.isToday(tue.date))
        XCTAssertEqual(tue.rows.map { Format.time($0.item.date) }, ["7:26 AM"])
        XCTAssertTrue(tue.rows[0].item.title.hasPrefix("Nia Liston"))
        XCTAssertEqual(tue.rows[0].item.what, "Episode 5")
        XCTAssertEqual(AiringSchedule.nowIndex(tue.rows), 1, "aired before 9:41 AM")
        XCTAssertEqual(AiringSchedule.countLabel(tue.rows), "1 episode")
        XCTAssertTrue(AiringSchedule.isPast(week[0].date))
        XCTAssertEqual(AiringSchedule.countLabel(week[1].rows), "Nothing airing")
        // Slow Horses is on hold: not in the default filter; TMDB knows only its day
        XCTAssertTrue(week[3].rows.isEmpty)
        var f = AiringSchedule.Filter()
        f.shows.insert(.onHold)
        let wed = AiringSchedule.days(AiringSchedule.rows(try month("2026-11-15"), library: library(), filter: f),
                                      on: [date("2026-11-04")])[0]
        XCTAssertEqual(wed.rows.map(\.titleId), ["tv:95480"])
        XCTAssertEqual(wed.rows.first.map { AiringSchedule.timeLabel($0.item) }, "All day")
        XCTAssertEqual(wed.rows.first?.item.what, "Season 6 · Episode 4")
        XCTAssertEqual(wed.rows.first?.status, .hold)
    }

    func testFridayAndTheMonthDots() throws {
        let rows = AiringSchedule.rows(try month("2026-11-15"), library: library())
        let fri = AiringSchedule.days(rows, on: [date("2026-11-06")])[0]
        XCTAssertEqual(fri.rows.first?.titleId, "anime:210482")
        XCTAssertEqual(fri.rows.first.map { Format.time($0.item.date) }, "3:00 AM")
        XCTAssertEqual(fri.rows.first?.status, .current)
        XCTAssertEqual(AiringSchedule.dots(fri.rows), [.current, .planned])
        XCTAssertEqual(AiringSchedule.dots([]), [])
        XCTAssertEqual(AiringSchedule.legend(rows), [.current, .planned])
    }

    func testLibraryStatusWinsOverTheAnswers() throws {
        let d = try month("2026-11-15")
        var lib = library()
        let i = try XCTUnwrap(lib.firstIndex { $0.id == "anime:210482" })
        lib[i].status = .completed
        let rows = AiringSchedule.rows(d, library: lib)
        XCTAssertFalse(rows.contains { $0.titleId == "anime:210482" }, "Completed isn't in the default filter")
        lib[i].status = .dropped
        var every = AiringSchedule.Filter()
        every.shows = Set(AiringSchedule.Show.allCases)
        XCTAssertFalse(AiringSchedule.rows(d, library: lib, filter: every).contains { $0.titleId == "anime:210482" },
                       "dropped titles never show")
    }

    func testFilters() throws {
        let d = try month("2026-11-15")
        var f = AiringSchedule.Filter()
        f.media = .tv
        f.shows = Set(AiringSchedule.Show.allCases)
        let tv = AiringSchedule.rows(d, library: library(), filter: f)
        XCTAssertFalse(tv.isEmpty)
        XCTAssertTrue(tv.allSatisfy { $0.item.titleKind == .tv })
        var g = AiringSchedule.Filter()
        g.toggle(.planning)
        XCTAssertEqual(g.shows, [.watching])
        g.toggle(.completed)
        XCTAssertEqual(g.shows, [.watching, .completed])
        XCTAssertEqual(AiringSchedule.Filter().mediaLabel, "All types")
        XCTAssertEqual(AiringSchedule.Filter(media: .movie).mediaLabel, "Movies")
        XCTAssertEqual(AiringSchedule.statusLabel(nil, media: .anime), "Not on your list")
        XCTAssertEqual(AiringSchedule.statusLabel(.planned, media: .tv), "Plan to Watch")
    }

    func testCounts() {
        let ep = CalendarItem(key: "anime:1:ep2", media: .anime, id: "1", title: "A", kind: .episode, number: 2,
                              label: "Ep 2", at: Millis.of(Clock.now))
        let film = CalendarItem(key: "movies:2:release", media: .movies, id: "2", title: "B", kind: .release,
                                label: "Film", note: "In cinemas", at: Millis.of(Clock.now), dateOnly: true)
        XCTAssertEqual(film.titleId, "movie:2")
        XCTAssertEqual(AiringSchedule.detail(film), "Film · In cinemas")
        let rows = [AiringSchedule.Row(item: ep, status: .current), AiringSchedule.Row(item: film, status: .planned)]
        XCTAssertEqual(AiringSchedule.countLabel(rows), "2 releases")
        XCTAssertEqual(AiringSchedule.countLabel([rows[0]]), "1 episode")
    }

    func testMergedMonthsKeepOneOfEach() throws {
        let nov = try month("2026-11-15")
        let both = CalendarData.merged([nov, nov, try month("2026-12-15")])
        XCTAssertEqual(Set(both.items.map(\.key)).count, both.items.count)
        XCTAssertEqual(both.from, nov.from)
    }
}
