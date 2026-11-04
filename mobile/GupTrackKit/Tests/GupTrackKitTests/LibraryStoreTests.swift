import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

extension Make {
    /// a server entry as the change feed sends it ("anime:1" -> media anime, id "1")
    static func sync(_ titleId: String = "anime:1", rev: Int, status: EntryStatus = .current, progress: Int = 0,
                     total: Int? = 12, at: Int64 = 1_793_700_000_000) -> SyncEntry {
        let key = TitleKey(titleId: titleId)!
        let e = ListEntry(id: key.id, title: "Show \(key.id)", format: "TV", status: status, progress: progress,
                          total: total, added: at)
        return SyncEntry(media: key.media, entry: e, statusAt: at, progressAt: at, scoreAt: at, changedAt: at, rev: rev)
    }

    static func feed(_ entries: [SyncEntry], removed: [ChangeFeed.Removed] = [], lists: [FeedList] = [],
                     cursor: String = "e1.1", more: Bool = false) -> ChangeFeed {
        ChangeFeed(entries: entries, removed: removed, lists: .init(changed: lists, removed: []), cursor: cursor,
                   more: more, serverTime: 1_793_700_000_000)
    }

    /// request ids r1, r2, … in order
    static func ids() -> () -> String {
        var n = 0
        return { n += 1; return "r\(n)" }
    }
}

final class LibraryStoreTests: XCTestCase {
    var store: LibraryStore!

    override func setUpWithError() throws {
        store = try LibraryStore()
    }

    func feed(_ entries: [SyncEntry], removed: [ChangeFeed.Removed] = [], cursor: String = "e1.1",
              more: Bool = false) throws {
        try store.applyFeed(Make.feed(entries, removed: removed, cursor: cursor, more: more))
    }

    func testFeedFillsTheLibraryAndKeepsTheCursor() throws {
        try feed([Make.sync("anime:1", rev: 1), Make.sync("movies:2", rev: 2)], cursor: "e1.9")
        XCTAssertEqual(Set(try store.entries().map(\.id)), ["anime:1", "movie:2"])
        XCTAssertEqual(try store.entry("movie:2")?.media, .movie)
        XCTAssertEqual(try store.cursor, "e1.9")
    }

    func testOpsShowOnTopOfTheServerCopy() throws {
        try feed([Make.sync(rev: 1, progress: 2)])
        let next = Make.ids()
        try store.change("anime:1", LibraryPatch(progress: 3), newId: next)
        try store.change("anime:1", LibraryPatch(score: 80), newId: next)
        let e = try XCTUnwrap(try store.entry("anime:1"))
        XCTAssertEqual(e.progress, 3)
        XCTAssertEqual(e.score, 80)
        XCTAssertEqual(try store.serverEntry("anime:1")?.entry.progress, 2)
        XCTAssertEqual(try store.pending().map(\.requestId), ["r1", "r2"])
        XCTAssertEqual(try store.pending().map(\.op.op), [.progress, .score])
        XCTAssertEqual(try store.pendingCount, 2)
    }

    func testAnEditSheetChangeIsOneEditOp() throws {
        try feed([Make.sync(rev: 1, progress: 2)])
        try store.change("anime:1", LibraryPatch(progress: 4, started: "2026-10-02", notes: "so good"), newId: Make.ids())
        let op = try XCTUnwrap(try store.pending().first?.op)
        XCTAssertEqual(op.op, .edit)
        XCTAssertEqual(op.entry?["progress"], .number(4))
        XCTAssertEqual(op.entry?["notes"], .string("so good"))
        XCTAssertEqual(op.entry?["started"], .string("2026-10-02"))
        XCTAssertEqual(try store.entry("anime:1")?.notes, "so good")
    }

    func testAddingANewTitleSendsItsMeta() throws {
        let next = Make.ids()
        try store.change("anime:9", LibraryPatch(status: .planned), title: Make.title("anime:9"), newId: next)
        XCTAssertEqual(try store.entry("anime:9")?.status, .planned)
        let op = try XCTUnwrap(try store.pending().first?.op)
        XCTAssertEqual(op.op, .status)
        XCTAssertEqual(op.media, .anime)
        XCTAssertEqual(op.id, "9")
        XCTAssertEqual(op.meta?.title, "Show")
        XCTAssertEqual(op.meta?.total, 12)
        // a score for a title that isn't on the list shows nothing (the server answers not_on_list)
        try store.change("anime:8", LibraryPatch(score: 70), newId: next)
        XCTAssertNil(try store.entry("anime:8"))
    }

    func testRewatchStartsFromCompleted() throws {
        try feed([Make.sync(rev: 1, status: .completed, progress: 12)])
        try store.change("anime:1", LibraryPatch(status: .repeating, progress: 0), newId: Make.ids())
        let op = try XCTUnwrap(try store.pending().first?.op)
        XCTAssertEqual(op.op, .rewatch)
        let e = try XCTUnwrap(try store.entry("anime:1"))
        XCTAssertEqual(e.status, .repeating)
        XCTAssertEqual(e.progress, 0)
        XCTAssertEqual(try store.listEntry("anime:1")?.rewatch?.progress, 12)
    }

    func testFinishingTheCountCompletesIt() throws {
        try feed([Make.sync(rev: 1, progress: 11)])
        try store.change("anime:1", LibraryPatch(progress: 12), newId: Make.ids())
        XCTAssertEqual(try store.entry("anime:1")?.status, .completed)
        XCTAssertNotNil(try store.entry("anime:1")?.finished)
    }

    func testRemovingHidesItUntilTheServerAgrees() throws {
        try feed([Make.sync(rev: 1)])
        try store.change("anime:1", LibraryPatch(remove: true), newId: Make.ids())
        XCTAssertNil(try store.entry("anime:1"))
        XCTAssertNotNil(try store.serverEntry("anime:1"))
        try store.acknowledge([WriteResult(requestId: "r1", applied: true, media: .anime, id: "1", entry: nil, removed: true)])
        XCTAssertNil(try store.serverEntry("anime:1"))
        XCTAssertEqual(try store.pendingCount, 0)
    }

    func testAcknowledgeWritesTheServersEntry() throws {
        try feed([Make.sync(rev: 1, progress: 2)])
        try store.change("anime:1", LibraryPatch(progress: 3), newId: Make.ids())
        var server = Make.sync(rev: 2, progress: 3)
        server.entry.notes = "from the server"
        let a = try store.acknowledge([WriteResult(requestId: "r1", applied: true, media: .anime, id: "1", entry: server)])
        XCTAssertEqual(a.settled.map(\.requestId), ["r1"])
        XCTAssertEqual(try store.serverEntry("anime:1")?.entry.notes, "from the server")
        XCTAssertEqual(try store.pendingCount, 0)
    }

    func testStaleShowsTheServersEntry() throws {
        try feed([Make.sync(rev: 1, progress: 2)])
        try store.change("anime:1", LibraryPatch(progress: 3), newId: Make.ids())
        let a = try store.acknowledge([WriteResult(requestId: "r1", applied: false, reason: "stale", media: .anime,
                                                   id: "1", entry: Make.sync(rev: 5, progress: 7))])
        XCTAssertEqual(a.settled.count, 1)
        XCTAssertTrue(a.refused.isEmpty)
        XCTAssertEqual(try store.entry("anime:1")?.progress, 7)
    }

    func testRefusedOpsAreReported() throws {
        try feed([Make.sync(rev: 1, progress: 2)])
        try store.change("anime:1", LibraryPatch(status: .repeating), newId: Make.ids())
        let a = try store.acknowledge([WriteResult(requestId: "r1", applied: false, reason: "not_completed", media: .anime,
                                                   id: "1", entry: Make.sync(rev: 1, progress: 2))])
        XCTAssertEqual(a.refused.map(\.1), ["not_completed"])
        XCTAssertEqual(try store.pendingCount, 0)
    }

    func testWrongOpsAreDroppedWithTheirMessage() throws {
        try feed([Make.sync(rev: 1, progress: 2)])
        try store.change("anime:1", LibraryPatch(progress: 3), newId: Make.ids())
        let a = try store.acknowledge([WriteResult(requestId: "r1", applied: false, error: "bad_request", message: "Bad status")])
        XCTAssertEqual(a.rejected.map(\.requestId), ["r1"])
        XCTAssertEqual(a.rejected.first?.lastError, "Bad status")
        XCTAssertEqual(a.rejected.first?.name, "Show 1")
        XCTAssertEqual(try store.entry("anime:1")?.progress, 2)
    }

    func testAnswersForUnknownRequestsAreIgnored() throws {
        XCTAssertEqual(try store.acknowledge([WriteResult(requestId: "nope", applied: true)]), LibraryStore.Answered())
    }

    func testRequestIdsAreUnique() throws {
        try store.change("anime:1", LibraryPatch(progress: 1), title: Make.title(), newId: { "r1" })
        XCTAssertThrowsError(try store.change("anime:1", LibraryPatch(progress: 2), newId: { "r1" }))
    }

    func testOlderRevisionsDontUndoNewerOnes() throws {
        try feed([Make.sync(rev: 5, progress: 5)])
        try feed([Make.sync(rev: 3, progress: 3)])
        XCTAssertEqual(try store.entry("anime:1")?.progress, 5)
        try feed([], removed: [ChangeFeed.Removed(media: .anime, id: "1", removedAt: 1)])
        XCTAssertNil(try store.entry("anime:1"))
    }

    func testListsAreReplacedWhole() throws {
        let level = ListLevel(list: .public, profile: .public)
        func list(_ name: String, rev: Int) -> FeedList {
            FeedList(list: MyList(id: 4, slug: "s", name: name, description: "", count: 0, covers: [], media: [],
                                  updated: 1, level: level, items: []), position: 0, rev: rev)
        }
        try store.applyFeed(Make.feed([], lists: [list("One", rev: 2)]))
        try store.applyFeed(Make.feed([], lists: [list("Old", rev: 1)]))
        XCTAssertEqual(try store.lists().map(\.list.name), ["One"])
        var gone = Make.feed([])
        gone.lists.removed = [.init(id: 4, removedAt: 9)]
        try store.applyFeed(gone)
        XCTAssertTrue(try store.lists().isEmpty)
    }

    func testOpsSurviveForgettingTheServerCopy() throws {
        try feed([Make.sync(rev: 1, progress: 1)], cursor: "e1.1")
        try store.change("anime:1", LibraryPatch(progress: 2), newId: Make.ids())
        try store.forgetServerCopy()
        XCTAssertNil(try store.cursor)
        XCTAssertNil(try store.serverEntry("anime:1"))
        XCTAssertEqual(try store.pendingCount, 1)
        try feed([Make.sync(rev: 1, progress: 1)], cursor: "e2.1")
        XCTAssertEqual(try store.entry("anime:1")?.progress, 2)
    }

    func testTheLibraryLastsOnDisk() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gt-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let s = try LibraryStore(path: path)
            try s.applyFeed(Make.feed([Make.sync(rev: 1)], cursor: "e1.1"))
            try s.change("anime:1", LibraryPatch(progress: 4), newId: Make.ids())
        }
        let again = try LibraryStore(path: path)
        XCTAssertEqual(try again.entry("anime:1")?.progress, 4)
        XCTAssertEqual(try again.pendingCount, 1)
        XCTAssertEqual(try again.cursor, "e1.1")
        try again.wipe()
        XCTAssertEqual(try again.entries().count, 0)
        XCTAssertNil(try again.cursor)
    }

    func testFailuresAreCounted() throws {
        try store.change("anime:1", LibraryPatch(progress: 1), title: Make.title(), newId: Make.ids())
        try store.noteFailure(["r1"], "offline")
        try store.noteFailure(["r1"], "still offline")
        let p = try XCTUnwrap(try store.pending().first)
        XCTAssertEqual(p.attempts, 2)
        XCTAssertEqual(p.lastError, "still offline")
    }
}

final class LibrarySyncTests: XCTestCase {
    func testSyncSendsThenReadsTheDemoLibrary() async throws {
        let transport = DemoTransport()
        let api = APIClient(transport: transport, token: "demo")
        let store = try LibraryStore()
        try store.change("anime:999", LibraryPatch(status: .planned), title: Make.title("anime:999"), newId: Make.ids())
        let report = try await LibrarySync(api: api, store: store).run()
        XCTAssertEqual(report.sent, 1)
        XCTAssertGreaterThan(report.received, 50)
        XCTAssertEqual(try store.pendingCount, 0)
        XCTAssertEqual(try store.cursor, transport.library.cursor)
        // the added title came back in the write's result and in the feed
        XCTAssertEqual(try store.serverEntry("anime:999")?.entry.status, .planned)
        XCTAssertEqual(transport.requests.map { "\($0.method) \($0.path)" }, ["POST library/write", "GET library/changes"])
        XCTAssertNil(transport.requests[0].requestId, "library writes carry their ids in the body")
        // a second sync asks for changes since the cursor and gets none
        let again = try await LibrarySync(api: api, store: store).run()
        XCTAssertEqual(again.received, 0)
        XCTAssertEqual(transport.requests.last?.query.first { $0.name == "since" }?.value, transport.library.cursor)
    }

    func testAnExpiredCursorReadsFromTheStart() async throws {
        let transport = DemoTransport()
        let store = try LibraryStore()
        try store.applyFeed(Make.feed([Make.sync("anime:424242", rev: 1)], cursor: "gone.5"))
        try store.change("anime:424242", LibraryPatch(score: 50), newId: Make.ids())
        let api = APIClient(transport: transport, token: "demo")
        // the write goes first and is answered not_on_list (the demo server never had it)
        let report = try await LibrarySync(api: api, store: store).run()
        XCTAssertTrue(report.restarted)
        XCTAssertNil(try store.serverEntry("anime:424242"))
        XCTAssertGreaterThan(try store.entries().count, 50)
        XCTAssertEqual(try store.cursor, transport.library.cursor)
    }

    func testOfflineKeepsTheOpsQueued() async throws {
        let api = APIClient(transport: DemoTransport(offline: true), token: "demo")
        let store = try LibraryStore()
        try store.change("anime:1", LibraryPatch(progress: 1), title: Make.title(), newId: Make.ids())
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
            try store.change("anime:\(900 + i)", LibraryPatch(status: .planned), title: Make.title("anime:\(900 + i)"),
                             newId: { "r\(i)" })
        }
        let report = try await LibrarySync(api: APIClient(transport: transport, token: "d"), store: store, batch: 2).run()
        XCTAssertEqual(report.sent, 5)
        XCTAssertEqual(transport.requests.filter { $0.method == "POST" }.count, 3)
    }

    func testTheServerSendingTheSameAnswerAgainIsHarmless() async throws {
        let store = try LibraryStore()
        try store.applyFeed(Make.feed([Make.sync(rev: 1, progress: 2)]))
        try store.change("anime:1", LibraryPatch(progress: 3), newId: Make.ids())
        let result = WriteResult(requestId: "r1", applied: true, media: .anime, id: "1", entry: Make.sync(rev: 2, progress: 3))
        try store.acknowledge([result])
        // a replayed answer for an op that already left the outbox changes nothing
        XCTAssertEqual(try store.acknowledge([result]), LibraryStore.Answered())
        XCTAssertEqual(try store.entry("anime:1")?.progress, 3)
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
        XCTAssertEqual(m.account?.user.name, "Mika")
        XCTAssertEqual(m.account?.role, "owner")
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
        XCTAssertEqual(m.entry(id)?.progress, before + 1)
    }

    func testOfflineDemo() async {
        let m = demoModel(["-offline"])
        await m.refresh()
        XCTAssertEqual(m.sync, .offline("This iPhone is offline."))
        let r: Load<ServerInfo> = await m.fetch { try await $0.server() }
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
        XCTAssertNotNil(Pictures.signedIn)
        await m.signOut()
        XCTAssertFalse(m.isSignedIn)
        XCTAssertTrue(m.library.isEmpty)
        XCTAssertNil(Pictures.signedIn)
        XCTAssertEqual(m.accountScreen, "welcome")
    }
}
