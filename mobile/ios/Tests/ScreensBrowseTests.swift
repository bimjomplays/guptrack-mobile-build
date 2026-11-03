import XCTest
@testable import GupTrack

/// Browse (11-15).
final class ScreensBrowseTests: ScreenTestCase {
    private let filters = "anime:genres=Action,Drama,Mystery&from=2020&season=fall&format=TV&status=releasing"

    func test11Browse() {
        let app = launch(["-tab", "browse"])
        expect(app, "This season")
        expect(app, "Fall 2026")
        expect(app, "STEEL BALL RUN")
        expect(app, "Trending now")
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertTrue(app.buttons["Filters"].exists)
        shot("11-browse")
    }

    func test12BrowseTV() {
        let app = launch(["-tab", "browse"])
        expect(app, "This season")
        app.buttons["TV"].tap()
        expect(app, "Severance")
        expect(app, "On the air")
        expect(app, "Popular")
        expect(app, "Score")
        shot("12-browse-tv")
    }

    func test13BrowseFilters() {
        let app = launch(["-tab", "browse", "-sheet", "filters/anime", "-browse-filters", filters])
        expect(app, "Sort by")
        expect(app, "3 selected")
        expect(app, "2020 – 2026")
        expect(app, "Show")
        expect(app, "results")
        shot("13-browse-filters")
    }

    func test14SeasonChart() {
        let app = launch(["-tab", "browse", "-open", "season-chart"])
        expect(app, "Anime season")
        expect(app, "Summer 2026")
        expect(app, "Winter 2027")
        expect(app, "The Apothecary Diaries")
        shot("14-season-chart")
    }

    func test15SearchResults() {
        let app = launch(["-tab", "browse"])
        expect(app, "This season")
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("chain")
        expect(app, "Top hit")
        expect(app, "Chainsaw Man")
        expect(app, "People")
        shot("15-search-results")
    }

    func testSearchPageShowsResults() {
        let app = launch(["-tab", "browse", "-open", "search/chain"])
        expect(app, "Top hit")
        expect(app, "Reze")
    }

    func testCardOpensItsTitle() {
        let app = launch(["-tab", "browse"])
        expect(app, "STEEL BALL RUN").tap()
        XCTAssertEqual(app.model.path(.browse).last, .title("anime:210482"))
    }

    func testThisSeasonOpensTheChart() {
        let app = launch(["-tab", "browse"])
        expect(app, "This season").tap()
        XCTAssertEqual(app.model.path(.browse).last, .seasonChart)
    }

    func testPlanToWatchAddsIt() {
        let app = launch(["-tab", "browse", "-open", "season-chart"])
        expect(app, "Black Clover")
        XCTAssertNil(app.model.entry("anime:195604"))
        app.buttons.matching(NSPredicate(format: "label == %@", "Plan to Watch")).firstMatch.tap()
        XCTAssertEqual(app.model.entry("anime:195604")?.status, .planned)
    }

    func testFiltersShowResults() {
        let app = launch(["-tab", "browse", "-sheet", "filters/anime", "-browse-filters", filters])
        expect(app, "results").tap()
        expect(app, "Results")
        expect(app, "Clear")
    }
}
