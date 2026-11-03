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
        XCTAssertTrue(poll(5) { app.model.unreadMessages == 2 }, "the Messages count is read at launch")
        shot("44-social")
    }

    func test45ActivityThread() {
        let app = launch(["-open", "activity/a1"])
        expect(app, "12 minutes ago")
        expect(app, "rated it")
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
        expect(app, "38 in common")
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
        expect(app, "198 titles")
        expect(app, "Add Friend")
        shot("47-add-friend")
    }

    func test50Reviews() {
        let app = launch(["-open", "reviews/anime:154587"])
        expect(app, "average of 52 reviews")
        expect(app, "Most liked")
        expect(app, "makima.fan")
        expect(app, "Read review")
        XCTAssertTrue(app.buttons["Write a review"].exists)
        shot("50-reviews")
    }

    func test51Messages() {
        let app = social()
        app.buttons["Messages"].tap()
        expect(app, "Message requests")
        expect(app, "aki.h wants to message you")
        expect(app, "Gyro spinning")
        expect(app, "You: Sent you Andor")
        XCTAssertTrue(app.buttons["New message"].exists)
        shot("51-messages")
    }

    func test52Conversation() {
        let app = launch(["-open", "conversation/kenji"])
        expect(app, "binged it last night")
        expect(app, "Anime · 11 eps")
        expect(app, "Read 12:03 AM")
        expect(app, "kenji is typing")
        expect(app, "Message kenji")
        shot("52-conversation")
    }

    func test54MessageRequest() {
        let app = launch(["-open", "message-request/aki.h"])
        expect(app, "Not a friend")
        expect(app, "View profile")
        expect(app, "Accept")
        expect(app, "Ignore")
        expect(app, "Report")
        shot("54-message-request")
    }

    // MARK: what they do

    func testFeedRowOpensThread() {
        let app = social()
        expect(app, "Vagabond").tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .activity("a2") })
    }

    func testLikeInFeed() {
        let app = social()
        expect(app, "Vagabond")
        app.buttons.matching(NSPredicate(format: "label == %@", "Like")).firstMatch.tap()
        XCTAssertTrue(poll(5) { self.requests(app).contains { $0.hasSuffix("/like") } })
    }

    func testAcceptMovesRequest() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "nami.watches")
        app.buttons["Accept nami.watches"].tap()
        expect(app, "New friend")
        XCTAssertTrue(poll(5) { self.requests(app).contains("POST friends/requests/nami.watches/accept") })
    }

    func testCompareOpens() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "38 in common")
        app.buttons["Compare with kenji"].tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .compare("kenji") })
    }

    func testSentAndBlocked() {
        let app = social()
        app.buttons["Friends"].tap()
        expect(app, "38 in common")
        app.buttons["Sent 1"].tap()
        expect(app, "ren_reads")
        app.buttons["Blocked"].tap()
        expect(app, "spoilerbot")
    }

    func testOpeningChatReadsIt() {
        let app = social()
        app.buttons["Messages"].tap()
        XCTAssertTrue(poll(5) { app.model.unreadMessages == 2 })
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
        let app = launch(["-open", "activity/a1"])
        expect(app, "2 replies")
        app.textFields["Reply to kenji"].typeText("same here")
        app.buttons["Send"].tap()
        expect(app, "3 replies")
    }

    func testReadReviewOpens() {
        let app = launch(["-open", "reviews/anime:154587"])
        expect(app, "makima.fan")
        app.buttons["Read makima.fan’s review"].tap()
        XCTAssertTrue(poll(5) { app.model.path(.browse).last == .review("frieren-makima") })
        expect(app, "Liked by")
    }

    func testAcceptOpensChat() {
        let app = launch(["-open", "message-request/aki.h"])
        expect(app, "Not a friend")
        app.buttons["Accept"].tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .conversation("aki.h") })
    }

    func testNewMessageOpensChat() {
        let app = launch(["-tab", "social", "-sheet", "new-message"])
        expect(app, "New Message")
        expect(app, "Reading Vagabond").tap()
        XCTAssertTrue(poll(5) { app.model.path(.social).last == .conversation("noor.reads") })
        XCTAssertNil(app.model.sheet)
    }
}
