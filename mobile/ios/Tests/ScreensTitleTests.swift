import XCTest
@testable import GupTrack

/// Title pages (16, 17, 20-25): one layout for every media, and the TV season page.
final class ScreensTitleTests: ScreenTestCase {
    private func open(_ id: String) -> App { launch(["-open", "title/" + id]) }

    func test16TitleAnime() {
        let app = open("anime:210482")
        expect(app, "STEEL BALL RUN")
        expect(app, "Open in Harbor")
        expect(app, "Your list")
        expect(app, "david production")
        XCTAssertTrue(app.buttons["Send to a friend"].exists)
        shot("16-title-anime")
    }

    func test17TitleAnimeScrolled() {
        let app = open("anime:210482")
        expect(app, "Your list")
        scroll(app, until: "Characters & voices", top: 120)
        expect(app, "Gyro Zeppeli")
        shot("17-title-anime-scrolled")
    }

    func test20TitleMoreMenu() {
        let app = open("anime:210482")
        expect(app, "Your list")
        app.buttons["More"].tap()
        expect(app, "Write a review")
        expect(app, "Open on AniList")
        expect(app, "Remove from list")
        shot("20-title-more-menu")
    }

    func test21TitleTV() {
        let app = open("tv:95396")
        expect(app, "Severance")
        expect(app, "Series · 2022– · 2 seasons")
        expect(app, "Dan Erickson")
        expect(app, "Your list · Season")
        expect(app, "Up next")
        shot("21-title-tv")
    }

    func test22TVSeason() {
        let app = launch(["-open", "title/tv:95396", "-open", "season/tv:95396/2"])
        expect(app, "Season 2")
        expect(app, "watched")
        XCTAssertTrue(app.buttons["Mark all watched"].exists)
        shot("22-tv-season")
    }

    func test23TitleMovie() {
        let app = open("movie:693134")
        expect(app, "Dune: Part Two")
        expect(app, "Film · 2024 · 2h 47m")
        expect(app, "Trailer")
        shot("23-title-movie")
    }

    func test23bTitleMovieScrolled() {
        let app = open("movie:693134")
        expect(app, "Dune: Part Two")
        scroll(app, until: "Cast", top: 120)
        expect(app, "Paul Atreides")
        shot("23b-title-movie-scrolled")
    }

    func test24TitleManga() {
        let app = open("manga:105778")
        expect(app, "Chainsaw Man")
        let next = (app.model.entry("manga:105778")?.progress ?? 0) + 1
        expect(app, "Mark Ch \(next) read")
        expect(app, "Tatsuki Fujimoto")
        XCTAssertFalse(find(app, "Open in Harbor").exists, "Harbor doesn't play manga")
        shot("24-title-manga")
    }

    func test25TitleBook() {
        let app = open("book:OL21745884W")
        expect(app, "Project Hail Mary")
        expect(app, "Novel · 2021 · 496 pages")
        expect(app, "Update progress")
        expect(app, "+ and − move 10 pages")
        shot("25-title-book")
    }

    // MARK: behaviour

    func testPlusStepsTheTitlesProgress() {
        let app = open("anime:210482")
        expect(app, "Your list")
        let before = app.model.entry("anime:210482")?.progress ?? 0
        app.buttons["One more"].tap()
        XCTAssertEqual(app.model.entry("anime:210482")?.progress, before + 1)
    }

    func testEditOpensTheEditor() {
        let app = open("anime:210482")
        expect(app, "Your list")
        app.buttons["Edit your list entry"].tap()
        XCTAssertEqual(app.model.sheet, .editor("anime:210482", expanded: false))
    }

    func testMarkingAChapterRead() {
        let app = open("manga:105778")
        let before = app.model.entry("manga:105778")?.progress ?? 0
        expect(app, "Mark Ch \(before + 1) read").tap()
        XCTAssertEqual(app.model.entry("manga:105778")?.progress, before + 1)
    }

    func testRelatedOpensTheTitle() {
        let app = open("anime:210482")
        expect(app, "Your list")
        scroll(app, until: "Prequel", top: 300)
        expect(app, "Prequel").tap()
        XCTAssertEqual(app.model.path(.browse).last, .title("anime:190327"))
    }

    func testTheEpisodeCircleMarksItWatched() {
        let app = launch(["-open", "title/tv:95396", "-open", "season/tv:95396/2"])
        expect(app, "Season 2")
        let before = app.model.entry("tv:95396")?.progress ?? 0
        let next = before - 9 + 1
        scroll(app, until: "Mark episode \(next) watched", top: 400)
        app.buttons["Mark episode \(next) watched"].tap()
        XCTAssertEqual(app.model.entry("tv:95396")?.progress, before + 1)
    }

    func testATitleOffTheListCanBeAdded() {
        let app = open("anime:20474")
        expect(app, "Not in your list")
        app.buttons["Add to List"].tap()
        XCTAssertEqual(app.model.entry("anime:20474")?.status, .planned)
    }

}
