import UIKit
import XCTest
@testable import GupTrack

/// The base of every screen test: the app's real screens in demo mode (invented fixtures, no server), driven inside
/// the unit-test process (ScreenDriver.swift). Each screen group has its own Screens<Group>Tests.swift; a picture's
/// name is its mockup's ("05-home"), so CI's shots/ folder lines up with "iPhone mockups/".
@MainActor
class ScreenTestCase: XCTestCase {
    private nonisolated(unsafe) var started = Date()

    override nonisolated func setUp() {
        started = Date()
        continueAfterFailure = false
    }

    override nonisolated func tearDown() {
        MainActor.assumeIsolated {
            // a failed test leaves its last screen and what was on it, to see why
            if let run = testRun, run.failureCount > 0, let app = App.current {
                let name = name.components(separatedBy: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "]")) ?? "test"
                app.shot("fail-\(name)")
                print("SCREEN at the failure of \(name):\n\(app.debugDescription)")
            }
            App.current?.close()
            Timing.report(name, Date().timeIntervalSince(started))
        }
    }

    /// the app in demo mode with launch flags: ["-open", "title/anime:210482"], ["-tab", "library"],
    /// ["-sheet", "new-list"], ["-account", "sign-in"]
    func launch(_ flags: [String] = []) -> App {
        App(flags, test: self)
    }

    /// any element whose label contains `text` (rows combine their texts into one accessibility element)
    func find(_ app: App, _ text: String) -> Element {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// waits for `text` on screen, failing the test if it doesn't come
    @discardableResult
    func expect(_ app: App, _ text: String, timeout: Double = 10, file: StaticString = #filePath,
                line: UInt = #line) -> Element {
        let e = find(app, text)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "no \"\(text)\" on screen\n\(app.debugDescription)",
                      file: file, line: line)
        return e
    }

    /// the screen as a picture named after its mockup
    func shot(_ name: String) {
        App.current?.shot(name)
    }

    /// a slow drag up by `points` that stops where it lets go (no fling), for the "scrolled" pictures
    /// (a negative `points` drags down, back towards the top)
    func scroll(_ app: App, by points: CGFloat) {
        let f = app.frame
        let sign: CGFloat = points < 0 ? -1 : 1
        var left = abs(points)
        while left > 0 {
            let step = min(left, f.height * 0.5)
            let from = CGPoint(x: f.midX, y: f.midY + sign * step / 2)
            let to = CGPoint(x: f.midX, y: f.midY - sign * step / 2)
            settle()
            Finger.press(from, seconds: 0, thenDragTo: to, speed: 500, hold: 0.4)
            idle()
            left -= step
        }
    }

    /// drags up until the element with `text` has its top at `y` or above (at most 12 drags); if a drag carried it
    /// up under the navigation bar, it drags back down so the element can be tapped
    func scroll(_ app: App, until text: String, top y: CGFloat = 140) {
        let e = find(app, text)
        for _ in 0..<12 {
            if e.exists, e.frame.minY <= y { break }
            let dy = e.exists ? max(40, e.frame.minY - y) : app.frame.height * 0.5
            scroll(app, by: dy)
        }
        let bar: CGFloat = 100
        if e.exists, e.frame.minY < bar {
            scroll(app, by: -(min(y, app.frame.height * 0.5) - e.frame.minY))
        }
    }
}
