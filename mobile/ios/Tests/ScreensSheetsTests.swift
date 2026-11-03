import XCTest
@testable import GupTrack

/// The sheets over a title page: list editor (18, 19), add to a list (26), write a review (27), send to (53).
final class ScreensSheetsTests: ScreenTestCase {
    private let sbr = "anime:210482"
    private let csm = "manga:105778"

    private func editor(expanded: Bool) -> App {
        launch(["-open", "title/" + sbr, "-sheet", "editor/\(sbr)/\(expanded)"])
    }

    private func requests(_ app: App) -> [String] {
        ((app.model.api.transport as? DemoTransport)?.requests ?? []).map { "\($0.method) \($0.path)" }
    }

    func test18EditorSheet() {
        let app = editor(expanded: false)
        expect(app, "Status")
        expect(app, "Watching")
        expect(app, "Plan to Watch")
        let e = app.model.entry(sbr)
        expect(app, "Episode \(e?.progress ?? 0) of 11")
        expect(app, "Your score")
        expect(app, "Favourite")
        find(app, "Score 7").tap()
        expect(app, "/ 10")
        shot("18-editor-sheet")
    }

    func test19EditorSheetFull() {
        let app = editor(expanded: true)
        expect(app, "Rewatches")
        expect(app, "10 point")
        expect(app, "Started")
        expect(app, "Finished")
        expect(app, "Note")
        expect(app, "Write a review")
        expect(app, "Remove from list")
        shot("19-editor-sheet-full")
    }

    func testEditorSaveChangesTheEntry() {
        let app = editor(expanded: false)
        expect(app, "Your score")
        let before = app.model.entry(sbr)
        find(app, "One more episode").tap()
        find(app, "Score 7").tap()
        XCTAssertEqual(app.model.entry(sbr), before, "nothing changes before ✓")
        app.buttons["Save"].tap()
        XCTAssertNil(app.model.sheet)
        XCTAssertEqual(app.model.entry(sbr)?.progress, (before?.progress ?? 0) + 1)
        XCTAssertEqual(app.model.entry(sbr)?.score, 70)
    }

    func testEditorCancelDropsTheDraft() {
        let app = editor(expanded: false)
        expect(app, "Your score")
        let before = app.model.entry(sbr)
        find(app, "One more episode").tap()
        find(app, "Completed").tap()
        app.buttons["Cancel"].tap()
        XCTAssertNil(app.model.sheet)
        XCTAssertEqual(app.model.entry(sbr), before)
    }

    func testEditorReviewRowOpensTheReviewSheet() {
        let app = editor(expanded: true)
        expect(app, "Write a review").tap()
        XCTAssertEqual(app.model.sheet, .writeReview(sbr))
    }

    func test26AddToListSheet() {
        let app = launch(["-open", "title/" + sbr, "-sheet", "add-to-list/" + sbr])
        expect(app, "New list")
        expect(app, "Rainy Sundays")
        expect(app, "titles · Public")
        expect(app, "Lists can mix")
        shot("26-add-to-list-sheet")
    }

    func testAddToListDoneSendsTheTicks() {
        let app = launch(["-open", "title/" + sbr, "-sheet", "add-to-list/" + sbr])
        expect(app, "Start here").tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(poll(5) { app.model.sheet == nil })
        XCTAssertTrue(requests(app).contains("POST lists/4/items"))
    }

    func testNewListOpensInTheSheet() {
        let app = launch(["-open", "title/" + sbr, "-sheet", "add-to-list/" + sbr])
        expect(app, "New list").tap()
        expect(app, "Description (optional)")
        XCTAssertEqual(app.model.sheet, .addToList(sbr), "pushed inside Add to list, with the title to put on it")
    }

    func test27WriteReview() {
        let app = launch(["-open", "title/" + csm, "-sheet", "write-review/" + csm])
        expect(app, "Chainsaw Man")
        expect(app, "Reading")
        expect(app, "Contains spoilers")
        find(app, "Review text").typeText(
            "Every chapter ends on a turn I didn't see coming, and the art never lets up. "
                + "The second part takes its time, but it earns it. Easy to recommend")
        expect(app, "/ 10,000")
        shot("27-write-review")
    }

    func testPostingAReview() {
        let app = launch(["-open", "title/" + csm, "-sheet", "write-review/" + csm])
        find(app, "Review text").typeText("Worth it.")
        app.buttons["Post"].tap()
        XCTAssertTrue(poll(5) { app.model.sheet == nil })
        XCTAssertTrue(requests(app).contains("PUT titles/manga/105778/review"))
    }

    func test53SendToSheet() {
        let app = launch(["-open", "title/" + sbr, "-sheet", "send-to/" + sbr])
        expect(app, "Friends")
        expect(app, "noor.reads")
        expect(app, "kenji").tap()
        expect(app, "lena").tap()
        find(app, "Add a message").typeText("first three episodes, trust me")
        expect(app, "Send 2")
        shot("53-send-to-sheet")
    }

    func testSendingPostsToEachFriend() {
        let app = launch(["-open", "title/" + sbr, "-sheet", "send-to/" + sbr])
        expect(app, "tobiwan").tap()
        app.buttons["Send 1"].tap()
        XCTAssertTrue(poll(5) { app.model.sheet == nil })
        XCTAssertTrue(requests(app).contains("POST conversations/tobiwan/messages"))
    }
}
