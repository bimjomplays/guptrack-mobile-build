import XCTest
@testable import GupTrack

/// Social (44-47, 50-52, 54): the tab's three parts, a thread, friends, find someone, reviews, a chat, a request.
final class ScreensSocialTests: ScreenTestCase {
    private func social() -> App {
        launch(["-tab", "social"])
    }

    private func requests(_ app: App) -> [String] {
        ((app.model.api.transport as? DemoTransport)?.requests ?? []).map { "\($0.method) \($0.path)" }
    }

    // MARK: the pictures

    func test44Social() {
        let app = social()
        expect(app, "completed Frieren")
        expect(app, "Vagabond")
        expect(app, "Dune: Part Two")
        XCTAssertTrue(app.buttons["Activity"].exists)
        XCTAssertTrue(app.buttons["Add friend"].exists)
        XCTAssertTrue(poll(5) { app.model.unreadMessages == 1 }, "the Messages count is read at launch")
        shot("44-social")
    }

    func test45ActivityThread() {
        let app = launch(["-open", "activity/119"])
        expect(app, "12 minutes ago")
        expect(app, "completed Frieren")
        expect(app, "Liked by")
        expect(app, "2 replies")
        expect(app, "Reply to kenji")
        shot("45-activity-thread")
    }

    func test46Friends() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "Requests")
        expect(app, "nami.watches")
        expect(app, "Friends since Oct 2026")
        XCTAssertTrue(app.buttons["Compare with kenji"].exists)
        XCTAssertTrue(app.buttons["Sent 1"].exists)
        shot("46-friends")
    }

    func test47AddFriend() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "Requests")
        app.buttons["Add friend"].tap()
        expect(app, "Find someone")
        app.textFields["Username"].typeText("kobeni")
        expect(app, "5 lists open to you")
        expect(app, "Add Friend")
        shot("47-add-friend")
    }

    func test50Reviews() {
        let app = launch(["-open", "reviews/anime:154587"])
        expect(app, "average of 6 reviews")
        expect(app, "Most liked")
        expect(app, "makima.fan")
        XCTAssertTrue(app.buttons["Read makima.fan’s review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Write a review"].exists)
        shot("50-reviews")
    }

    func test51Messages() {
        let app = social()
        app.buttons["Messages"].tap()
        expect(app, "Message requests")
        expect(app, "aki.h wants to message you")
        expect(app, "Gyro spinning")
        expect(app, "You: Shared Andor")
        XCTAssertTrue(app.buttons["New message"].exists)
        shot("51-messages")
    }

    func test52Conversation() {
        let app = launch(["-open", "conversation/kenji"])
        expect(app, "binged it last night")
        expect(app, "Anime · ONA · 2026")
        expect(app, "Read")
        expect(app, "kenji is typing")
        expect(app, "Message kenji")
        shot("52-conversation")
    }

    func test54MessageRequest() {
        let app = launch(["-open", "message-request/aki.h"])
        expect(app, "aki.h")
        expect(app, "going to see the Reze movie")
        expect(app, "View profile")
        expect(app, "Accept")
        expect(app, "Ignore")
        XCTAssertFalse(app.buttons["Report"].exists, "the contract has no report")
        shot("54-message-request")
    }

    // MARK: what they do

    func testFeedRowOpensThread() {
        let app = social()
        expect(app, "Vagabond").tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .activity("117") })
    }

    func testLikeInFeed() {
        let app = social()
        expect(app, "Vagabond")
        app.buttons.matching(NSPredicate(format: "label == %@", "Like")).firstMatch.tap()
        XCTAssertTrue(poll(5) { self.requests(app).contains { $0.hasPrefix("POST likes/activity/") } })
    }

    func testAcceptMovesRequest() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "nami.watches")
        app.buttons["Accept nami.watches"].tap()
        XCTAssertFalse(app.buttons["Accept nami.watches"].waitForExistence(timeout: 2))
        expect(app, "Friends since Nov")
        XCTAssertTrue(poll(5) { self.requests(app).contains("POST users/nami.watches/friend/answer") })
    }

    func testCompareOpens() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "Friends since Oct 2026")
        app.buttons["Compare with kenji"].tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .compare("kenji") })
    }

    func testSentAndBlocked() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "Friends since Oct 2026")
        app.buttons["Sent 1"].tap()
        expect(app, "ren_reads")
        app.buttons["Blocked"].tap()
        expect(app, "spoilerbot")
    }

    func testOpeningChatReadsIt() {
        let app = social()
        app.buttons["Messages"].tap()
        XCTAssertTrue(poll(5) { app.model.unreadMessages == 1 })
        expect(app, "Gyro spinning").tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .conversation("kenji") })
        XCTAssertTrue(poll(5) { app.model.unreadMessages == 0 })
    }

    func testSendMessage() {
        let app = launch(["-open", "conversation/kenji"])
        expect(app, "kenji is typing")
        app.textFields["Message kenji"].typeText("see you at the finale")
        app.buttons["Send"].tap()
        expect(app, "see you at the finale")
        XCTAssertTrue(poll(5) { self.requests(app).contains("POST conversations/kenji/messages") })
    }

    func testReplyToActivity() {
        let app = launch(["-open", "activity/119"])
        expect(app, "2 replies")
        app.textFields["Reply to kenji"].typeText("same here")
        app.buttons["Send"].tap()
        expect(app, "3 replies")
    }

    func testReadReviewOpens() {
        let app = launch(["-open", "reviews/anime:154587"])
        expect(app, "kenji")
        app.buttons["Read kenji’s review"].tap()
        XCTAssertTrue(poll(5) { app.model.path(.browse).last == .review("anime:154587@kenji") })
        expect(app, "Liked by")
    }

    func testAcceptOpensChat() {
        let app = launch(["-open", "message-request/aki.h"])
        expect(app, "going to see the Reze movie")
        app.buttons["Accept"].tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .conversation("aki.h") })
    }

    func testNewMessageOpensChat() {
        let app = launch(["-tab", "social", "-sheet", "new-message"])
        expect(app, "New Message")
        expect(app, "noor.reads").tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .conversation("noor.reads") })
        XCTAssertNil(app.model.sheet)
    }
}
