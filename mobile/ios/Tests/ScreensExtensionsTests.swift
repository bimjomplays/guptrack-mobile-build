import SwiftUI
import XCTest
@testable import GupTrack

/// Widgets, Lock Screen and Share to GupTrack (65, 65b, 66). The extensions can't run in the test host, so their
/// faces (WidgetViews.swift, ShareView.swift, compiled into the app) are drawn on stand-ins for the Home Screen, the
/// Lock Screen and a shared page (ExtensionsMocks.swift), on the app's demo library.
final class ScreensExtensionsTests: ScreenTestCase {
    private func host<V: View>(_ app: App, _ view: V) {
        app.window.rootViewController = UIHostingController(
            rootView: view.environment(app.model).preferredColorScheme(.dark))
    }

    private static let severance = "https://www.themoviedb.org/tv/95396-severance"

    func test65Widgets() {
        let app = launch()
        host(app, MockHomeScreen())
        expect(app, "Continue")
        expect(app, "STEEL BALL RUN")
        shot("65-widgets")
    }

    func test65bLockScreen() {
        let app = launch()
        host(app, MockLockScreen())
        expect(app, "Next episode")
        expect(app, "of 11")
        shot("65b-lock-screen")
    }

    func test66ShareExtension() {
        let app = launch()
        host(app, MockSharePage(shared: Self.severance))
        expect(app, "Add to GupTrack")
        expect(app, "Severance")
        expect(app, "Matched from the link")
        expect(app, "Season 2")
        shot("66-share-extension")
    }

    func testWidgetPlusSteps() {
        let app = launch()
        host(app, MockHomeScreen())
        let plus = expect(app, "Add one to STEEL")
        let before = app.model.entry("anime:210482")?.progress ?? 0
        plus.tap()
        XCTAssertTrue(poll(5) { app.model.entry("anime:210482")?.progress == before + 1 })
    }

    func testSharePicksStatus() {
        let app = launch()
        var added: ShareMatch.Draft?
        host(app, MockSharePage(shared: Self.severance, onAdd: { added = $0 }))
        expect(app, "Plan to Watch").tap()
        expect(app, "Save").tap()
        XCTAssertTrue(poll(5) { added != nil })
        XCTAssertEqual(added?.status, .planned)
    }

    func testShareStepsProgress() {
        let app = launch()
        var added: ShareMatch.Draft?
        host(app, MockSharePage(shared: Self.severance, onAdd: { added = $0 }))
        let before = app.model.entry("tv:95396")?.progress ?? 0
        expect(app, "One more").tap()
        expect(app, "Save").tap()
        XCTAssertTrue(poll(5) { added != nil })
        XCTAssertEqual(added?.progress, before + 1)
    }
}
