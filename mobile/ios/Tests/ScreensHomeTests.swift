import XCTest
@testable import GupTrack

/// Home (05, 06, 07).
final class ScreensHomeTests: ScreenTestCase {
    func test05Home() {
        let app = launch()
        expect(app, "Continue")
        expect(app, "STEEL BALL RUN")
        expect(app, "in progress")
        expect(app, "Upcoming")
        XCTAssertTrue(app.buttons["Calendar"].exists)
        XCTAssertTrue(app.buttons["Notifications"].exists)
        shot("05-home")
    }

    func test06HomeScrolled() {
        let app = launch()
        expect(app, "Continue")
        scroll(app, until: "Stalled", top: 120)
        expect(app, "Ep 52 of 220")
        expect(app, "Start something")
        expect(app, "Trending anime")
        shot("06-home-scrolled")
    }

    func test07HomeContextMenu() {
        let app = launch()
        let row = expect(app, "STEEL BALL RUN")
        row.press(forDuration: 1.0)
        expect(app, "Watched episode 7")
        expect(app, "Open in Harbor")
        expect(app, "Send to a friend")
        shot("07-home-context-menu")
    }

    func testTapAContinueRowOpensItsTitle() {
        let app = launch()
        expect(app, "STEEL BALL RUN").tap()
        XCTAssertEqual(app.model.path(.home).last, .title("anime:210482"))
    }

    func testPlusStepsProgress() {
        let app = launch()
        expect(app, "STEEL BALL RUN")
        let before = app.model.entry("anime:210482")?.progress
        app.buttons.matching(NSPredicate(format: "label == %@", "One more")).firstMatch.tap()
        XCTAssertEqual(app.model.entry("anime:210482")?.progress, (before ?? 0) + 1)
    }
}
