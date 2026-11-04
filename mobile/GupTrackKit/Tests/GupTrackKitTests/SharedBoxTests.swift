import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The App Group's files the app shares with its widgets and share extension (SharedBox), in a test folder.
@MainActor
final class SharedBoxTests: XCTestCase {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shared-\(UUID().uuidString)")

    override func setUp() {
        Clock.fixed = Clock.demoNow
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    func model(_ box: SharedBox, signedIn: Bool = true) throws -> AppModel {
        let tokens = MemoryTokenStore(signedIn ? Demo.account() : nil)
        return AppModel(api: APIClient(transport: DemoTransport(offline: false), token: tokens.load()?.token),
                        store: try LibraryStore(), tokens: tokens, demo: true, shared: box)
    }

    func testStateRoundTripsAndOutboxIsTakenOnce() throws {
        let box = SharedBox(folder: folder)
        XCTAssertNil(box.read())
        let lib = Array(Demo.library().prefix(3))
        let state = SharedState(made: Clock.now, signedIn: true, demo: false, server: Demo.server, library: lib,
                                catalog: ExtensionCatalog())
        box.write(state)
        XCTAssertEqual(box.read(), state)

        let a = WidgetOutbox.Change(id: lib[0].id, patch: LibraryPatch(progress: 4), at: Clock.now)
        let b = WidgetOutbox.Change(id: "anime:9", patch: LibraryPatch(status: .planned), at: Clock.now,
                                    title: lib[1].title)
        box.append(a)
        box.append(b)
        // another process (the widget) sees the same box
        XCTAssertEqual(SharedBox(folder: folder).pending(), [a, b])
        XCTAssertEqual(box.take(), [a, b])
        XCTAssertEqual(box.take(), [])
        box.append(a)
        box.clear()
        XCTAssertEqual(box.pending(), [])
        XCTAssertEqual(box.read()?.signedIn, false)
        XCTAssertEqual(box.read()?.library, [])
    }

    func testAppSharesItsLibraryAndNextEpisodes() async throws {
        let box = SharedBox(folder: folder)
        let m = try model(box)
        await m.refresh()
        let state = try XCTUnwrap(box.read())
        XCTAssertTrue(state.signedIn)
        XCTAssertTrue(state.demo)
        XCTAssertEqual(state.server, m.account?.baseURL)
        XCTAssertEqual(state.library, m.library)

        let next = try Demo.load(ExtensionCatalog.self, "api/extensions.json").upcoming
        XCTAssertFalse(next.isEmpty)
        m.noteUpcoming(next)
        XCTAssertEqual(box.read()?.catalog.upcoming, next)

        // a change in the app shows in the widgets at once
        let first = try XCTUnwrap(m.library.first { $0.status == .current })
        m.step(first.id)
        XCTAssertEqual(box.read()?.library.first { $0.id == first.id }?.progress, first.progress + first.media.step)

        await m.signOut()
        XCTAssertEqual(box.read()?.signedIn, false)
        XCTAssertEqual(box.read()?.library, [])
    }

    func testAppTakesTheWidgetsAndShareSheetsChanges() async throws {
        let box = SharedBox(folder: folder)
        let m = try model(box)
        await m.refresh()
        let e = try XCTUnwrap(m.library.first { $0.status == .current })
        // a title that isn't on the list yet, added from the share sheet
        let catalog = try Demo.load(ExtensionCatalog.self, "api/extensions.json")
        let new = try XCTUnwrap(catalog.titles.first { m.entry($0.id) == nil })
        box.append(WidgetOutbox.Change(id: e.id, patch: LibraryPatch(progress: e.progress + 1), at: Clock.now))
        box.append(WidgetOutbox.Change(id: new.id, patch: LibraryPatch(status: .planned), at: Clock.now, title: new))
        await m.refresh()
        XCTAssertEqual(m.entry(e.id)?.progress, e.progress + 1)
        XCTAssertEqual(m.entry(new.id)?.status, .planned)
        XCTAssertEqual(m.entry(new.id)?.title.name, new.name)
        XCTAssertEqual(box.pending(), [])
        // and they're sent like any change made in the app
        XCTAssertEqual(m.pendingCount, 0)
    }

    func testSignedOutAppLeavesTheBoxAlone() throws {
        let box = SharedBox(folder: folder)
        let change = WidgetOutbox.Change(id: "anime:1", patch: LibraryPatch(progress: 2), at: Clock.now)
        box.append(change)
        let m = try model(box, signedIn: false)
        m.takeExtensionChanges()
        XCTAssertEqual(box.pending(), [change])
        XCTAssertEqual(box.read()?.signedIn, false)
    }

    func testPicturesOnTheServerGoThroughItsFilesWithTheToken() throws {
        let account = SharedAccount(baseURL: URL(string: "https://guptrack.example:8443/")!, token: Demo.account().token)
        let own = account.request(for: URL(string: "/media/covers/a.webp")!)
        XCTAssertEqual(own.url?.absoluteString, "https://guptrack.example:8443/api/app/v1/files/media/covers/a.webp")
        XCTAssertEqual(own.value(forHTTPHeaderField: "Authorization"), "Bearer demo-token")
        let cover = account.request(for: URL(string: "https://img.example/c.jpg")!)
        XCTAssertEqual(cover.url?.absoluteString, "https://img.example/c.jpg")
        XCTAssertNil(cover.value(forHTTPHeaderField: "Authorization"))
    }

    func bundled() -> (library: [LibraryEntry], catalog: ExtensionCatalog) {
        // swiftlint:disable:next force_try
        (Demo.library(), try! Demo.load(ExtensionCatalog.self, "api/extensions.json"))
    }

    func testExtensionsDrawFromTheAppOrTheirDemo() throws {
        // no App Group (the screen tests): the bundled demo
        let demo = ExtensionSource.current(nil, bundled: bundled)
        XCTAssertTrue(demo.demo && demo.signedIn && !demo.usesBox)
        XCTAssertEqual(demo.library, Demo.library())

        // the App Group, before the app has signed in: nothing to show
        let box = SharedBox(folder: folder)
        let empty = ExtensionSource.current(box, bundled: bundled)
        XCTAssertFalse(empty.signedIn)
        XCTAssertTrue(empty.library.isEmpty)
        XCTAssertTrue(empty.usesBox)

        // signed in: the app's library with the widget's +1 on top, and the app's next episodes
        let lib = Array(Demo.library().filter { $0.status == .current }.prefix(3))
        let next = bundled().catalog.upcoming.prefix(1)
        box.write(SharedState(made: Clock.now, signedIn: true, demo: false, server: Demo.server, library: lib,
                              catalog: ExtensionCatalog(upcoming: Array(next))))
        let after = try XCTUnwrap(box.step(lib[0].id, in: ExtensionSource.base(box), now: Clock.now))
        XCTAssertEqual(after.progress, lib[0].progress + lib[0].media.step)
        let live = ExtensionSource.current(box, bundled: bundled)
        XCTAssertFalse(live.demo)
        XCTAssertEqual(live.library.first?.progress, after.progress)
        XCTAssertEqual(live.catalog.upcoming, Array(next))
        XCTAssertTrue(live.catalog.titles.isEmpty)
        // a second +1 counts from the first
        XCTAssertEqual(box.step(lib[0].id, in: ExtensionSource.base(box), now: Clock.now)?.progress,
                       after.progress + lib[0].media.step)
        XCTAssertEqual(box.pending().count, 2)

        // the demo app: the bundled catalogue to match links against
        box.write(SharedState(made: Clock.now, signedIn: true, demo: true, server: Demo.server, library: lib,
                              catalog: ExtensionCatalog()))
        let shown = ExtensionSource.current(box, bundled: bundled)
        XCTAssertTrue(shown.demo)
        XCTAssertEqual(shown.catalog, bundled().catalog)
    }
}
