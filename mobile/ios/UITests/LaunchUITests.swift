import XCTest

/// The one real XCUITest: the app launches on demo data into the five tabs and a tab switch works. Screens and their
/// pictures are in-process screen tests (Tests/Screens*Tests.swift); UI tests are only for what the system must
/// deliver itself.
// ci-covers: GupTrackApp.swift RootView.swift
final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testLaunchShowsTheTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 20))
        for name in ["Home", "Browse", "Library", "Social", "Profile"] {
            XCTAssertTrue(bar.buttons[name].exists, name)
        }
        bar.buttons["Library"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 10))
    }
}
