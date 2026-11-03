import Foundation
import Observation

// The signed-out screens' logic (01-04): checking a typed server address, the username rule, the password meter,
// the recovery codes as text, and the flow itself (AccountFlowModel) from the first screen to the signed-in app.
// The views are mobile/ios/Sources/Account/.
//
// Pairing: the website's Settings › Connected apps shows a QR code of a PairLink (Account.swift):
//     guptrack://pair?v=1&url=<percent-encoded https server address>&code=<one-time code, base64url, 43+ chars>
// Scanning it (in the app, or with the Camera app, which opens the link) pairs this iPhone in one step: POST
// auth/pair with the code and the device's name gives the DeviceGrant.
//
// Passkeys: a native passkey needs the server's domain in the app's Associated Domains, which a self-hosted server
// can't have. So "Sign in with a passkey" opens the website's own sign-in in a system web sheet
// (ASWebAuthenticationSession) at <server>/connect/app?device=<name>; once signed in there the website redirects
// to the same guptrack://pair link, and the app pairs with it. (The website route is still to be built.)

// MARK: the server address

/// What the Server address field knows about what was typed.
enum ServerCheck: Equatable, Sendable {
    case empty
    /// not an https address the app would use
    case invalid
    case checking(URL)
    case found(URL, ServerHello)
    /// something answered, but not GupTrack (or a GupTrack this app can't talk to)
    case wrong(URL, String)
    case unreachable(URL, String)

    /// the address to use, once it answered as GupTrack
    var server: URL? {
        if case .found(let u, _) = self { return u }
        return nil
    }

    var hello: ServerHello? {
        if case .found(_, let h) = self { return h }
        return nil
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    /// the line under the field: (lead in green when found, rest muted) or a problem
    var help: (good: String?, text: String, problem: Bool) {
        switch self {
        case .empty:
            return (nil, "The address of the PC running GupTrack, from the Tailscale app.", false)
        case .invalid:
            return (nil, "That isn't an address the app can use. It's a name like your-pc.example, over HTTPS.", true)
        case .checking:
            return (nil, "Looking for GupTrack…", false)
        case .found(_, let h):
            let next = h.joining == "closed" ? "you sign in next" : "you sign in or join next"
            return ("Found \(h.name)", " · " + next, false)
        case .wrong(_, let why), .unreachable(_, let why):
            return (nil, why, true)
        }
    }

    /// what a server's hello means for this app
    static func verdict(_ hello: ServerHello, at url: URL) -> ServerCheck {
        guard hello.app == "guptrack" else { return .wrong(url, "Something answered there, but it isn't GupTrack.") }
        if hello.api > AppAPI.version {
            return .wrong(url, "This GupTrack is newer than the app. Update the app.")
        }
        if hello.api < AppAPI.version {
            return .wrong(url, "This GupTrack is older than the app. Update GupTrack on the PC.")
        }
        return .found(url, hello)
    }

    /// the field's text as an address, without asking the server yet
    static func parse(_ text: String) -> ServerCheck {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .empty }
        guard let url = PairLink.serverURL(t) else { return .invalid }
        return .checking(url)
    }

    /// asks the server at `url` who it is
    static func check(_ url: URL, with client: APIClient) async -> ServerCheck {
        do {
            return verdict(try await client.hello(), at: url)
        } catch let e as APIError {
            switch e {
            case .unreachable(let why): return .unreachable(url, why)
            case .unreadable: return .wrong(url, "Something answered there, but it isn't GupTrack.")
            default: return .wrong(url, e.message)
            }
        } catch {
            return .unreachable(url, "Can't reach that address.")
        }
    }

    /// the address as shown on the sign-in screen ("guptrack.example", with a port if it has one)
    static func display(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return url.port.map { "\(host):\($0)" } ?? host
    }
}

// MARK: usernames

/// The website's username rule (src/auth/auth.server.ts USERNAME): 3-32 of a-z 0-9 . _ -, starting with a letter or
/// digit; typed case and outer spaces don't matter.
enum UsernameRule: Equatable, Sendable {
    case empty, ok, tooShort, tooLong, badStart, badCharacters

    static func normalize(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    static func check(_ typed: String) -> UsernameRule {
        let s = normalize(typed)
        if s.isEmpty { return .empty }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz" + "0123456789" + "._-")
        guard s.allSatisfy(allowed.contains) else { return .badCharacters }
        guard let first = s.first, first.isLetter || first.isNumber else { return .badStart }
        if s.count < 3 { return .tooShort }
        if s.count > 32 { return .tooLong }
        return .ok
    }

    static let hint = "You sign in with it, and friends find you by it. Letters, numbers, dots, dashes and underscores."

    /// the line under the field
    var message: String {
        switch self {
        case .empty, .ok: return Self.hint
        case .tooShort: return "At least 3 characters."
        case .tooLong: return "At most 32 characters."
        case .badStart: return "Start with a letter or a number."
        case .badCharacters: return "Only letters, numbers, dots, dashes and underscores."
        }
    }

    var isProblem: Bool { self != .empty && self != .ok }
}

// MARK: the password meter

/// The Join screen's four-part meter under the password ("Strong · 18 characters"), from PasswordStrength.
struct PasswordMeter: Equatable, Sendable {
    let strength: PasswordStrength
    let characters: Int

    init(_ password: String) {
        strength = PasswordStrength.of(password)
        characters = password.count
    }

    /// how many of the four parts are lit: weak 1, fair 2, strong 3, and the fourth for a long strong one
    var lit: Int {
        switch strength {
        case .tooShort: return characters == 0 ? 0 : 1
        case .weak: return 1
        case .fair: return 2
        case .strong: return characters >= 24 ? 4 : 3
        }
    }

    /// the colour's name for the view: "danger", "star", "good", or nil (nothing typed)
    var tone: String? {
        switch strength {
        case .tooShort: return characters == 0 ? nil : "danger"
        case .weak: return "danger"
        case .fair: return "star"
        case .strong: return "good"
        }
    }

    var label: String {
        if characters == 0 { return "At least 15 characters." }
        let n = characters == 1 ? "1 character" : "\(characters) characters"
        if strength == .tooShort { return "\(n) · at least 15" }
        return "\(strength.label) · \(n)"
    }

    /// good enough to make the account with
    var acceptable: Bool { strength >= .weak }
}

// MARK: recovery codes

enum RecoveryCodes {
    /// the codes as the Copy button and the saved file have them
    static func text(_ codes: [String], username: String, server: URL) -> String {
        var lines = ["GupTrack recovery codes for \(username) on \(ServerCheck.display(server))", ""]
        for (i, c) in codes.enumerated() { lines.append("\(i + 1). \(c)") }
        lines += ["", "If you forget your password, one of these gets you back in. Each code works once."]
        return lines.joined(separator: "\n") + "\n"
    }

    /// the saved file's name
    static func fileName(username: String) -> String { "GupTrack recovery codes (\(username)).txt" }

    /// two columns when every code is short enough to fit half the width (the mockup's "k7rq-2mvx"), else one
    static func columns(_ codes: [String]) -> Int { (codes.map(\.count).max() ?? 0) <= 12 ? 2 : 1 }

    /// how a typed code is compared (the website's normalizeCode): case, spaces and dashes don't matter
    static func normalize(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    }
}

// MARK: recovering with a code (not in AppAPI yet)

/// POST auth/recover: a new password with a recovery code; signs this device in like sign-in does
struct RecoverBody: Codable, Equatable, Sendable {
    var username: String
    var code: String
    var password: String
    var device: String
}

extension APIClient {
    func recover(_ body: RecoverBody) async throws -> DeviceGrant { try await send("POST", "auth/recover", body) }
}

// MARK: the flow

/// The signed-out flow's state: which screen, the server it talks to, what's typed, and the calls. The view keeps one
/// of these; RootView shows the tabs as soon as `AppModel.signedIn` runs.
@Observable @MainActor
final class AccountFlowModel {
    enum Step: String, Hashable, Sendable {
        case connect, signIn = "sign-in", join, recover, codes = "recovery"
    }

    /// the screen at the bottom of the stack (connect or sign-in, or the codes after joining)
    var root: Step
    /// screens pushed on it (join and recover over sign-in)
    var path: [Step] = []

    // connect
    var address = ""
    var check: ServerCheck = .empty
    var device: String
    // the server signed-in screens use (checked on connect, or kept from last time)
    var server: URL?
    var hello: ServerHello?

    // sign in, join, recover
    var username = ""
    var password = ""
    var displayName = ""
    var invite = ""
    var code = ""

    var busy = false
    var error: String?

    /// after joining: the grant waits here until the codes are saved
    private(set) var joined: DeviceGrant?

    let model: AppModel

    init(model: AppModel, start: String?, server: URL?, device: String) {
        self.model = model
        self.server = server
        self.device = device
        if let server { address = ServerCheck.display(server) }
        switch start {
        case "sign-in": root = server == nil ? .connect : .signIn
        case "join": root = server == nil ? .connect : .signIn; if server != nil { path = [.join] }
        case "recover": root = server == nil ? .connect : .signIn; if server != nil { path = [.recover] }
        case "recovery": root = .codes
        case "connect": root = .connect
        // after signing out ("welcome") with a server from last time: straight to signing in there
        default: root = server == nil ? .connect : .signIn
        }
    }

    /// the screen showing now
    var current: Step { path.last ?? root }

    private var client: APIClient? { server.map { model.client(for: $0) } }

    // MARK: connect

    /// called (debounced) as the address changes
    func checkAddress() async {
        let parsed = ServerCheck.parse(address)
        guard case .checking(let url) = parsed else { check = parsed; return }
        check = parsed
        let result = await ServerCheck.check(url, with: model.client(for: url))
        // the field may have changed while waiting
        if ServerCheck.parse(address) == .checking(url) { check = result }
    }

    var canContinue: Bool { check.server != nil && !deviceName.isEmpty }

    var deviceName: String { device.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Continue: on to signing in at the checked server
    func useCheckedServer() {
        guard let url = check.server else { return }
        server = url
        hello = check.hello
        error = nil
        root = .signIn
        path = []
    }

    /// Change, on the sign-in screen
    func changeServer() {
        error = nil
        path = []
        root = .connect
    }

    /// a scanned or pasted pairing link: pairs at once; returns the problem to show, if any
    @discardableResult
    func pair(_ text: String) async -> String? {
        switch PairLink.parse(text) {
        case .failure(let p):
            return p.message
        case .success(let link):
            busy = true
            defer { busy = false }
            do {
                let grant = try await model.client(for: link.baseURL).pair(code: link.code, device: deviceNameOrDefault)
                server = link.baseURL
                address = ServerCheck.display(link.baseURL)
                await model.signedIn(grant, server: link.baseURL)
                return nil
            } catch let e as APIError {
                return e.message
            } catch {
                return "Couldn't pair this iPhone. Make a new code on the website."
            }
        }
    }

    private var deviceNameOrDefault: String { deviceName.isEmpty ? "iPhone" : deviceName }

    // MARK: sign in

    var canSignIn: Bool { !busy && !UsernameRule.normalize(username).isEmpty && !password.isEmpty && server != nil }

    func signIn() async {
        guard canSignIn, let client, let server else { return }
        await run {
            let grant = try await client.signIn(username: UsernameRule.normalize(self.username),
                                                password: self.password, device: self.deviceNameOrDefault)
            self.password = ""
            await self.model.signedIn(grant, server: server)
        }
    }

    /// whether the server lets new people join from here
    var canJoinHere: Bool { (hello?.joining ?? "invite") != "closed" }

    /// the server wants an invite code with a new account
    var needsInvite: Bool { (hello?.joining ?? "invite") == "invite" }

    var passkeys: Bool { hello?.passkeys ?? false }

    /// where the passkey sign-in opens (see the note at the top)
    func passkeyURL() -> URL? {
        guard let server, var c = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/connect/app"
        c.queryItems = [URLQueryItem(name: "device", value: deviceNameOrDefault)]
        return c.url
    }

    /// reads the hello again for a server kept from last time (passkeys, joining)
    func loadHello() async {
        guard hello == nil, let server else { return }
        if case .found(_, let h) = await ServerCheck.check(server, with: model.client(for: server)) { hello = h }
    }

    // MARK: join

    var usernameRule: UsernameRule { UsernameRule.check(username) }
    var meter: PasswordMeter { PasswordMeter(password) }

    var canJoin: Bool {
        !busy && usernameRule == .ok && meter.acceptable && server != nil
            && (!needsInvite || !invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func join() async {
        guard canJoin, let client else { return }
        let name = UsernameRule.normalize(username)
        let shown = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = JoinBody(username: name, displayName: shown.isEmpty ? name : shown, password: password,
                            device: deviceNameOrDefault,
                            invite: needsInvite ? invite.trimmingCharacters(in: .whitespacesAndNewlines) : nil)
        await run {
            let grant = try await client.join(body)
            self.password = ""
            self.showCodes(grant)
        }
    }

    /// the codes screen for a new account (the demo's -account recovery joins the demo user first)
    func showCodes(_ grant: DeviceGrant) {
        joined = grant
        saved = false
        path = []
        root = .codes
    }

    // MARK: recovery codes

    var saved = false
    var codes: [String] { joined?.recoveryCodes ?? [] }
    var joinedUsername: String { joined?.user.username ?? "" }

    var codesText: String {
        RecoveryCodes.text(codes, username: joinedUsername, server: server ?? Demo.server)
    }

    /// Open GupTrack: signs in with the grant from joining
    func finishJoining() async {
        guard saved, let grant = joined, let server else { return }
        joined = nil
        await model.signedIn(grant, server: server)
    }

    /// the demo's -account recovery: a new demo account to show codes for
    func demoJoin() async {
        guard joined == nil else { return }
        let url = server ?? Demo.server
        server = url
        let body = JoinBody(username: "mika", displayName: "Mika", password: "", device: deviceNameOrDefault, invite: nil)
        if let grant = try? await model.client(for: url).join(body) { showCodes(grant) }
    }

    // MARK: recover

    var canRecover: Bool {
        !busy && !UsernameRule.normalize(username).isEmpty && !RecoveryCodes.normalize(code).isEmpty
            && meter.acceptable && server != nil
    }

    func recover() async {
        guard canRecover, let client, let server else { return }
        let body = RecoverBody(username: UsernameRule.normalize(username), code: RecoveryCodes.normalize(code),
                               password: password, device: deviceNameOrDefault)
        await run {
            let grant = try await client.recover(body)
            self.password = ""
            await self.model.signedIn(grant, server: server)
        }
    }

    // MARK: moving between screens

    func go(_ step: Step) {
        error = nil
        if let i = path.firstIndex(of: step) { path = Array(path[...i]) } else if step == root { path = [] } else { path.append(step) }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await work()
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = "Something went wrong. Try again."
        }
    }
}
