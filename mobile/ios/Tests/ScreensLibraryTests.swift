import XCTest
@testable import GupTrack

/// Library (32-40): the tab, a media list as rows and covers, its title and sort menus, the swipe actions, a custom
/// list, editing it and a new list.
final class ScreensLibraryTests: ScreenTestCase {
    private let sbr = "anime:210482"

    func test32Library() {
        let app = launch(["-tab", "library"])
        expect(app, "Anime")
        expect(app, "Books")
        expect(app, "Your lists")
        expect(app, "Rainy Sundays")
        XCTAssertTrue(app.buttons["Search"].exists)
        XCTAssertTrue(app.buttons["More"].exists)
        shot("32-library")
    }

    func test33ListRows() {
        let app = rows()
        expect(app, "STEEL BALL RUN")
        expect(app, "Watching")
        expect(app, "mean score")
        shot("33-library-list-rows")
    }

    func test34ListCovers() {
        let app = rows()
        expect(app, "STEEL BALL RUN")
        app.buttons["Show covers"].tap()
        XCTAssertTrue(app.buttons["Show rows"].waitForExistence(timeout: 5))
        expect(app, "STEEL BALL RUN")
        shot("34-library-list-covers")
        app.buttons["Show rows"].tap()
    }

    func test35SwitchMedia() {
        let app = rows()
        expect(app, "STEEL BALL RUN")
        let title = app.buttons.matching(NSPredicate(format: "label == %@", "Anime")).firstMatch
        if title.exists { title.tap() } else { find(app, "Anime").tap() }
        expect(app, "Your lists")
        expect(app, "Covers")
        shot("35-library-switch-media")
    }

    func test36Sort() {
        let app = rows()
        expect(app, "STEEL BALL RUN")
        app.buttons["Sort"].tap()
        expect(app, "Last updated")
        expect(app, "All formats")
        shot("36-library-sort")
    }

    func test37Swipe() {
        let app = rows()
        let row = expect(app, "STEEL BALL RUN")
        let f = row.frame
        Finger.press(CGPoint(x: f.maxX - 30, y: f.midY), seconds: 0,
                     thenDragTo: CGPoint(x: f.minX + 60, y: f.midY), speed: 300, hold: 0.3)
        expect(app, "Drop")
        expect(app, "Rate")
        shot("37-library-swipe")
    }

    func test38CustomList() {
        let app = launch(["-tab", "library", "-open", "custom-list/rainy-sundays"])
        expect(app, "Rainy Sundays")
        expect(app, "Edit list")
        expect(app, "Add titles")
        expect(app, "Shuffle")
        expect(app, "Steins;Gate")
        shot("38-custom-list")
    }

    func test39EditList() {
        let app = launch(["-tab", "library", "-sheet", "edit-list/rainy-sundays"])
        expect(app, "Edit list")
        expect(app, "drag to reorder")
        expect(app, "Who can see it")
        expect(app, "Add a note")
        shot("39-custom-list-edit")
    }

    func test40NewList() {
        let app = launch(["-tab", "library", "-sheet", "new-list"])
        expect(app, "New list")
        expect(app, "Description (optional)")
        expect(app, "Anyone signed in to GupTrack")
        shot("40-new-list")
    }

    // MARK: behaviour

    func testMediaRowOpensItsList() {
        let app = launch(["-tab", "library"])
        expect(app, "Manga").tap()
        XCTAssertTrue(poll(5) { app.model.path(.library).last == .list(.manga) })
    }

    func testListCardOpensTheList() {
        let app = launch(["-tab", "library"])
        expect(app, "Rainy Sundays").tap()
        XCTAssertTrue(poll(5) { app.model.path(.library).last == .customList("rainy-sundays") })
    }

    func testRowOpensItsTitle() {
        let app = rows()
        expect(app, "STEEL BALL RUN").tap()
        XCTAssertTrue(poll(5) { app.model.path(.library).last == .title(self.sbr) })
    }

    func testPlusOneStepsProgress() {
        let app = rows()
        expect(app, "STEEL BALL RUN")
        let before = app.model.entry(sbr)?.progress ?? 0
        app.buttons.matching(NSPredicate(format: "label == %@", "Plus one")).firstMatch.tap()
        XCTAssertTrue(poll(5) { app.model.entry(self.sbr)?.progress == before + 1 })
    }

    func testNewListSheetOpens() {
        let app = launch(["-tab", "library", "-sheet", "new-list"])
        expect(app, "New list")
        XCTAssertEqual(app.model.sheet, .newList)
    }

    private func rows() -> App {
        UserDefaults.standard.removeObject(forKey: "library.view.anime")
        UserDefaults.standard.removeObject(forKey: "library.sort.anime")
        return launch(["-tab", "library", "-open", "list/anime"])
    }
}
