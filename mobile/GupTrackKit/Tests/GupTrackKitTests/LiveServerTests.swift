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

/// The app's own code against a real GupTrack server (bin/gt-app-e2e starts one on its own port with a throwaway
/// data folder, makes the owner and a friend, and passes the pairing link in the environment). Without it, skipped.
///
/// It goes the way a phone does: pair from the Connected apps link, read every screen's data, change progress while
/// unplugged and send it when back, read the change feed, hear a friend's message on the live stream, fetch an own
/// picture with the token (then 304), and sign out (the token stops working).
@MainActor
final class LiveServerTests: XCTestCase {
    /// the plug between the app and the server: pulled, every call fails as if the PC couldn't be reached
    final class Plug: Transport, @unchecked Sendable {
        let live: LiveTransport
        private let lock = NSLock()
        private var out = false
        init(_ base: URL) { live = LiveTransport(base: base) }

        var pulled: Bool {
            get { lock.withLock { out } }
            set { lock.withLock { out = newValue } }
        }

        func send(_ request: APIRequest) async throws -> APIResponse {
            if pulled { throw APIError.unreachable("Unplugged by the test.") }
            return try await live.send(request)
        }

        func lines(_ request: APIRequest) -> AsyncThrowingStream<String, Error> {
            if pulled { return AsyncThrowingStream { $0.finish(throwing: APIError.unreachable("Unplugged by the test.")) } }
            return live.lines(request)
        }
    }

    struct Setup {
        let link: String
        let friend: String
        let friendPassword: String
    }

    var setup: Setup {
        get throws {
            let env = ProcessInfo.processInfo.environment
            guard let link = env["GUPTRACK_LIVE_PAIR"], let friend = env["GUPTRACK_LIVE_FRIEND"],
                  let password = env["GUPTRACK_LIVE_FRIEND_PASSWORD"] else {
                throw XCTSkip("bin/gt-app-e2e runs this against a test server")
            }
            return Setup(link: link, friend: friend, friendPassword: password)
        }
    }

    override func tearDown() {
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func phone(_ folder: URL, plugs: Plugs) throws -> AppModel {
        let store = try LibraryStore(path: folder.appendingPathComponent("library-\(UUID().uuidString).sqlite").path)
        let m = AppModel(api: APIClient(transport: LiveTransport(base: URL(string: "https://unused.example")!)),
                         store: store, tokens: MemoryTokenStore(), demo: false)
        m.connect = { plugs.plug(for: $0) }
        return m
    }

    /// one plug per phone, made when it first reaches its server
    final class Plugs: @unchecked Sendable {
        private let lock = NSLock()
        private var made: Plug?
        func plug(for base: URL) -> Plug {
            lock.withLock {
                if let made, made.live.base == base { return made }
                let p = Plug(base)
                made = p
                return p
            }
        }
        var current: Plug? { lock.withLock { made } }
    }

    func until(_ seconds: Double = 10, _ what: @MainActor () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if what() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return what()
    }

    func expect(_ what: String, _ seconds: Double = 10, _ check: @MainActor () -> Bool) async {
        let ok = await until(seconds, check)
        XCTAssertTrue(ok, what)
    }

    func testThePhoneAgainstARealServer() async throws {
        let setup = try setup
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("guptrack-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        // pair: the link from Settings › Connected apps › Pair iPhone, as the pairing screen takes it
        guard case .success(let link) = PairLink.parse(setup.link) else { return XCTFail("not a pairing link: \(setup.link)") }
        let base = link.baseURL
        let hello = try await APIClient(transport: LiveTransport(base: base)).server()
        XCTAssertEqual(hello.app, "guptrack")
        XCTAssertFalse(hello.setupOpen)

        let plugs = Plugs()
        let model = try phone(folder, plugs: plugs)
        let flow = AccountFlowModel(model: model, start: nil, server: nil, device: "GupTrack test iPhone")
        let problem = await flow.pair(setup.link)
        XCTAssertNil(problem)
        let twice = await flow.pair(setup.link)
        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(model.account?.user.username, "owner")
        XCTAssertNotNil(model.lastSynced, "signing in reads the library")
        XCTAssertEqual(model.sync, .idle)
        XCTAssertFalse(model.library.isEmpty, "the owner's library came down")
        XCTAssertNotNil(twice, "a pairing code works once")

        // every screen's data, as the screens ask for it
        try await readEveryScreen(model.api, friend: setup.friend)

        // the change feed: nothing new since the sync
        let cursor = try XCTUnwrap(try model.store.cursor)
        let quiet = try await model.api.libraryChanges(since: cursor)
        XCTAssertTrue(quiet.entries.isEmpty)

        // offline: progress changes on the phone, waits in the outbox, and goes when the PC is back
        let plug = try XCTUnwrap(plugs.current)
        let entry = try XCTUnwrap(model.library.first { $0.media != .movie && $0.media != .book } ?? model.library.first)
        plug.pulled = true
        model.step(entry.id)
        await expect("the sync found the PC gone") {
            if case .offline = model.sync { return model.loading == 0 }
            return false
        }
        XCTAssertEqual(model.pendingCount, 1)
        guard case .offline = model.sync else { return XCTFail("offline, not \(model.sync)") }
        let stepped = try XCTUnwrap(model.entry(entry.id))
        XCTAssertEqual(stepped.progress, entry.progress + entry.media.step)
        plug.pulled = false
        await model.syncLibrary()
        XCTAssertEqual(model.pendingCount, 0)
        XCTAssertEqual(model.sync, .idle)
        let changed = try await model.api.libraryChanges(since: cursor)
        let mine = try XCTUnwrap(changed.entries.first { $0.titleId == entry.id },
                                 "the feed has the change: \(changed.entries.map(\.titleId))")
        XCTAssertEqual(mine.entry.progress, stepped.progress)

        // GupTrack's own pictures: with the token, then 304 for the copy kept (before the friend's phone signs in: the
        // picture loader follows the phone signed in last)
        let me = try await model.api.me()
        let avatar = try XCTUnwrap(Pictures.url(me.profile.avatar, base: base), "bin/gt-app-e2e gives the owner a picture")
        let auth = try XCTUnwrap(Pictures.authorization(for: avatar))
        let first = try await URLSession.shared.data(for: PictureFetch.request(avatar, authorization: auth, cached: false))
        let status = (first.1 as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(PictureFetch.outcome(status: status, data: first.0, cached: false), .fresh(first.0),
                       "\(avatar) answered \(status.map(String.init) ?? "nothing")")
        let again = try await URLSession.shared.data(for: PictureFetch.request(avatar, authorization: auth, cached: true))
        XCTAssertEqual((again.1 as? HTTPURLResponse)?.statusCode, 304)
        let anonymous = try await URLSession.shared.data(for: PictureFetch.request(avatar, authorization: nil, cached: false))
        XCTAssertEqual(PictureFetch.outcome(status: (anonymous.1 as? HTTPURLResponse)?.statusCode, data: anonymous.0,
                                            cached: true), .drop)

        // live: the stream opens, a friend signs in with their password and writes; the chat's news moves
        let stream = Task { await model.streamMessages(backoff: .milliseconds(200)) }
        await expect("the live stream opened") { model.live.connected }
        let friendPhone = try phone(folder, plugs: Plugs())
        let friendFlow = AccountFlowModel(model: friendPhone, start: "sign-in", server: base, device: "Friend's phone")
        friendFlow.username = setup.friend
        friendFlow.password = setup.friendPassword
        await friendFlow.signIn()
        XCTAssertNil(friendFlow.error)
        XCTAssertTrue(friendPhone.isSignedIn)
        XCTAssertEqual(friendPhone.account?.user.username, setup.friend)
        _ = try await friendPhone.api.sendMessage("owner", OutgoingMessage(body: "Hi"), requestId: UUID().uuidString)
        await expect("the message came over the stream") { model.live.version(setup.friend) >= 1 }
        await expect("the badge followed") { model.unreadMessages >= 1 }
        // "typing" once there's a conversation, ended by their next message
        _ = try await friendPhone.api.typing("owner")
        await expect("typing came over the stream") { model.live.isTyping(setup.friend) }
        let seen = model.live.version(setup.friend)
        _ = try await friendPhone.api.sendMessage("owner", OutgoingMessage(body: "Hello from the live test"),
                                                  requestId: UUID().uuidString)
        await expect("the second message came over the stream") { model.live.version(setup.friend) > seen }
        XCTAssertFalse(model.live.isTyping(setup.friend))
        let chat = try await model.api.conversation(setup.friend)
        XCTAssertEqual(chat.messages.last?.body, "Hello from the live test")
        stream.cancel()
        await stream.value

        // sign out: the phone forgets, and the old token stops working
        let token = try XCTUnwrap(model.account?.token)
        await model.signOut()
        XCTAssertFalse(model.isSignedIn)
        XCTAssertTrue(model.library.isEmpty)
        do {
            _ = try await APIClient(transport: LiveTransport(base: base), token: token).me()
            XCTFail("the token still works after signing out")
        } catch APIError.signedOut {}
        await friendPhone.signOut()
    }

    /// what each screen loads, decoded the way it does: a shape the server and the app disagree on fails here
    func readEveryScreen(_ api: APIClient, friend: String) async throws {
        func read<T>(_ what: String, _ call: () async throws -> T) async {
            do { _ = try await call() } catch { XCTFail("\(what): \(error)") }
        }
        await read("me") { try await api.me() }
        await read("home") { try await api.home() }
        await read("home/live") { try await api.homeLive() }
        await read("picks") { try await api.picks() }
        await read("notices") { try await api.notices() }
        await read("calendar") { try await api.calendar(month: Date()) }
        await read("profile") { try await api.myProfile() }
        await read("lists") { try await api.yourLists() }
        await read("custom lists") { try await api.customLists() }
        await read("friends") { try await api.friends() }
        await read("feed") { try await api.feed() }
        await read("messages") { try await api.messageList() }
        await read("pulse") { try await api.pulse() }
        await read("recipients") { try await api.recipients() }
        await read("conversation") { try await api.conversation(friend) }
        await read("their profile") { try await api.userProfile(friend) }
        await read("compare") { try await api.compare(friend) }
        // a title page from a search, as the Search screen opens one
        let found = try await api.search("Fullmetal")
        let hit = try XCTUnwrap(found.top?.title, "search found a title")
        await read("title page") { try await api.titlePage(hit.id) }
        for media in MediaKind.allCases {
            await read("browse \(media)") { try await api.browsePage(media) }
        }
        await read("settings: account") { try await api.accountSettings() }
        await read("settings: privacy") { try await api.privacySettings() }
        await read("settings: messages") { try await api.settingsMessages() }
        await read("settings: account info") { try await api.account() }
        await read("settings: devices") { try await api.devices() }
        await read("settings: backups") { try await api.savedBackups() }
        await read("settings: nightly backups") { try await api.nightlyBackups() }
        await read("settings: accounts") { try await api.accounts() }
    }
}
