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

    private let info = ServerInfo(app: "guptrack", api: 1, setupOpen: false, serverTime: 1_793_716_860_000)
    private let server = URL(string: "https://guptrack.example")!
    private let pairCode = "7KQ4-M2XD"

    // MARK: fixtures

    func testFixturesDecode() throws {
        for f in ["pair", "sign-in", "recover"] {
            let g = try Demo.load(SignInAnswer.self, "api/auth/\(f).post.json")
            XCTAssertEqual(g.user.username, "mika")
            XCTAssertFalse(g.token.isEmpty)
            XCTAssertNil(g.recoveryCodes)
        }
        XCTAssertEqual(try Demo.load(SignInAnswer.self, "api/auth/recover.post.json").codesLeft, 7)
        let joined = try Demo.load(SignInAnswer.self, "api/auth/join.post.json")
        XCTAssertEqual(joined.recoveryCodes?.count, 10)
        for c in joined.recoveryCodes ?? [] {
            XCTAssertEqual(RecoveryCodes.normalize(c).count, 26, c)
            XCTAssertTrue(RecoveryCodes.normalize(c).uppercased().allSatisfy(PairLink.crockford.contains), c)
        }
        XCTAssertEqual(RecoveryCodes.columns(joined.recoveryCodes ?? []), 1)
        XCTAssertEqual(try Demo.load(ServerInfo.self, "api/server.json").app, "guptrack")
        XCTAssertEqual(try Demo.load(PairCheck.self, "api/auth/pair/check.post.json").user.username, "mika")
    }

    // MARK: the server address

    func testParseAddress() {
        XCTAssertEqual(ServerCheck.parse("  "), .empty)
        XCTAssertEqual(ServerCheck.parse("http://pc.example"), .invalid)
        XCTAssertEqual(ServerCheck.parse("http://localhost:3000"), .checking(URL(string: "http://localhost:3000")!))
        XCTAssertEqual(ServerCheck.parse("PC.example "), .checking(URL(string: "https://pc.example")!))
    }

    func testVerdicts() {
        XCTAssertEqual(ServerCheck.verdict(info, at: server), .found(server, info))
        var other = info
        other.app = "something"
        XCTAssertEqual(ServerCheck.verdict(other, at: server).server, nil)
        var empty = info
        empty.setupOpen = true
        if case .wrong(_, let why) = ServerCheck.verdict(empty, at: server) {
            XCTAssertTrue(why.contains("no accounts yet"))
        } else { XCTFail("a server nobody set up has no one to sign in as") }
        var newer = info
        newer.api = 2
        if case .wrong(_, let why) = ServerCheck.verdict(newer, at: server) {
            XCTAssertTrue(why.contains("Update the app"))
        } else { XCTFail("a newer API should be wrong") }
        let found = ServerCheck.found(server, info).help
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
        XCTAssertEqual(ok.info?.app, "guptrack")
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
        XCTAssertEqual(RecoveryCodes.normalize("oIl0-L"), "01101")
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
        XCTAssertEqual(f.check.info?.app, "guptrack")
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
        XCTAssertEqual(m.account?.user.name, "Mika", "the name comes from GET me after signing in")
        XCTAssertEqual(m.account?.deviceId, 1)
        XCTAssertEqual(m.account?.baseURL, server)
        XCTAssertFalse(m.library.isEmpty)
        XCTAssertEqual(f.password, "")
        // what went up
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/sign-in" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(SignInBody.self, from: $0) }
        XCTAssertEqual(body, SignInBody(username: "mika", password: "demo-password",
                                        device: DeviceInfo(name: "Mika's iPhone", platform: AccountFlowModel.platform)))
        XCTAssertNil(sent?.requestId, "signed-out calls carry no X-Request-Id")
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
        let link = "guptrack://pair?server=https%3A%2F%2Fguptrack.example&code=\(pairCode)"
        let none = await f.pair(link)
        XCTAssertNil(none)
        XCTAssertTrue(m.isSignedIn)
        XCTAssertEqual(f.address, "guptrack.example")
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/pair" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(PairBody.self, from: $0) }
        XCTAssertEqual(body, PairBody(code: pairCode, device: DeviceInfo(name: "Mika's iPhone", platform: AccountFlowModel.platform)))
    }

    func testJoinShowsCodesThenSignsIn() async {
        let m = signedOut("join")
        let f = AccountFlowModel(model: m, start: "join", server: server, device: "iPhone")
        f.info = info
        XCTAssertTrue(f.needsInvite)
        f.username = "Mika"
        f.displayName = "Mika"
        f.password = "demo-Paper-lantern-42"
        XCTAssertFalse(f.canJoin, "needs the invite")
        f.invite = "an-invite"
        XCTAssertTrue(f.canJoin)
        await f.join()
        XCTAssertEqual(f.current, .codes)
        XCTAssertEqual(f.codes.count, 10)
        XCTAssertFalse(m.isSignedIn, "not until the codes are saved")
        XCTAssertTrue(f.codesText.contains("1. 92qhv-1fkpj-86nmg-egagw-6txnh-s"))
        // the display name is set on the new account's profile with its token
        let named = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "settings/profile" }
        XCTAssertEqual(named?.method, "PATCH")
        XCTAssertEqual(named?.token, try Demo.load(SignInAnswer.self, "api/auth/join.post.json").token)
        XCTAssertEqual(named?.body.flatMap { try? APIClient.decoder.decode(ProfilePatch.self, from: $0) }, ProfilePatch(name: "Mika"))
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

    func testDemoRecoveryScreen() async {
        let f = AccountFlowModel(model: signedOut("recovery"), start: "recovery", server: server, device: "iPhone")
        await f.demoJoin()
        XCTAssertEqual(f.codes.first, "92qhv-1fkpj-86nmg-egagw-6txnh-s")
    }

    func testRecover() async {
        let m = signedOut("sign-in")
        let f = AccountFlowModel(model: m, start: "recover", server: server, device: "iPhone")
        XCTAssertEqual(f.current, .recover)
        f.username = "mika"
        f.code = "92QHV 1FKPJ-86NMG-EGAGW-6TXNH-S"
        f.password = "short"
        XCTAssertFalse(f.canRecover)
        f.password = "demo-Paper-lantern-42"
        await f.recover()
        XCTAssertTrue(m.isSignedIn)
        let sent = (m.api.transport as? DemoTransport)?.requests.first { $0.path == "auth/recover" }
        let body = sent?.body.flatMap { try? APIClient.decoder.decode(RecoverBody.self, from: $0) }
        XCTAssertEqual(body?.code, "92qhv1fkpj86nmgegagw6txnhs")
    }

    func testGoBackToSignIn() {
        let f = AccountFlowModel(model: signedOut(), start: "join", server: server, device: "iPhone")
        f.go(.signIn)
        XCTAssertEqual(f.path, [])
        f.go(.join)
        XCTAssertEqual(f.path, [.join])
    }
}
