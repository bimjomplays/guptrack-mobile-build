import XCTest
@testable import GupTrack

/// Profiles (41, 42, 43, 43b, 48, 49): your profile, Statistics, someone else's profile, Compare.
final class ScreensProfileTests: ScreenTestCase {
    func testProfile() {
        let app = launch(["-tab", "profile"])
        expect(app, "Mika")
        expect(app, "6 friends")
        expect(app, "Seasonal anime")
        expect(app, "Statistics")
        expect(app, "Entries")
        expect(app, "Last updates")
        XCTAssertTrue(app.buttons["Settings"].exists)
        shot("41-profile")
    }

    func testProfileScrolled() {
        let app = launch(["-tab", "profile"])
        expect(app, "Statistics")
        scroll(app, until: "Lists", top: 120)
        expect(app, "Favourites")
        expect(app, "Reviews")
        expect(app, "Quiet in the best way")
        shot("42-profile-scrolled")
    }

    func testStats() {
        let app = launch(["-open", "stats"])
        expect(app, "Mean score")
        expect(app, "Median")
        expect(app, "Scores")
        expect(app, "Formats")
        expect(app, "Release years")
        shot("43-stats")
    }

    func testStatsScrolled() {
        let app = launch(["-open", "stats"])
        expect(app, "Mean score")
        scroll(app, until: "Genres", top: 120)
        expect(app, "Studios")
        shot("43b-stats-scrolled")
    }

    func testUserProfile() {
        let app = launch(["-open", "user/kenji"])
        expect(app, "kenji")
        expect(app, "Friends since")
        expect(app, "Message")
        expect(app, "Compare")
        expect(app, "in common with you")
        expect(app, "Last updates")
        shot("48-user-profile")
    }

    func testCompare() {
        let app = launch(["-open", "compare/kenji"])
        expect(app, "You and kenji")
        expect(app, "In common")
        expect(app, "Scored by both")
        expect(app, "Apart on average")
        expect(app, "Most different")
        shot("49-compare")
    }

    func testNoEditProfileButton() {
        let app = launch(["-tab", "profile"])
        expect(app, "Statistics")
        XCTAssertFalse(find(app, "Edit profile").exists)
    }

    func testGearOpensSettings() {
        let app = launch(["-tab", "profile"])
        expect(app, "Statistics")
        app.buttons["Settings"].tap()
        XCTAssertEqual(app.model.path(.profile).last, .settings)
    }

    func testFriendsLinkOpensFriends() {
        let app = launch(["-tab", "profile"])
        expect(app, "6 friends").tap()
        XCTAssertEqual(app.model.path(.profile).last, .friends)
    }

    func testSeeAllOpensStats() {
        let app = launch(["-tab", "profile"])
        expect(app, "Statistics")
        app.buttons["See all statistics"].tap()
        XCTAssertEqual(app.model.path(.profile).last, .stats)
    }

    func testMessageOpensConversation() {
        let app = launch(["-open", "user/kenji"])
        expect(app, "in common with you")
        app.buttons["Message"].tap()
        XCTAssertEqual(app.model.path(app.model.tab).last, .conversation("kenji"))
    }

    func testCompareButtonOpensCompare() {
        let app = launch(["-open", "user/kenji"])
        expect(app, "in common with you")
        app.buttons["Compare"].tap()
        XCTAssertEqual(app.model.path(app.model.tab).last, .compare("kenji"))
    }
}
