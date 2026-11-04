import XCTest
@testable import GupTrack

/// Home's extras: notifications (08) and the calendar (09, 10).
final class ScreensHomeExtrasTests: ScreenTestCase {
    func test08Notifications() {
        let app = launch(["-open", "notifications"])
        expect(app, "Today")
        expect(app, "wants to be friends")
        expect(app, "sent you a message")
        expect(app, "commented on your profile")
        expect(app, "liked your review of")
        expect(app, "This week")
        expect(app, "is out")
        XCTAssertTrue(app.buttons["Accept"].exists)
        XCTAssertTrue(app.buttons["Decline"].exists)
        XCTAssertTrue(app.buttons["Mark all read"].exists)
        shot("08-notifications")
    }

    func test09CalendarWeek() {
        let app = launch(["-open", "calendar"])
        expect(app, "Nov 1 – 7, 2026")
        expect(app, "Sun, Nov 1")
        expect(app, "Nothing airing")
        expect(app, "Tue, Nov 3")
        expect(app, "Nia Liston")
        expect(app, "Now, 9:41 AM")
        expect(app, "Wed, Nov 4")
        XCTAssertTrue(app.buttons["Today"].exists)
        XCTAssertTrue(app.buttons["Next week"].exists)
        shot("09-calendar-week")
    }

    func test10CalendarMonth() {
        let app = launch(["-open", "calendar"])
        expect(app, "Nov 1 – 7, 2026")
        app.buttons["Month"].tap()
        expect(app, "November 2026")
        app.buttons["November 6"].tap()
        expect(app, "Friday, Nov 6")
        expect(app, "STEEL BALL RUN")
        expect(app, "Plan to Watch")
        shot("10-calendar-month")
    }

    func testAcceptAnswersTheRequest() {
        let app = launch(["-open", "notifications"])
        app.buttons["Accept"].tap()
        expect(app, "You're now friends")
        XCTAssertFalse(app.buttons["Decline"].exists)
    }

    func testTapAMessageOpensTheConversation() {
        let app = launch(["-open", "notifications"])
        expect(app, "sent you a message").tap()
        XCTAssertEqual(app.model.path(.home).last, .conversation("kenji"))
    }

    func testTapAnEpisodeOpensTheTitle() {
        let app = launch(["-open", "notifications"])
        expect(app, "is out").tap()
        XCTAssertEqual(app.model.path(.home).last, .title("anime:210482"))
    }

    func testPastDaysUnfold() {
        let app = launch(["-open", "calendar"])
        expect(app, "Sun, Nov 1").tap()
        expect(app, "Overgeared")
    }

    func testNextWeekAndBackToToday() {
        let app = launch(["-open", "calendar"])
        expect(app, "Nov 1 – 7, 2026")
        app.buttons["Next week"].tap()
        expect(app, "Nov 8 – 14, 2026")
        app.buttons["Today"].tap()
        expect(app, "Nov 1 – 7, 2026")
    }

    func testTapAnAiringOpensTheTitle() {
        let app = launch(["-open", "calendar"])
        expect(app, "Nia Liston").tap()
        XCTAssertEqual(app.model.path(.home).last, .title("anime:206949"))
    }
}
