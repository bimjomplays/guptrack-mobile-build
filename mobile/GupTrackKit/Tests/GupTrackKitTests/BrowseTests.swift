import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// Browse (11-15): the pages decode, filters filter, the season chart groups, search captions read right.
final class BrowseTests: XCTestCase {
    override func setUp() {
        Clock.fixed = Clock.demoNow
        Clock.fixedZone = Clock.demoZone
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func library() throws -> [LibraryEntry] { try Demo.load([LibraryEntry].self, "api/library.json") }

    // MARK: pages

    func testEveryMediaHasABrowsePage() throws {
        for m in MediaKind.allCases {
            let page = try Demo.load(BrowsePage.self, Demo.file("browse", variant: m.rawValue))
            XCTAssertEqual(page.media, m)
            XCTAssertGreaterThanOrEqual(page.shelves.count, 2, "\(m)")
            XCTAssertTrue(page.shelves.allSatisfy { !$0.titles.isEmpty && $0.titles.allSatisfy { $0.media == m } }, "\(m)")
            XCTAssertEqual(page.feature != nil, m == .tv || m == .movie, "TMDB media get the feature card")
            let pool = try Demo.load([Title].self, Demo.file("browse/titles", variant: m.rawValue))
            XCTAssertGreaterThanOrEqual(pool.count, 10, "\(m)")
            XCTAssertTrue(pool.allSatisfy { $0.media == m })
        }
    }

    func testAnimePageStartsWithThisSeason() throws {
        let page = try Demo.load(BrowsePage.self, "api/browse/anime.json")
        let season = page.shelves[0]
        XCTAssertEqual(season.title, "This season")
        XCTAssertEqual(season.sub, "Fall 2026 · 50 anime")
        XCTAssertEqual(season.route, .seasonChart)
        XCTAssertEqual(season.titles.prefix(3).map(\.id), ["anime:210482", "anime:195539", "anime:195516"])
        XCTAssertFalse(page.shelves[1].titles.contains { $0.id == "anime:21" })
        XCTAssertEqual(page.shelves[1].sort, .popularity)
    }

    func testTVFeatureIsPluribus() throws {
        let page = try Demo.load(BrowsePage.self, "api/browse/tv.json")
        XCTAssertEqual(page.feature?.title.name, "Pluribus")
        XCTAssertEqual(page.feature?.label, "Most added this week")
        XCTAssertEqual(page.feature?.line, "2025 · Drama · ★ 7.9")
        XCTAssertEqual(page.shelves.map(\.title), ["Popular shows", "Top rated"])
        XCTAssertEqual(page.shelves[0].titles.prefix(3).map(\.name), ["Severance", "The Last of Us", "Shōgun"])
    }

    func testAnimeFilmsStayUnderAnime() throws {
        let films = try Demo.load([Title].self, "api/browse/titles/movie.json")
        XCTAssertFalse(films.contains { $0.id.hasPrefix("anime:") })
        let anime = try Demo.load([Title].self, "api/browse/titles/anime.json")
        XCTAssertTrue(anime.contains { $0.format == "Movie" })
    }

    func testCaptionIsYourStatusElseTheScore() throws {
        let lib = try library()
        let page = try Demo.load(BrowsePage.self, "api/browse/anime.json")
        let sbr = page.shelves[0].titles[0]
        let e = lib.first { $0.id == sbr.id }
        XCTAssertEqual(BrowseCaption.of(sbr, entry: e), .status(.current, .anime))
        var t = Make.title()
        t.score = 8.5
        XCTAssertEqual(BrowseCaption.of(t, entry: nil), .score("8.5", year: nil))
        t.year = 2022
        XCTAssertEqual(BrowseCaption.of(t, entry: nil, withYear: true), .score("8.5", year: 2022))
        t.score = nil
        t.format = "Movie"
        XCTAssertEqual(BrowseCaption.of(t, entry: nil), .text("Film"))
        XCTAssertEqual(BrowseAdd.label(.manga), "Plan to Read")
    }

    // MARK: filters

    private let mockup = "genres=Action,Drama,Mystery&years=2020-&season=Fall&formats=TV,ONA&statuses=Airing"

    func testFiltersRoundTripThroughTheirSavedForm() {
        let f = BrowseFilters(sort: .score, genres: ["Action", "Drama"], yearFrom: 2020, season: "Fall",
                              formats: ["TV", "ONA"], statuses: ["Airing"], minScore: 7)
        XCTAssertEqual(BrowseFilters(encoded: f.encoded), f)
        XCTAssertEqual(f.query(.anime).first, URLQueryItem(name: "media", value: "anime"))
        XCTAssertEqual(f.count, 6)
        XCTAssertTrue(BrowseFilters(sort: .title).isEmpty)
        let saved = BrowseFilterStore.set("", .anime, f)
        XCTAssertEqual(BrowseFilterStore.get(saved, .anime), f)
        XCTAssertEqual(BrowseFilterStore.get(saved, .tv), BrowseFilters())
        XCTAssertEqual(BrowseFilterStore.set(saved, .anime, BrowseFilters()), "")
    }

    func testTheMockupsFiltersFindFallActionShows() throws {
        let f = BrowseFilters(encoded: mockup)
        XCTAssertEqual(f.genres, ["Action", "Drama", "Mystery"])
        XCTAssertEqual(f.yearLabel, "2020 – 2026")
        let pool = try Demo.load([Title].self, "api/browse/titles/anime.json")
        let found = f.apply(pool)
        XCTAssertFalse(found.isEmpty)
        XCTAssertLessThan(found.count, pool.count)
        for t in found {
            XCTAssertTrue(t.season?.hasPrefix("Fall") ?? false)
            XCTAssertTrue(["TV", "ONA"].contains(t.format ?? ""))
            XCTAssertTrue(Set(t.genres ?? []).isSuperset(of: ["Action", "Drama", "Mystery"]))
        }
        // one genre finds more
        var loose = f
        loose.genres = ["Action"]
        XCTAssertGreaterThan(loose.apply(pool).count, found.count)
    }

    func testYearSliderEndsMeanNoLimit() {
        var f = BrowseFilters()
        XCTAssertEqual(f.yearRange, BrowseFilters.firstYear...2026)
        XCTAssertEqual(f.yearLabel, "Any year")
        f.setYears(2020...2026)
        XCTAssertEqual(f.yearFrom, 2020)
        XCTAssertNil(f.yearTo)
        XCTAssertEqual(f.yearLabel, "2020 – 2026")
        f.setYears(BrowseFilters.firstYear...2015)
        XCTAssertNil(f.yearFrom)
        XCTAssertEqual(f.yearLabel, "Up to 2015")
    }

    func testSortsAndChipText() {
        let a = Title(id: "anime:1", media: .anime, name: "Beta", year: 2020, score: 7)
        let b = Title(id: "anime:2", media: .anime, name: "alpha", year: 2024, score: 9)
        XCTAssertEqual(BrowseFilters(sort: .popularity).apply([a, b]).map(\.id), ["anime:1", "anime:2"])
        XCTAssertEqual(BrowseFilters(sort: .score).apply([a, b]).map(\.id), ["anime:2", "anime:1"])
        XCTAssertEqual(BrowseFilters(sort: .newest).apply([a, b]).map(\.id), ["anime:2", "anime:1"])
        XCTAssertEqual(BrowseFilters(sort: .title).apply([a, b]).map(\.id), ["anime:2", "anime:1"])
        XCTAssertEqual(BrowseFilters.chipText("Genres", []), "Genres")
        XCTAssertEqual(BrowseFilters.chipText("Genres", ["Action"]), "Action")
        XCTAssertEqual(BrowseFilters.chipText("Genres", ["Action", "Drama"]), "Action +1")
    }

    func testStatusFilterKeepsTitlesWithoutAState() {
        let shows = [Title(id: "tv:1", media: .tv, name: "A"), Title(id: "tv:2", media: .tv, name: "B", state: "Ended")]
        XCTAssertEqual(BrowseFilters(statuses: ["Airing"]).apply(shows).map(\.id), ["tv:1"])
    }

    // MARK: season chart

    func testSeasonsStepAcrossTheYear() {
        let fall = SeasonChart.Ref.current
        XCTAssertEqual(fall, SeasonChart.Ref(name: "Fall", year: 2026))
        XCTAssertEqual(fall.previous.label, "Summer 2026")
        XCTAssertEqual(fall.next.label, "Winter 2027")
        XCTAssertEqual(fall.next.previous, fall)
        XCTAssertEqual(fall.slug, "fall-2026")
    }

    func testFallChartGroupsByFormat() throws {
        let chart = try Demo.load(SeasonChart.self, "api/season-chart/fall-2026.json")
        XCTAssertEqual(chart.season, "Fall 2026")
        XCTAssertEqual(chart.subtitle, "Anime season · 50 anime")
        XCTAssertEqual(chart.kinds.map(\.0), [.all, .tv, .ona, .movies, .other])
        XCTAssertEqual(chart.kinds.map(\.1).dropFirst().reduce(0, +), 50)
        let groups = chart.groups(.all)
        XCTAssertEqual(groups.map(\.kind), [.tv, .ona, .movies, .other])
        XCTAssertEqual(groups[0].titles.first?.name, "The Apothecary Diaries Season 3")
        XCTAssertEqual(groups[1].titles.first?.id, "anime:210482")
        XCTAssertEqual(chart.groups(.ona).map(\.kind), [.ona])
        let hidden = chart.groups(.ona, hide: ["anime:210482"])
        XCTAssertFalse(hidden[0].titles.contains { $0.id == "anime:210482" })
        for s in ["summer-2026", "winter-2027"] {
            XCTAssertNoThrow(try Demo.load(SeasonChart.self, "api/season-chart/\(s).json"))
        }
    }

    func testChartRowLines() throws {
        let chart = try Demo.load(SeasonChart.self, "api/season-chart/fall-2026.json")
        let sbr = chart.titles.first { $0.id == "anime:210482" }!
        XCTAssertEqual(SeasonChart.airing(sbr)?.text, "Ep 7 · Fri 3:00 AM · in 3 days")
        let edge = chart.titles.first { $0.id == "anime:195539" }!
        XCTAssertEqual(SeasonChart.facts(edge), "TRIGGER · 10 episodes")
        XCTAssertEqual(SeasonChart.genres(edge), "Action, Drama")
        XCTAssertEqual(SeasonChart.airing(edge)?.text, "All 10 out")
        let byNext = SeasonChart.ordered(chart.titles, .airing, now: Clock.now)
        XCTAssertNotNil(byNext.first?.next)
    }

    // MARK: search

    func testChainFindsChainsawMan() throws {
        let r = try Demo.load(SearchResults.self, Demo.file("search", variant: "chain"))
        XCTAssertEqual(r.top?.id, "anime:127230")
        XCTAssertEqual(r.top.map(SearchResults.topLine), "Top hit · Anime · 2022")
        XCTAssertEqual(r.top.map(SearchResults.topFacts), "MAPPA · 12 episodes")
        XCTAssertEqual(r.scopes.map(\.0), [.all, .anime, .manga, .people])
        XCTAssertEqual(r.scopes[1].1, 4)
        let all = r.shown(.all)
        XCTAssertFalse(all[0].titles.contains { $0.id == r.top?.id }, "the top hit isn't repeated")
        XCTAssertEqual(SearchResults.caption(all[0].titles[0]), "Film · 2025 · MAPPA")
        XCTAssertEqual(SearchResults.caption(all[0].titles[1]), "Anime · Not yet aired · MAPPA")
        XCTAssertEqual(SearchResults.caption(r.shown(.manga)[0].titles[0]), "Manga · 2018 · 232 chapters")
        XCTAssertEqual(r.shown(.anime)[0].titles.count, 4)
        let fujimoto = r.shown(.people)[0].people[0]
        XCTAssertEqual(fujimoto.name, "Tatsuki Fujimoto")
        XCTAssertEqual(fujimoto.route, .person("person:119917"))
    }

    func testSearchVariantsAndNothingFound() throws {
        XCTAssertEqual(Demo.file("search", variant: "Chainsaw Man"), "api/search/chainsaw-man.json")
        let dune = try Demo.load(SearchResults.self, Demo.file("search", variant: "dune"))
        XCTAssertEqual(dune.scopes.map(\.0), [.all, .movie, .book, .people])
        XCTAssertEqual(dune.top.map(SearchResults.caption), "Movie · 2024 · 2h 47m")
        let none = try Demo.load(SearchResults.self, "api/search.json")
        XCTAssertTrue(none.isEmpty)
    }

    func testSearchGoesThroughTheDemo() async throws {
        let api = APIClient(transport: DemoTransport(), token: "demo-token")
        let r = try await api.search("chain")
        XCTAssertEqual(r.top?.name, "Chainsaw Man")
        let nothing = try await api.search("zzz")
        XCTAssertTrue(nothing.isEmpty)
        let page = try await api.browsePage(.tv)
        XCTAssertEqual(page.media, .tv)
        let found = try await api.browseTitles(.anime, BrowseFilters(encoded: mockup))
        XCTAssertFalse(found.isEmpty)
        let chart = try await api.seasonChart(.current)
        XCTAssertEqual(chart.season, "Fall 2026")
    }

    func testImagesComeFromTheCatalogueCDNs() throws {
        let hosts = ["s4.anilist.co", "image.tmdb.org", "covers.openlibrary.org"]
        var urls: [URL] = []
        for m in MediaKind.allCases {
            let p = try Demo.load(BrowsePage.self, Demo.file("browse", variant: m.rawValue))
            urls += p.shelves.flatMap(\.titles).compactMap(\.cover) + [p.feature?.title.banner].compactMap { $0 }
        }
        for q in ["chain", "dune"] {
            let r = try Demo.load(SearchResults.self, Demo.file("search", variant: q))
            urls += r.groups.flatMap(\.people).compactMap(\.image)
        }
        for u in urls { XCTAssertTrue(hosts.contains(u.host ?? ""), u.absoluteString) }
    }
}
