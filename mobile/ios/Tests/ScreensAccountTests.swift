import XCTest
@testable import GupTrack

/// Signed out (01-04): connect, sign in, join, recovery codes.
final class ScreensAccountTests: ScreenTestCase {
    func test01ConnectServer() {
        let app = launch(["-account", "connect"])
        expect(app, "Connect to your GupTrack")
        expect(app, "Scan the pairing code")
        expect(app, "or enter it yourself")
        expect(app, "Found GupTrack")
        expect(app, "Listed under Connected devices")
        XCTAssertTrue(app.buttons["Continue"].exists)
        shot("01-connect-server")
    }

    func test02SignIn() {
        let app = launch(["-account", "sign-in"])
        expect(app, "Sign in to your library.")
        expect(app, "guptrack.example")
        expect(app, "Sign in with a passkey")
        expect(app, "Use a recovery code")
        expect(app, "Join GupTrack")
        shot("02-sign-in")
    }

    func test03Join() {
        let app = launch(["-account", "join"])
        expect(app, "Make your account.")
        expect(app, "Shown on your profile.")
        expect(app, "Strong · 18 characters")
        expect(app, "Create account")
        expect(app, "Next you'll get recovery codes")
        shot("03-join")
    }

    func test04RecoveryCodes() {
        let app = launch(["-account", "recovery"])
        expect(app, "Save your recovery codes")
        expect(app, "h3tm-8qwe")
        expect(app, "s7gh-5wnp")
        expect(app, "Save to Files")
        expect(app, "I've saved these").tap()
        XCTAssertTrue(app.buttons["Open GupTrack"].isEnabled)
        shot("04-recovery-codes")
    }

    // MARK: behaviour

    func testSigningInLandsOnHome() {
        let app = launch(["-account", "sign-in"])
        let username = app.textFields["Username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.typeText(String(repeating: "\u{8}", count: 8) + "mika")
        app.buttons["Sign in"].tap()
        expect(app, "Upcoming")
        XCTAssertTrue(app.model.isSignedIn)
        XCTAssertEqual(app.model.account?.user.username, "mika")
        XCTAssertEqual(app.model.tab, .home)
    }

    func testContinueGoesToSignIn() {
        let app = launch(["-account", "connect"])
        expect(app, "Found GupTrack")
        app.buttons["Continue"].tap()
        expect(app, "Sign in to your library.")
        app.buttons["Change server"].tap()
        expect(app, "Connect to your GupTrack")
    }

    func testTypingABadAddress() {
        let app = launch(["-account", "connect"])
        expect(app, "Found GupTrack")
        app.textFields["Server address"].typeText(String(repeating: "\u{8}", count: 20) + "http://")
        expect(app, "isn't an address the app can use")
        XCTAssertFalse(app.buttons["Continue"].isEnabled)
    }

    func testPastedPairingLinkSignsIn() {
        let app = launch(["-account", "connect"])
        expect(app, "Scan the pairing code").tap()
        expect(app, "The camera isn't available here.")
        let code = String(repeating: "demo-pair-", count: 5)
        app.textFields["Pairing link"].typeText("guptrack://pair?v=1&url=https%3A%2F%2Fguptrack.example&code=\(code)")
        app.buttons["Connect"].tap()
        expect(app, "Upcoming")
        XCTAssertTrue(app.model.isSignedIn)
    }

    func testJoinShowsCodesThenOpensGupTrack() {
        let app = launch(["-account", "join"])
        // the demo fills in the form (and the demo server's invite)
        expect(app, "Strong · 18 characters")
        scroll(app, until: "Create account", top: 400)
        app.buttons["Create account"].tap()
        expect(app, "Save your recovery codes")
        XCTAssertFalse(app.model.isSignedIn)
        XCTAssertFalse(app.buttons["Open GupTrack"].isEnabled)
        expect(app, "I've saved these").tap()
        app.buttons["Open GupTrack"].tap()
        expect(app, "Upcoming")
        XCTAssertTrue(app.model.isSignedIn)
    }

    func testJoinAndRecoverOpenFromSignIn() {
        let app = launch(["-account", "sign-in"])
        expect(app, "Join GupTrack").tap()
        expect(app, "Make your account.")
        expect(app, "Have an account?").tap()
        expect(app, "Sign in to your library.")
        expect(app, "Use a recovery code").tap()
        expect(app, "Set password and sign in")
    }
}
