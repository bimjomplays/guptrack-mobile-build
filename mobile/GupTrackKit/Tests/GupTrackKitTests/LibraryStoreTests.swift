import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

final class LibraryStoreTests: XCTestCase {
    var store: LibraryStore!

    override func setUpWithError() throws {
        store = try LibraryStore()
    }

    func feed(_ changes: [FeedChange], cursor: String = "c1", more: Bool = false, reset: Bool = false) throws {
        try store.applyFeed(ChangePage(changes: changes, cursor: cursor, more: more, reset: reset))
    }

    func change(_ id: String, rev: Int, progress: Int? = nil, status: ListStatus = .current) -> FeedChange {
        var e = Make.entry(id, status)
        if let progress { e.progress = progress }
        return FeedChange(titleId: id, revision: rev, entry: e)
    }

    func testFeedFillsTheLibraryAndKeepsTheCursor() throws {
        try feed([change("anime:1", rev: 1), change("anime:2", rev: 1)], cursor: "c9", reset: true)
        XCTAssertEqual(try store.entries().count, 2)
        XCTAssertEqual(try store.cursor, "c9")
    }

    func testPendingEditsShowOnTopOfTheServerCopy() throws {
        try feed([change("anime:1", rev: 1, progress: 2)], reset: true)
        try store.change("anime:1", LibraryPatch(progress: 3), requestId: "r1")
        try store.change("anime:1", LibraryPatch(score: 80), requestId: "r2")
        let e = try XCTUnwrap(try store.entry("anime:1"))
        XCTAssertEqual(e.progress, 3)
        XCTAssertEqual(e.score, 80)
        XCTAssertEqual(try store.serverEntry("anime:1")?.progress, 2)
        XCTAssertEqual(try store.pending().map(\.requestId), ["r1", "r2"])
        XCTAssertEqual(try store.pendingCount, 2)
    }

    func testAddingANewTitleOfflineNeedsTheTitle() throws {
        try store.change("anime:9", LibraryPatch(status: .planned), title: Make.title("anime:9"), requestId: "r1")
        XCTAssertEqual(try store.entry("anime:9")?.status, .planned)
        // without the title there's nothing to show
        try store.change("anime:8", LibraryPatch(progress: 1), requestId: "r2")
        XCTAssertNil(try store.entry("anime:8"))
    }

    func testRemovingHidesItUntilTheServerAgrees() throws {
        try feed([change("anime:1", rev: 1)], reset: true)
        try store.change("anime:1", LibraryPatch(remove: true), requestId: "r1")
        XCTAssertNil(try store.entry("anime:1"))
        XCTAssertNotNil(try store.serverEntry("anime:1"))
        try store.acknowledge([ChangeResult(requestId: "r1", ok: true, revision: 2)])
        XCTAssertNil(try store.serverEntry("anime:1"))
        XCTAssertEqual(try store.pendingCount, 0)
    }

    func testAcknowledgeWritesTheServersEntry() throws {
        try feed([change("anime:1", rev: 1, progress: 2)], reset: true)
        try store.change("anime:1", LibraryPatch(progress: 3), requestId: "r1")
        var server = Make.entry("anime:1")
        server.progress = 3
        server.notes = "from the server"
        try store.acknowledge([ChangeResult(requestId: "r1", ok: true, revision: 2, entry: server)])
        XCTAssertEqual(try store.serverEntry("anime:1")?.notes, "from the server")
        XCTAssertEqual(try store.pendingCount, 0)
    }

    func testAcknowledgeWithoutAnEntryFoldsTheEditIn() throws {
        try feed([change("anime:1", rev: 1, progress: 2)], reset: true)
        try store.change("anime:1", LibraryPatch(progress: 3), requestId: "r1")
        try store.change("anime:1", LibraryPatch(progress: 4), requestId: "r2")
        try store.acknowledge([ChangeResult(requestId: "r1", ok: true, revision: 2)])
        XCTAssertEqual(try store.serverEntry("anime:1")?.progress, 3)
        XCTAssertEqual(try store.entry("anime:1")?.progress, 4)   // r2 still pending on top
    }

    func testRejectedEditsAreDroppedAndReported() throws {
        try feed([change("anime:1", rev: 1, progress: 2)], reset: true)
        try store.change("anime:1", LibraryPatch(progress: 3), requestId: "r1")
        let rejected = try store.acknowledge([ChangeResult(requestId: "r1", ok: false, error: "Not on your list.")])
        XCTAssertEqual(rejected.map(\.requestId), ["r1"])
        XCTAssertEqual(rejected.first?.lastError, "Not on your list.")
        XCTAssertEqual(try store.entry("anime:1")?.progress, 2)
    }

    func testAnswersForUnknownRequestsAreIgnored() throws {
        XCTAssertEqual(try store.acknowledge([ChangeResult(requestId: "nope", ok: true)]), [])
    }

    func testRequestIdsAreUnique() throws {
        try store.change("anime:1", LibraryPatch(progress: 1), title: Make.title(), requestId: "r1")
        XCTAssertThrowsError(try store.change("anime:1", LibraryPatch(progress: 2), requestId: "r1"))
    }

    func testOlderFeedRevisionsDontUndoNewerOnes() throws {
        try feed([change("anime:1", rev: 5, progress: 5)], reset: true)
        try feed([change("anime:1", rev: 3, progress: 3)])
        XCTAssertEqual(try store.entry("anime:1")?.progress, 5)
        try feed([FeedChange(titleId: "anime:1", revision: 6, entry: nil)])
        XCTAssertNil(try store.entry("anime:1"))
    }

    func testResetOverSeveralPagesRemovesWhatItDidntInclude() throws {
        try feed([change("anime:1", rev: 1), change("anime:2", rev: 1), change("anime:3", rev: 1)], reset: true)
        try feed([change("anime:1", rev: 1)], cursor: "p1", more: true, reset: true)
        // mid-copy nothing is removed yet
        XCTAssertEqual(try store.entries().count, 3)
        try feed([change("anime:3", rev: 1)], cursor: "p2", more: false)
        XCTAssertEqual(Set(try store.entries().map(\.id)), ["anime:1", "anime:3"])
        XCTAssertEqual(try store.cursor, "p2")
    }

    func testPendingEditsSurviveAReset() throws {
        try feed([change("anime:1", rev: 1, progress: 1)], reset: true)
        try store.change("anime:1", LibraryPatch(progress: 2), requestId: "r1")
        try feed([change("anime:1", rev: 2, progress: 1)], reset: true)
        XCTAssertEqual(try store.entry("anime:1")?.progress, 2)
    }

    func testTheLibraryLastsOnDisk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gt-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let s = try LibraryStore(path: path)
            try s.applyFeed(ChangePage(changes: [change("anime:1", rev: 1)], cursor: "c", more: false, reset: true))
            try s.change("anime:1", LibraryPatch(progress: 4), requestId: "r1")
        }
        let again = try LibraryStore(path: path)
        XCTAssertEqual(try again.entry("anime:1")?.progress, 4)
        XCTAssertEqual(try again.pendingCount, 1)
        try again.wipe()
        XCTAssertEqual(try again.entries().count, 0)
        XCTAssertNil(try again.cursor)
    }

    func testFailuresAreCounted() throws {
        try store.change("anime:1", LibraryPatch(progress: 1), title: Make.title(), requestId: "r1")
        try store.noteFailure(["r1"], "offline")
        try store.noteFailure(["r1"], "still offline")
        let p = try XCTUnwrap(try store.pending().first)
        XCTAssertEqual(p.attempts, 2)
        XCTAssertEqual(p.lastError, "still offline")
    }
}

final class LibrarySyncTests: XCTestCase {
    func testSyncSendsThenPullsTheDemoLibrary() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "demo")
        let store = try LibraryStore()
        try store.change("anime:999", LibraryPatch(status: .planned), title: Make.title("anime:999"), requestId: "r1")
        let report = try await LibrarySync(api: api, store: store).run()
        XCTAssertEqual(report.sent, 1)
        XCTAssertGreaterThan(report.received, 50)
        XCTAssertEqual(try store.pendingCount, 0)
        XCTAssertEqual(try store.cursor, DemoTransport.cursor)
        // the demo's full copy didn't include the added title, and the reset removed it
        XCTAssertNil(try store.entry("anime:999"))
        XCTAssertEqual(transport.requests.map { "\($0.method) \($0.path)" }, ["POST library/changes", "GET library/changes"])
        // a second sync asks for changes since the cursor and gets none
        let again = try await LibrarySync(api: api, store: store).run()
        XCTAssertEqual(again.received, 0)
        XCTAssertEqual(transport.requests.last?.query.first?.value, DemoTransport.cursor)
    }

    func testOfflineKeepsTheEditsQueued() async throws {
        let api = APIClient(transport: DemoTransport(offline: true), token: "demo")
        let store = try LibraryStore()
        try store.change("anime:1", LibraryPatch(progress: 1), title: Make.title(), requestId: "r1")
        do {
            _ = try await LibrarySync(api: api, store: store).run()
            XCTFail("expected offline")
        } catch let e as APIError {
            XCTAssertTrue(e.isUnreachable)
        }
        XCTAssertEqual(try store.pending().first?.attempts, 1)
        XCTAssertEqual(try store.entry("anime:1")?.progress, 1)
    }

    func testBatches() async throws {
        let transport = DemoTransport()
        let store = try LibraryStore()
        for i in 0..<5 {
            try store.change("anime:\(i)", LibraryPatch(status: .planned), title: Make.title("anime:\(i)"), requestId: "r\(i)")
        }
        let report = try await LibrarySync(api: APIClient(transport: transport, token: "d"), store: store, batch: 2).run()
        XCTAssertEqual(report.sent, 5)
        XCTAssertEqual(transport.requests.filter { $0.method == "POST" }.count, 3)
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func demoModel(_ args: [String] = []) -> AppModel {
        Demo.args = ["app", "-demo"] + args
        return AppModel.make()
    }

    override func tearDown() {
        Demo.args = ["app"]
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func testDemoSignsInAndSyncs() async {
        let m = demoModel()
        XCTAssertTrue(m.isSignedIn)
        XCTAssertTrue(m.library.isEmpty)
        await m.refresh()
        XCTAssertGreaterThan(m.library.count, 50)
        XCTAssertEqual(m.sync, .idle)
        XCTAssertEqual(m.loading, 0)
        XCTAssertEqual(Clock.now, Clock.demoNow)
    }

    func testDemoFlagsOpenPagesAndSheets() {
        let m = demoModel(["-open", "list/anime", "-open", "title/anime:210482", "-sheet", "editor/anime:210482/true"])
        XCTAssertEqual(m.tab, .library)
        XCTAssertEqual(m.path(.library), [.list(.anime), .title("anime:210482")])
        XCTAssertEqual(m.sheet, .editor("anime:210482", expanded: true))
        let t = demoModel(["-tab", "social"])
        XCTAssertEqual(t.tab, .social)
        let out = demoModel(["-account", "sign-in"])
        XCTAssertFalse(out.isSignedIn)
        XCTAssertEqual(out.accountScreen, "sign-in")
    }

    func testChangesShowAtOnceAndSync() async throws {
        let m = demoModel()
        await m.refresh()
        let id = "anime:210482"
        let before = try XCTUnwrap(m.entry(id)).progress
        m.step(id)
        XCTAssertEqual(m.entry(id)?.progress, before + 1)
        await m.syncLibrary()
        XCTAssertEqual(m.pendingCount, 0)
    }

    func testOfflineDemo() async {
        let m = demoModel(["-offline"])
        await m.refresh()
        XCTAssertEqual(m.sync, .offline("This iPhone is offline."))
        let r: Load<ServerHello> = await m.fetch { try await $0.hello() }
        XCTAssertEqual(r.error, "This iPhone is offline.")
    }

    func testLinksOpenTheirTab() {
        let m = demoModel()
        m.tab = .profile
        XCTAssertTrue(m.handle(url: URL(string: "guptrack://title/anime:21")!))
        XCTAssertEqual(m.tab, .browse)
        XCTAssertEqual(m.path(.browse), [.title("anime:21")])
        XCTAssertFalse(m.handle(url: URL(string: "guptrack://nope")!))
    }

    func testSignOutForgetsEverything() async {
        let m = demoModel()
        await m.refresh()
        await m.signOut()
        XCTAssertFalse(m.isSignedIn)
        XCTAssertTrue(m.library.isEmpty)
        XCTAssertEqual(m.accountScreen, "welcome")
    }
}
