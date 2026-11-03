import Foundation
import XCTest
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// The signed-out flow (01-04): address checks, username rule, password meter, recovery codes, and the flow on the
/// demo server from each first screen to signed in.
@MainActor
final class AccountFlowTests: XCTestCase {
    override func tearDown() {
        Demo.args = ["app"]
        Clock.fixed = nil
        Clock.fixedZone = nil
    }

    private func signedOut(_ screen: String = "connect") -> AppModel {
        Demo.args = ["app", "-demo", "-account", screen]
        return AppModel.make()
    }

    private let hello = ServerHello(app: "guptrack", version: "1.0.0", api: 1, name: "GupTrack", joining: "invite",
                                    passkeys: true)
    private let server = URL(string: "https://guptrack.example")!
    private let pairCode = String(repeating: "Ab3-_", count: 9)

    // MARK: fixtures

    func testFixturesDecode() throws {
        for f in ["pair", "sign-in", "recover"] {
            let g = try Demo.load(DeviceGrant.self, "api/auth/\(f).post.json")
            XCTAssertEqual(g.user.username, "mika")
            XCTAssertNil(g.recoveryCodes)
        }
        let joined = try Demo.load(DeviceGrant.self, "api/auth/join.post.json")
        XCTAssertEqual(joined.recoveryCodes?.count, 8)
        XCTAssertEqual(RecoveryCodes.columns(joined.recoveryCodes ?? []), 2)
        XCTAssertEqual(try Demo.load(ServerHello.self, "api/hello.json").app, "guptrack")
    }

    // MARK: the server address

    func testParseAddress() {
        XCTAssertEqual(ServerCheck.parse("  "), .empty)
        XCTAssertEqual(ServerCheck.parse("http://pc.example"), .invalid)
        XCTAssertEqual(ServerCheck.parse("localhost"), .invalid)
        XCTAssertEqual(ServerCheck.parse("PC.example "), .checking(URL(string: "https://pc.example")!))
    }

    func testVerdicts() {
        XCTAssertEqual(ServerCheck.verdict(hello, at: server), .found(server, hello))
        var other = hello
        other.app = "something"
        XCTAssertEqual(ServerCheck.verdict(other, at: server).server, nil)
        var newer = hello
        newer.api = 2
        if case .wrong(_, let why) = ServerCheck.verdict(newer, at: server) {
            XCTAssertTrue(why.contains("Update the app"))
        } else { XCTFail("a newer API should be wrong") }
        let found = ServerCheck.found(server, hello).help
        XCTAssertEqual(found.good, "Found GupTrack")
        XCTAssertEqual(found.text, " · you sign in or join next")
        XCTAssertFalse(found.problem)
        XCTAssertTrue(ServerCheck.invalid.help.problem)
        XCTAssertEqual(ServerCheck.display(URL(string: "https://pc.example:8443")!), "pc.example:8443")
        XCTAssertEqual(ServerCheck.display(server), "guptrack.example")
    }

    func testCheckAgainstTheDemo() async {
        let m = signedOut()
        let ok = await ServerCheck.check(server, with: m.client(for: server))
        XCTAssertEqual(ok.hello?.name, "GupTrack")
        Demo.args = ["app", "-demo", "-account", "connect", "-offline"]
        let off = AppModel.make()
        let down = await ServerCheck.check(server, with: off.client(for: server))
        XCTAssertEqual(down, .unreachable(server, "This iPhone is offline."))
    }

    // MARK: usernames and passwords

    func testUsernameRule() {
        XCTAssertEqual(UsernameRule.check(""), .empty)
        XCTAssertEqual(UsernameRule.check(" Mika "), .ok)
        XCTAssertEqual(UsernameRule.check("noor.reads"), .ok)
        XCTAssertEqual(UsernameRule.check("ab"), .tooShort)
        XCTAssertEqual(UsernameRule.check(String(repeating: "a", count: 33)), .tooLong)
        XCTAssertEqual(UsernameRule.check(".mika"), .badStart)
        XCTAssertEqual(UsernameRule.check("mi ka"), .badCharacters)
        XCTAssertEqual(UsernameRule.check("mika!"), .badCharacters)
        XCTAssertFalse(UsernameRule.ok.isProblem)
        XCTAssertTrue(UsernameRule.tooShort.isProblem)
    }

    func testPasswordMeter() {
        XCTAssertEqual(PasswordMeter("").lit, 0)
        XCTAssertNil(PasswordMeter("").tone)
        XCTAssertEqual(PasswordMeter("").label, "At least 15 characters.")
        XCTAssertEqual(PasswordMeter("short").label, "5 characters · at least 15")
        XCTAssertFalse(PasswordMeter("short").acceptable)
        XCTAssertEqual(PasswordMeter("aaaaaaaaaaaaaaa").lit, 1)
        XCTAssertTrue(PasswordMeter("aaaaaaaaaaaaaaa").acceptable)
        XCTAssertEqual(PasswordMeter("aaaaaaaaaaaaaa1").tone, "star")
        let strong = PasswordMeter("Paper-lantern-42xy")
        XCTAssertEqual(strong.strength, .strong)
        XCTAssertEqual(strong.lit, 3)
        XCTAssertEqual(strong.label, "Strong · 18 characters")
        XCTAssertEqual(PasswordMeter("correct horse battery staple").lit, 4)
    }

    // MARK: recovery codes

    func testRecoveryCodesText() {
        let t = RecoveryCodes.text(["aaaa-bbbb", "cccc-dddd"], username: "mika", server: server)
        XCTAssertTrue(t.hasPrefix("GupTrack recovery codes for mika on guptrack.example\n\n1. aaaa-bbbb\n2. cccc-dddd\n"))
        XCTAssertEqual(RecoveryCodes.fileName(username: "mika"), "GupTrack recovery codes (mika).txt")
        XCTAssertEqual(RecoveryCodes.columns(["8k3qd-x0v7m-abcde-fghjk-mnpqr-s"]), 1)
        XCTAssertEqual(RecoveryCodes.normalize(" K7RQ-2mvx "), "k7rq2mvx")
    }

    // MARK: the flow

    func testStartScreens() {
        let m = signedOut()
        XCTAssertEqual(AccountFlowModel(model: m, start: "connect", server: nil, device: "iPhone").current, .connect)
        XCTAssertEqual(AccountFlowModel(model: m, start: "welcome", server: server, device: "iPhone").current, .signIn)
        XCTAssertEqual(AccountFlowModel(model: m, start: "welcome", server: nil, device: "iPhone").current, .connect)
        XCTAssertEqual(AccountFlowModel(model: m, start: "connect", server: server, device: "iPhone").current, .connect)
        // signing in needs a server: without one it starts on connect
        XCTAssertEqual(AccountFlowModel(model: m, start: "sign-in", server: nil, device: "iPhone").current, .connect)
        XCTAssertEqual(AccountFlowModel(model: m, start: "sign-in", server: server, device: "iPhone").current, .signIn)
        let join = AccountFlowModel(model: m, start: "join", server: server, device: "iPhone")
        XCTAssertEqual(join.root, .signIn)
        XCTAssertEqual(join.path, [.join])
        XCTAssertEqual(join.address, "guptrack.example")
        XCTAssertEqual(AccountFlowModel(model: m, start: "recovery", server: server, device: "iPhone").current, .codes)
    }

    func testConnectThenSignIn() async {
        let m = signedOut()
        let f = AccountFlowModel(model: m, start: "connect", server: nil, device: "Mika's iPhone")
        XCTAssertFalse(f.canContinue)
        f.address = "guptrack.example"
        await f.checkAddress()
        XCTAssertEqual(f.check.hello?.app, "guptrack")
        XCTAssertTrue(f.canContinue)
        f.useCheckedServer()
        XCTAssertEqual(f.current, .signIn)
        XCTAssertEqual(f.server, server)
        XCTAssertFalse(f.canSignIn)
        f.username = "Mika"
        f.password = "demo-password"
        XCTAssertTrue(f.canSignIn)
        await f.signIn()
        XCTAssertNil(f.error)
        XCTAssertTrue(m.isSignedIn)
        XCTAssertEqual(m.account?.user.username, "mika")
        XCTAssertEqual(m.account?.baseURL, server)
        XCTAssertFalse(m.library.isEmpty)
        XCTAssertEqual(f.password, "")
        // what went up
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/sign-in" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(SignInBody.self, from: $0) }
        XCTAssertEqual(body, SignInBody(username: "mika", password: "demo-password", device: "Mika's iPhone"))
    }

    func testChangeServer() {
        let f = AccountFlowModel(model: signedOut(), start: "sign-in", server: server, device: "iPhone")
        f.go(.recover)
        f.changeServer()
        XCTAssertEqual(f.current, .connect)
        XCTAssertEqual(f.path, [])
    }

    func testSignInOffline() async {
        Demo.args = ["app", "-demo", "-account", "sign-in", "-offline"]
        let m = AppModel.make()
        let f = AccountFlowModel(model: m, start: "sign-in", server: server, device: "iPhone")
        f.username = "mika"
        f.password = "x"
        await f.signIn()
        XCTAssertEqual(f.error, "This iPhone is offline.")
        XCTAssertFalse(m.isSignedIn)
        XCTAssertFalse(f.busy)
    }

    func testPairing() async {
        let m = signedOut()
        let f = AccountFlowModel(model: m, start: "connect", server: nil, device: "Mika's iPhone")
        let problem = await f.pair("https://example.com")
        XCTAssertEqual(problem, PairLink.Problem.notOurs.message)
        XCTAssertFalse(m.isSignedIn)
        let link = "guptrack://pair?v=1&url=https%3A%2F%2Fguptrack.example&code=\(pairCode)"
        let none = await f.pair(link)
        XCTAssertNil(none)
        XCTAssertTrue(m.isSignedIn)
        XCTAssertEqual(f.address, "guptrack.example")
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/pair" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(PairBody.self, from: $0) }
        XCTAssertEqual(body, PairBody(code: pairCode, device: "Mika's iPhone"))
    }

    func testJoinShowsCodesThenSignsIn() async {
        let m = signedOut("join")
        let f = AccountFlowModel(model: m, start: "join", server: server, device: "iPhone")
        f.hello = hello
        XCTAssertTrue(f.needsInvite)
        f.username = "Mika"
        f.displayName = "Mika"
        f.password = "demo-Paper-lantern-42"
        XCTAssertFalse(f.canJoin, "needs the invite")
        f.invite = "an-invite"
        XCTAssertTrue(f.canJoin)
        await f.join()
        XCTAssertEqual(f.current, .codes)
        XCTAssertEqual(f.codes.count, 8)
        XCTAssertFalse(m.isSignedIn, "not until the codes are saved")
        XCTAssertTrue(f.codesText.contains("1. h3tm-8qwe"))
        await f.finishJoining()
        XCTAssertFalse(m.isSignedIn, "the box isn't ticked")
        f.saved = true
        await f.finishJoining()
        XCTAssertTrue(m.isSignedIn)
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/join" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(JoinBody.self, from: $0) }
        XCTAssertEqual(body?.username, "mika")
        XCTAssertEqual(body?.invite, "an-invite")
    }

    func testOpenJoiningNeedsNoInvite() {
        let f = AccountFlowModel(model: signedOut(), start: "join", server: server, device: "iPhone")
        var open = hello
        open.joining = "open"
        f.hello = open
        f.username = "mika"
        f.password = "demo-Paper-lantern-42"
        XCTAssertTrue(f.canJoin)
        open.joining = "closed"
        f.hello = open
        XCTAssertFalse(f.canJoinHere)
    }

    func testDemoRecoveryScreen() async {
        let f = AccountFlowModel(model: signedOut("recovery"), start: "recovery", server: server, device: "iPhone")
        await f.demoJoin()
        XCTAssertEqual(f.codes.first, "h3tm-8qwe")
    }

    func testRecover() async {
        let m = signedOut("sign-in")
        let f = AccountFlowModel(model: m, start: "recover", server: server, device: "iPhone")
        XCTAssertEqual(f.current, .recover)
        f.username = "mika"
        f.code = "h3tm-8qwe"
        f.password = "short"
        XCTAssertFalse(f.canRecover)
        f.password = "demo-Paper-lantern-42"
        await f.recover()
        XCTAssertTrue(m.isSignedIn)
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/recover" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(RecoverBody.self, from: $0) }
        XCTAssertEqual(body?.code, "h3tm8qwe")
    }

    func testPasskeyURL() {
        let f = AccountFlowModel(model: signedOut(), start: "sign-in", server: server, device: "Mika's iPhone")
        XCTAssertEqual(f.passkeyURL()?.absoluteString, "https://guptrack.example/connect/app?device=Mika's%20iPhone")
    }

    func testGoBackToSignIn() {
        let f = AccountFlowModel(model: signedOut(), start: "join", server: server, device: "iPhone")
        f.go(.signIn)
        XCTAssertEqual(f.path, [])
        f.go(.join)
        XCTAssertEqual(f.path, [.join])
    }
}
