import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The demo's answers, with scripted live streams: each GET messages/events gets the next script.
final class ScriptedStreams: Transport, @unchecked Sendable {
    enum Script { case lines([String]), open([String]), fail(APIError), hold }

    let demo = DemoTransport()
    private let lock = NSLock()
    private var scripts: [Script]
    private(set) var opened = 0

    init(_ scripts: [Script]) { self.scripts = scripts }

    func send(_ request: APIRequest) async throws -> APIResponse { try await demo.send(request) }

    func lines(_ request: APIRequest) -> AsyncThrowingStream<String, Error> {
        let next: Script = lock.withLock {
            opened += 1
            return scripts.isEmpty ? .hold : scripts.removeFirst()
        }
        return AsyncThrowingStream { cont in
            switch next {
            case .lines(let l):
                for line in l { cont.yield(line) }
                cont.finish()
            case .open(let l):
                for line in l { cont.yield(line) }   // and stays open
            case .fail(let e): cont.finish(throwing: e)
            case .hold: break   // open and quiet until cancelled
            }
        }
    }
}

@MainActor
final class LiveTests: XCTestCase {
    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func model(_ t: ScriptedStreams) -> AppModel {
        let tokens = MemoryTokenStore(Demo.account())
        // swiftlint:disable:next force_try
        return AppModel(api: APIClient(transport: t, token: tokens.load()?.token), store: try! LibraryStore(),
                        tokens: tokens, demo: false)
    }

    func until(_ what: @escaping @MainActor () -> Bool) async {
        for _ in 0..<400 where !what() { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testEventsMoveTheNewsAndTyping() {
        let live = LiveMessages()
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(live.apply(.typing("fran"), now: now))
        XCTAssertTrue(live.isTyping("fran", now: now.addingTimeInterval(5)))
        XCTAssertFalse(live.isTyping("fran", now: now.addingTimeInterval(7)))
        XCTAssertTrue(live.apply(.message("fran"), now: now))
        XCTAssertFalse(live.isTyping("fran", now: now))
        XCTAssertEqual(live.version("fran"), 1)
        XCTAssertFalse(live.apply(.read("fran")))
        XCTAssertEqual(live.version("fran"), 2)
        XCTAssertTrue(live.apply(.change(nil)))
        XCTAssertEqual(live.anyNews, 2)
        XCTAssertEqual(live.version("ola"), 0)
    }

    func testStreamFeedsTheScreensAndReconnects() async {
        let t = ScriptedStreams([
            .lines(["retry: 10", ": hello", "", #"data: {"t":"typing","with":"fran"}"#, "",
                    #"data: {"t":"message","with":"fran"}"#, ""]),
            .fail(.server(429, "rate_limited", "Too many live streams.")),
        ])
        let m = model(t)
        m.unreadMessages = 99
        let run = Task { await m.streamMessages(backoff: .milliseconds(5)) }
        // the first stream ends after its two events; the second is turned away (429); the third stays open
        await until { t.opened >= 3 && m.live.connected == false }
        XCTAssertEqual(m.live.version("fran"), 1)
        XCTAssertFalse(m.live.isTyping("fran"))
        // the badge came from the message list after the news
        XCTAssertNotEqual(m.unreadMessages, 99)
        run.cancel()
        await run.value
        XCTAssertTrue(m.isSignedIn)
        XCTAssertFalse(m.live.connected)
    }

    func testOpenStreamCountsAsConnected() async {
        let t = ScriptedStreams([.open(["retry: 5000", ": hello"])])
        let m = model(t)
        let run = Task { await m.streamMessages(backoff: .milliseconds(5)) }
        await until { m.live.connected }
        XCTAssertTrue(m.live.connected)
        run.cancel()
        await run.value
        XCTAssertFalse(m.live.connected)
        XCTAssertEqual(t.opened, 1)
    }

    func testNewsKeepsMessagesStillSending() async throws {
        let api = APIClient(transport: DemoTransport(), token: Demo.account().token)
        let first = try await api.messageList().lines.first!.person.username
        let server = try await api.conversation(first)
        let newest = server.messages.map(\.id).max() ?? 0
        func mine(_ id: Int, _ body: String, at: Int64) -> Message {
            Message(id: id, mine: true, body: body, card: nil, photos: [], at: at, edited: nil, deleted: false,
                    reactions: [])
        }
        let at = Int64(Clock.now.timeIntervalSince1970 * 1000)
        // two of yours on screen; the server has the first already, under its own id
        let shown = server.sending(mine(newest + 1_000_000, "one", at: at)).sending(mine(newest + 2_000_000, "two", at: at))
        var stored = server
        stored.messages.append(mine(newest + 1, "one", at: at + 40))
        let now = shown.refreshed(stored)
        XCTAssertEqual(now.messages.suffix(2).map(\.body), ["one", "two"])
        XCTAssertEqual(now.messages.suffix(2).map(\.id), [newest + 1, newest + 2_000_000])
        // once both are stored, nothing is doubled
        stored.messages.append(mine(newest + 2, "two", at: at + 80))
        XCTAssertEqual(now.refreshed(stored).messages.filter { $0.body == "two" }.count, 1)
        XCTAssertEqual(server.refreshed(stored), stored)
    }

    func testRemovedTokenSignsThePhoneOut() async {
        let t = ScriptedStreams([.fail(.signedOut)])
        let m = model(t)
        await m.streamMessages(backoff: .milliseconds(5))
        XCTAssertFalse(m.isSignedIn)
        XCTAssertEqual(m.notice, APIError.signedOut.message)
        XCTAssertEqual(t.opened, 1)
    }

    func testDemoHasNoStream() async {
        Demo.args = ["app", "-demo"]
        defer { Demo.args = ["app"] }
        let m = AppModel.make()
        await m.stayLive()
        XCTAssertFalse(m.live.connected)
    }

    func testOwnPicturesAreAskedAgainAndDroppedWhenGone() {
        let url = URL(string: "https://guptrack.example/api/app/v1/files/media/ab12.webp")!
        let r = PictureFetch.request(url, authorization: "Bearer x", cached: true)
        XCTAssertEqual(r.value(forHTTPHeaderField: "If-None-Match"), "\"ab12.webp\"")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer x")
        XCTAssertNil(PictureFetch.request(url, authorization: "Bearer x", cached: false)
            .value(forHTTPHeaderField: "If-None-Match"))
        let cover = PictureFetch.request(URL(string: "https://img.example/c.jpg")!, authorization: nil, cached: true)
        XCTAssertNil(cover.value(forHTTPHeaderField: "If-None-Match"))
        XCTAssertNil(cover.value(forHTTPHeaderField: "Authorization"))

        let bytes = Data([1, 2])
        XCTAssertEqual(PictureFetch.outcome(status: 200, data: bytes, cached: true), .fresh(bytes))
        XCTAssertEqual(PictureFetch.outcome(status: 304, data: nil, cached: true), .keep)
        XCTAssertEqual(PictureFetch.outcome(status: 404, data: nil, cached: true), .drop)
        XCTAssertEqual(PictureFetch.outcome(status: nil, data: nil, cached: true), .keep)
        XCTAssertEqual(PictureFetch.outcome(status: nil, data: nil, cached: false), .drop)
        XCTAssertEqual(PictureFetch.outcome(status: 500, data: nil, cached: true), .keep)
        XCTAssertTrue(PictureFetch.revalidates(authorization: "Bearer x"))
        XCTAssertFalse(PictureFetch.revalidates(authorization: nil))
    }
}
