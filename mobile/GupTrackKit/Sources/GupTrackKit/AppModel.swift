import Foundation
import Observation

/// What a screen's data is doing: still coming, here, or not coming (with the reason to show).
enum Load<T> {
    case loading
    case loaded(T)
    case failed(String)

    var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var error: String? {
        if case .failed(let why) = self { return why }
        return nil
    }
}

extension Load: Equatable where T: Equatable {}
extension Load: Sendable where T: Sendable {}

/// How the library sync is doing, for the small status line in Library and Settings › Offline library.
enum SyncState: Equatable, Sendable {
    case idle
    case syncing
    case offline(String)
    case failed(String)
}

/// The app's state: who's signed in, the offline library, the selected tab, each tab's pages and the sheet on top.
/// Screens read it from the environment and load their own page data through `fetch`.
@Observable @MainActor
final class AppModel {
    // navigation
    var tab: AppTab = .home
    var paths: [AppTab: [Route]] = [:]
    var sheet: SheetRoute?

    // the account
    private(set) var account: ServerAccount?
    /// a signed-out screen to start on (the demo's -account flag)
    var accountScreen: String?

    // the library
    private(set) var library: [LibraryEntry] = []
    private(set) var pendingCount = 0
    private(set) var sync: SyncState = .idle
    private(set) var lastSynced: Date?
    /// a short message to show once ("Couldn't save: …")
    var notice: String?

    /// unread messages, the Social tab's badge (Social › Messages sets it when it loads)
    var unreadMessages = 0
    /// the red dot on Home's bell: from the home feed, cleared by Notifications
    var unreadNotifications = 0

    /// page loads under way (the screen tests wait for 0)
    private(set) var loading = 0

    private(set) var api: APIClient
    let store: LibraryStore
    let tokens: TokenStore
    let isDemo: Bool

    init(api: APIClient, store: LibraryStore, tokens: TokenStore, demo: Bool) {
        self.api = api
        self.store = store
        self.tokens = tokens
        self.isDemo = demo
        account = tokens.load()
        Pictures.signedIn = account.map { ($0.baseURL, $0.token) }
        reload()
    }

    /// the app as launched: the demo with -demo, else the Keychain's account and the library on disk
    static func make() -> AppModel {
        if Demo.isOn {
            Clock.fixed = Clock.demoNow
            Clock.fixedZone = Clock.demoZone
            let signedOut = Demo.value("-account") != nil
            let tokens = MemoryTokenStore(signedOut ? nil : Demo.account())
            let transport = DemoTransport(offline: Demo.has("-offline"))
            // swiftlint:disable:next force_try
            let store = try! LibraryStore()
            let m = AppModel(api: APIClient(transport: transport, token: tokens.load()?.token), store: store,
                             tokens: tokens, demo: true)
            m.accountScreen = Demo.value("-account")
            m.applyDemoFlags()
            return m
        }
        #if canImport(Security)
        let tokens: TokenStore = KeychainTokenStore()
        #else
        let tokens: TokenStore = MemoryTokenStore()
        #endif
        let store = (try? LibraryStore(path: libraryPath())) ?? (try! LibraryStore())
        let account = tokens.load()
        let api = APIClient(transport: LiveTransport(base: account?.baseURL ?? Demo.server), token: account?.token)
        return AppModel(api: api, store: store, tokens: tokens, demo: false)
    }

    static func libraryPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.sqlite").path
    }

    // MARK: navigation

    func path(_ tab: AppTab) -> [Route] { paths[tab] ?? [] }

    func setPath(_ tab: AppTab, _ path: [Route]) { paths[tab] = path }

    /// push a page on the current tab
    func open(_ route: Route) {
        paths[tab, default: []].append(route)
    }

    /// go to a tab's root (tapping the selected tab again)
    func popToRoot(_ tab: AppTab) { paths[tab] = [] }

    /// guptrack://… from a widget, the share extension or a notification: the page on its own tab
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let r = Route(url: url) else { return false }
        sheet = nil
        tab = r.homeTab
        paths[r.homeTab] = [r]
        return true
    }

    func applyDemoFlags() {
        let opened = Demo.values("-open").compactMap(Route.init(path:))
        if let t = Demo.value("-tab").flatMap(AppTab.init(rawValue:)) {
            tab = t
        } else if let first = opened.first {
            tab = first.homeTab
        }
        if !opened.isEmpty { paths[tab] = opened }
        sheet = Demo.value("-sheet").flatMap(SheetRoute.init(id:))
    }

    // MARK: the library

    var isSignedIn: Bool { account != nil }

    func entry(_ titleId: String) -> LibraryEntry? { library.first { $0.id == titleId } }

    func entries(_ media: MediaKind) -> [LibraryEntry] { library.filter { $0.media == media } }

    func entries(_ media: MediaKind, _ status: ListStatus) -> [LibraryEntry] {
        library.filter { $0.media == media && $0.status == status }
    }

    /// reread the offline library
    func reload() {
        library = (try? store.entries()) ?? []
        pendingCount = (try? store.pendingCount) ?? 0
    }

    /// change an entry now (offline too) and send it when the server can be reached
    @discardableResult
    func change(_ titleId: String, _ patch: LibraryPatch, title: Title? = nil) -> LibraryEntry? {
        let e: LibraryEntry?
        do {
            e = try store.change(titleId, patch, title: title ?? entry(titleId)?.title)
        } catch {
            notice = "Couldn't save that change on this iPhone."
            return entry(titleId)
        }
        reload()
        Task { await syncLibrary() }
        return e
    }

    /// +1 episode / chapter (books: +10 pages)
    func step(_ titleId: String, by n: Int = 1) {
        guard let e = entry(titleId) else { return }
        change(titleId, LibraryPatch(progress: e.progress + n * e.media.step))
    }

    /// send pending changes, then read the server's
    func syncLibrary() async {
        guard isSignedIn, sync != .syncing else { return }
        sync = .syncing
        loading += 1
        defer { loading -= 1 }
        do {
            let report = try await LibrarySync(api: api, store: store).run()
            sync = .idle
            lastSynced = Clock.now
            if let first = report.rejected.first {
                notice = "GupTrack didn't take a change to \(first.name): \(first.lastError ?? "no reason given")."
            }
        } catch let e as APIError {
            handle(e)
        } catch {
            sync = .failed("The library couldn't sync.")
        }
        reload()
    }

    /// everything a fresh launch or pull-to-refresh needs
    func refresh() async {
        reload()
        await syncLibrary()
    }

    // MARK: loading pages

    /// one screen's data from the server, counted for the screen tests
    func fetch<T>(_ work: (APIClient) async throws -> T) async -> Load<T> {
        loading += 1
        defer { loading -= 1 }
        do {
            return .loaded(try await work(api))
        } catch let e as APIError {
            handle(e)
            return .failed(e.message)
        } catch {
            return .failed("Something went wrong loading this.")
        }
    }

    private func handle(_ e: APIError) {
        switch e {
        case .signedOut:
            sync = .idle
            forget()
            notice = e.message
        case .unreachable(let why):
            sync = .offline(why)
        case .server(let s) where s.status == 429:
            sync = .offline(e.message)
        default:
            sync = .failed(e.message)
        }
    }

    // MARK: signing in and out

    /// the answer from pairing, signing in, joining or recovering: keeps the token, then reads GET me for the
    /// name and picture to show
    func signedIn(_ answer: SignInAnswer, server: URL) async {
        var a = ServerAccount(baseURL: server, token: answer.token, deviceId: answer.device.id,
                              user: UserRef(username: answer.user.username, name: answer.user.username, avatar: nil),
                              role: answer.user.role, signedInAt: Clock.now)
        api = APIClient(transport: isDemo ? api.transport : LiveTransport(base: server), token: answer.token)
        Pictures.signedIn = (server, answer.token)
        if let me = try? await api.me() { a.user = me.user(on: server) }
        tokens.save(a)
        account = a
        accountScreen = nil
        await refresh()
    }

    /// a client for a server before signing in (hello, pair, sign-in, join)
    func client(for server: URL) -> APIClient {
        APIClient(transport: isDemo ? api.transport : LiveTransport(base: server))
    }

    func signOut() async {
        _ = try? await api.signOut()
        forget()
    }

    private func forget() {
        tokens.clear()
        Pictures.signedIn = nil
        try? store.wipe()
        account = nil
        api = APIClient(transport: api.transport)
        paths = [:]
        sheet = nil
        tab = .home
        accountScreen = "welcome"
        reload()
    }
}
