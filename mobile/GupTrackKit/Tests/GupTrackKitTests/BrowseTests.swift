import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Browse (11-15), docs/app-api.md §8.1–8.2: the answers decode as the doc writes them, the calls go where the doc
/// says, filters round-trip, the season chart groups, search reads right.
final class BrowseTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder.decode(T.self, from: Data(json.utf8))
    }

    static let frieren = #"""
    { "id": "anilist:154587", "source": "anilist", "sourceId": "154587", "title": "Frieren: Beyond Journey’s End",
      "alt": ["Sousou no Frieren"], "cover": "https://img.example/frieren.jpg", "format": "TV", "year": 2023,
      "season": "fall", "start": "2023-09-29", "status": "finished", "genres": ["Adventure", "Drama", "Fantasy"],
      "tags": ["Elf"], "score": 90, "popularity": 410000, "trending": 120, "count": 28, "by": "Madhouse",
      "newField": 1 }
    """#

    static let dune = #"""
    { "id": "tmdb:movie:693134", "source": "tmdb", "sourceId": "movie/693134", "title": "Dune: Part Two",
      "cover": "/api/app/v1/pictures/dune.jpg", "format": "Film", "year": 2024, "season": null, "start": "2024-02-27",
      "status": "finished", "genres": ["Science Fiction"], "tags": [], "score": 82, "popularity": 900,
      "trending": 40, "count": 167, "by": "Denis Villeneuve" }
    """#

    // MARK: §8.1 answers

    func testCatalogTitleDecodesAndBecomesATitle() throws {
        let c = try decode(CatalogTitle.self, Self.frieren)
        XCTAssertEqual(c.status, .finished)
        XCTAssertEqual(c.season, .fall)
        let t = c.title(.anime)
        XCTAssertEqual(t.id, "anime:154587")
        XCTAssertEqual(t.score, 9.0, "0–100 shown out of 10")
        XCTAssertEqual(t.total, 28)
        XCTAssertEqual(t.state, "Finished")
        XCTAssertEqual(t.studio, "Madhouse")

        let m = try decode(CatalogTitle.self, Self.dune)
        XCTAssertEqual(m.ref(.movies), TitleRef(kind: .movie, id: "693134"))
        let film = m.title(.movies)
        XCTAssertEqual(film.id, "movie:693134")
        XCTAssertNil(film.total, "a film's count is its runtime")
        XCTAssertEqual(film.runtime, "2h 47m")
        // a "/" picture stays a relative address for the image loader
        XCTAssertEqual(film.cover?.absoluteString, "/api/app/v1/pictures/dune.jpg")
    }

    func testShelvesAnswer() throws {
        let a = try decode(BrowseShelves.self, #"""
        { "shelves": [
          { "spec": { "title": "This season", "note": "Fall 2026", "filter": { "season": "fall", "from": 2026, "to": 2026 },
                      "chart": true, "min": 4 }, "titles": [\#(Self.frieren)] },
          { "spec": { "title": "Top rated", "filter": { "sort": "top", "genres": "Drama,Mystery" }, "min": 4, "fresh": true },
            "titles": [\#(Self.frieren)] },
          { "spec": { "title": "Empty", "filter": {}, "min": 4 }, "titles": [] }
        ] }
        """#)
        XCTAssertEqual(a.shelves.count, 3)
        XCTAssertEqual(a.shelves[0].spec.filter.season, .fall)
        XCTAssertEqual(a.shelves[1].spec.filter.genres, ["Drama", "Mystery"])
        XCTAssertEqual(a.shelves[1].spec.filter.sort, .top)

        let anime = BrowsePage(.anime, a)
        XCTAssertNil(anime.feature)
        XCTAssertEqual(anime.shelves.map(\.title), ["This season", "Top rated"], "empty shelves go")
        XCTAssertTrue(anime.shelves[0].chart)
        XCTAssertEqual(anime.shelves[0].note, "Fall 2026")
    }

    func testTVAndMoviesLeadWithTheFirstShelfsFirstTitle() throws {
        let a = try decode(BrowseShelves.self, #"""
        { "shelves": [
          { "spec": { "title": "Trending", "filter": { "sort": "trending" }, "min": 4 }, "titles": [\#(Self.dune), \#(Self.dune)] },
          { "spec": { "title": "Top rated", "filter": { "sort": "top" }, "min": 4 }, "titles": [\#(Self.dune)] }
        ] }
        """#)
        let p = BrowsePage(.movie, a)
        XCTAssertEqual(p.feature?.label, "Trending")
        XCTAssertEqual(p.feature?.title.name, "Dune: Part Two")
        XCTAssertEqual(p.shelves.first?.titles.count, 1)
    }

    func testFacetsAndResults() throws {
        let f = try decode(Facets.self, #"{"genres":["Action","Drama"],"tags":["Elf","Time Skip"]}"#)
        XCTAssertEqual(f.tags, ["Elf", "Time Skip"])
        let r = try decode(BrowseResults.self, #"{"titles":[\#(Self.frieren)],"total":null,"more":true,"next":2}"#)
        XCTAssertNil(r.total)
        XCTAssertEqual(r.next, 2)
        let page = BrowseResultsPage(.anime, r, BrowseFilters())
        XCTAssertEqual(page.showText, "Show 1+ results")
        let all = BrowseResultsPage(titles: [], total: 120, more: false, next: nil)
        XCTAssertEqual(all.showText, "Show 120 results")
    }

    // MARK: filters

    func testFiltersQueryIsTheWebsitesAddress() {
        var f = BrowseFilters()
        f.sort = .top
        f.genres = ["Action", "Drama"]
        f.from = 2020
        f.season = .fall
        f.format = "TV"
        f.status = .releasing
        f.score = 8.5
        XCTAssertEqual(f.encoded, "sort=top&genres=Action,Drama&format=TV&from=2020&season=fall&status=releasing&score=8.5")
        XCTAssertEqual(BrowseFilters(encoded: f.encoded), f)
        XCTAssertEqual(f.query(page: 3).last, URLQueryItem(name: "page", value: "3"))
        XCTAssertFalse(f.query().contains { $0.name == "page" }, "page 1 is left out")
        // values that make no sense are dropped quietly
        let bad = BrowseFilters(encoded: "season=autumn&status=airing&from=1066&score=11&sort=best&genres=Action")
        XCTAssertEqual(bad, BrowseFilters(genres: ["Action"]))
    }

    func testFiltersTextAndCounts() {
        var f = BrowseFilters()
        XCTAssertTrue(f.isEmpty)
        XCTAssertEqual(f.yearLabel, "Any year")
        f.genres = ["Action", "Drama", "Mystery"]
        f.from = 2020
        XCTAssertEqual(BrowseFilters.chipText("Genres", f.genres), "Action +2")
        XCTAssertEqual(f.yearLabel, "2020 – \(BrowseFilters.lastYear)")
        XCTAssertEqual(BrowseFilters.scoreText(8), "★ 8+")
        XCTAssertTrue(BrowseFilters.hasSeason(.anime))
        XCTAssertFalse(BrowseFilters.hasSeason(.tv))
    }

    func testFilterStoreKeepsEachMedia() {
        var s = ""
        s = BrowseFilterStore.set(s, .anime, BrowseFilters(genres: ["Action"]))
        s = BrowseFilterStore.set(s, .tv, BrowseFilters(sort: .new))
        XCTAssertEqual(BrowseFilterStore.get(s, .anime).genres, ["Action"])
        XCTAssertEqual(BrowseFilterStore.get(s, .tv).sort, .new)
        XCTAssertTrue(BrowseFilterStore.get(s, .book).isEmpty)
    }

    func testFiltersMatchAsTheWebsiteDoes() throws {
        let c = try decode(CatalogTitle.self, Self.frieren)
        XCTAssertTrue(BrowseFilters(genres: ["Drama", "Fantasy"]).matches(c))
        XCTAssertFalse(BrowseFilters(genres: ["Drama", "Horror"]).matches(c), "every genre must match")
        XCTAssertFalse(BrowseFilters(from: 2024).matches(c))
        XCTAssertTrue(BrowseFilters(season: .fall).matches(c))
        XCTAssertFalse(BrowseFilters(status: .releasing).matches(c))
    }

    /// the filters sheet's screen (13) shows a count the demo catalogue really has
    func testDemoFiltersCountForTheSheet() async throws {
        let api = APIClient(transport: DemoTransport(), token: "demo")
        let f = BrowseFilterStore.get("anime:genres=Action,Adventure,Fantasy&from=2020&season=fall&format=TV&status=releasing", .anime)
        XCTAssertEqual(f.genres, ["Action", "Adventure", "Fantasy"])
        let page = try await api.browseTitles(.anime, f)
        XCTAssertEqual(page.showText, "Show 4 results")
    }

    // MARK: the season chart

    func testSeasonChartAnswer() throws {
        let entry = Self.frieren.replacingOccurrences(of: "\"newField\": 1", with: "\"next\": { \"episode\": 7, \"at\": 1793800000 }, \"carried\": true")
        let c = try decode(SeasonChart.self, #"{"season":"fall","year":2026,"titles":[\#(entry)]}"#)
        XCTAssertEqual(c.label, "Fall 2026")
        XCTAssertTrue(c.titles[0].carried)
        let t = c.rows[0]
        XCTAssertEqual(t.next?.episode, 7)
        XCTAssertEqual(t.next?.at, Date(timeIntervalSince1970: 1_793_800_000), "seconds, not ms")
        XCTAssertEqual(c.count(.tv), 1)
        XCTAssertEqual(c.count(.film), 0)
    }

    func testSeasonRefsStepAndStartFromToday() {
        let now = SeasonChart.Ref.of(Clock.now)
        XCTAssertEqual(now, SeasonChart.Ref(season: .fall, year: 2026))
        XCTAssertEqual(now.next, SeasonChart.Ref(season: .winter, year: 2027))
        XCTAssertEqual(now.previous.label, "Summer 2026")
        XCTAssertEqual(SeasonChart.Ref(season: .winter, year: 2027).previous, now)
        XCTAssertEqual(now.slug, "fall-2026")
    }

    // MARK: §8.2 search

    func testSearchAnswer() throws {
        let a = try decode(SearchAnswer.self, #"""
        { "groups": [
          { "title": "Anime", "hits": [
            { "ref": { "to": "title", "kind": "anime", "id": "127230" }, "name": "Chainsaw Man",
              "image": "https://img.example/csm.jpg", "note": "Anime · TV · 2022" } ] },
          { "title": "Characters", "hits": [
            { "ref": { "to": "character", "id": "138101" }, "name": "Reze", "image": null, "note": "Chainsaw Man" } ] },
          { "title": "People", "hits": [
            { "ref": { "to": "person", "source": "anilist", "id": "118739" }, "name": "Tatsuki Fujimoto",
              "image": null, "note": "Story & Art" },
            { "ref": { "to": "author", "id": "OL7234434A" }, "name": "Andy Weir", "image": null, "note": "Author" },
            { "ref": { "to": "network", "id": "49" }, "name": "HBO", "image": null, "note": "TV network" },
            { "ref": { "to": "something-new", "id": "1" }, "name": "Later", "image": null, "note": "" } ] }
        ] }
        """#)
        let r = SearchResults(query: "chain", groups: a.groups)
        XCTAssertEqual(r.top?.name, "Chainsaw Man")
        XCTAssertEqual(r.top?.route, .title("anime:127230"))
        XCTAssertEqual(SearchResults.topLine(r.top!), "Top hit · Anime · TV · 2022")
        XCTAssertEqual(r.scopes.map(\.0), ["All", "Anime", "Characters", "People"])
        XCTAssertEqual(r.scopes[3].1, 4)
        XCTAssertEqual(r.shown("All").map(\.title), ["Characters", "People"], "the top hit isn't shown twice")
        let people = a.groups[2].hits.map(\.route)
        XCTAssertEqual(people, [.person("anilist:118739"), .author("OL7234434A"), .studio("network:49"), nil])
        XCTAssertEqual(a.groups[1].hits[0].route, .character("138101"))
    }

    // MARK: calls

    func testCallsGoWhereTheDocSays() async throws {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "demo-token")

        t.reply(#"{"shelves":[]}"#)
        _ = try await api.browseShelves(.movie)
        t.reply(#"{"genres":[],"tags":[]}"#)
        _ = try await api.browseFacets(.book)
        t.reply(#"{"titles":[],"total":0,"more":false,"next":null}"#)
        _ = try await api.browseResults(.tv, BrowseFilters(genres: ["Drama"], sort: .top), page: 2)
        t.reply(#"{"season":"winter","year":2027,"titles":[]}"#)
        _ = try await api.seasonChart(SeasonChart.Ref(season: .winter, year: 2027))
        t.reply(#"{"groups":[]}"#)
        _ = try await api.search("  chainsaw  ")

        XCTAssertEqual(t.sent.map(\.method), ["GET", "GET", "GET", "GET", "GET"])
        XCTAssertEqual(t.sent.map(\.path), ["browse/movies/shelves", "browse/books/filters", "browse/tv/results",
                                            "season-chart", "search"])
        XCTAssertEqual(t.sent[2].query, [URLQueryItem(name: "sort", value: "top"), URLQueryItem(name: "genres", value: "Drama"),
                                         URLQueryItem(name: "page", value: "2")])
        XCTAssertEqual(t.sent[3].query, [URLQueryItem(name: "season", value: "winter"), URLQueryItem(name: "year", value: "2027")])
        XCTAssertEqual(t.sent[4].query, [URLQueryItem(name: "q", value: "chainsaw")])
        XCTAssertTrue(t.sent.allSatisfy { $0.body == nil })
    }

    func testSearchKeepsTo80Characters() async throws {
        let t = StubTransport()
        t.reply(#"{"groups":[]}"#)
        let api = APIClient(transport: t, token: "demo-token")
        _ = try await api.search(String(repeating: "a", count: 120))
        XCTAssertEqual(t.sent[0].query.first?.value?.count, 80)
    }

    // MARK: the demo's answers

    func testDemoAnswersDecode() throws {
        for m in MediaKind.allCases {
            let a = try Demo.load(BrowseShelves.self, "api/browse/\(m.api.rawValue)/shelves.json")
            XCTAssertFalse(BrowsePage(m, a).shelves.isEmpty, "\(m)")
            _ = try Demo.load(Facets.self, "api/browse/\(m.api.rawValue)/filters.json")
            _ = try Demo.load(BrowseResults.self, "api/browse/\(m.api.rawValue)/results.json")
        }
        for s in ["summer", "fall", "winter"] {
            let c = try Demo.load(SeasonChart.self, "api/season-chart/\(s).json")
            XCTAssertFalse(c.titles.isEmpty, s)
        }
        let s = try Demo.load(SearchAnswer.self, "api/search/chain.json")
        XCTAssertFalse(s.groups.isEmpty)
    }
}
