import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(GupTrackKit)
@testable import GupTrackKit
#else
@testable import GupTrack
#endif

/// A transport that answers with whatever the test sets.
final class StubTransport: Transport, @unchecked Sendable {
    var answer = APIResponse(Data("{}".utf8), 200)
    var error: Error?
    var sent: [APIRequest] = []

    func reply(_ json: String, _ status: Int = 200, headers: [String: String] = [:]) {
        answer = APIResponse(Data(json.utf8), status, headers: headers)
    }

    func send(_ r: APIRequest) async throws -> APIResponse {
        sent.append(r)
        if let error { throw error }
        return answer
    }
}

final class APITests: XCTestCase {
    let base = URL(string: "https://pc.example.ts.net")!

    func testURLs() {
        XCTAssertEqual(APIRequest("GET", "library/changes", query: [URLQueryItem(name: "since", value: "c 1")]).url(on: base)?.absoluteString,
                       "https://pc.example.ts.net/api/app/v1/library/changes?since=c%201")
        XCTAssertEqual(APIRequest("GET", "/server").url(on: URL(string: "https://h.example/base/")!)?.absoluteString,
                       "https://h.example/base/api/app/v1/server")
    }

    func testRequestsCarryTheBearerTokenAndJSON() throws {
        let r = try LiveTransport.makeRequest(APIRequest("POST", "library/write", body: Data("{}".utf8), token: "t0k"), base: base)
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Accept"), "application/json")
        let anon = try LiveTransport.makeRequest(APIRequest("GET", "server"), base: base)
        XCTAssertNil(anon.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(anon.httpBody)
    }

    func testOfflineMessages() {
        XCTAssertEqual(LiveTransport.why(URLError(.notConnectedToInternet)), "This iPhone is offline.")
        XCTAssertTrue(LiveTransport.why(URLError(.cannotFindHost)).contains("Tailscale DNS"))
    }

    func testDatesDecodeFromISOAndEpoch() throws {
        struct D: Decodable { var a: Date; var b: Date; var c: Date }
        let d = try APIClient.decoder.decode(D.self, from: Data(#"{"a":"2026-11-03T14:41:00.000Z","b":1793716860,"c":1793716860000}"#.utf8))
        XCTAssertEqual(d.a, Clock.demoNow)
        XCTAssertEqual(d.b, Clock.demoNow)
        XCTAssertEqual(d.c, Clock.demoNow)
    }

    func testClientErrors() async {
        let t = StubTransport()
        let api = APIClient(transport: t, token: "x")
        t.reply(#"{"error":"bad_request","message":"Nope.","serverTime":1}"#, 400)
        await assertThrows(APIError.server(400, "bad_request", "Nope.")) { let _: OKReply = try await api.get("x") }
        t.reply("", 401)
        await assertThrows(APIError.signedOut) { let _: OKReply = try await api.get("x") }
        t.reply("<html>", 502)
        await assertThrows(APIError.server(502, "server_error", "GupTrack answered with an error (502).")) {
            let _: OKReply = try await api.get("x")
        }
        t.reply(#"{"nope":1}"#)
        await assertThrows(APIError.unreadable) { let _: OKReply = try await api.get("x") }
        t.error = APIError.unreachable("off")
        await assertThrows(APIError.unreachable("off")) { let _: OKReply = try await api.get("x") }
        XCTAssertEqual(t.sent.first?.token, "x")
    }

    func testUnauthorizedWithoutATokenIsAnOrdinaryError() async {
        let t = StubTransport()
        t.reply(#"{"error":"unauthorized","message":"Wrong username or password.","serverTime":1}"#, 401)
        await assertThrows(APIError.server(401, "unauthorized", "Wrong username or password.")) {
            _ = try await APIClient(transport: t).signIn(username: "a", password: "b",
                                                         device: DeviceInfo(name: "c", platform: "iOS"))
        }
    }

    func testBodiesAreSortedJSON() async throws {
        let t = StubTransport()
        t.reply(#"{"ok":true}"#)
        let api = APIClient(transport: t, token: "x")
        let _: OKReply = try await api.send("POST", "auth/pair", PairBody(code: "c", device: DeviceInfo(name: "d", platform: "p")))
        XCTAssertEqual(t.sent[0].body.map { String(decoding: $0, as: UTF8.self) },
                       #"{"code":"c","device":{"name":"d","platform":"p"}}"#)
    }
}

final class DemoTests: XCTestCase {
    func testFlags() {
        let saved = Demo.args
        defer { Demo.args = saved }
        Demo.args = ["app", "-demo", "-tab", "library", "-open", "list/anime", "-open", "title/anime:1"]
        XCTAssertTrue(Demo.isOn)
        XCTAssertEqual(Demo.value("-tab"), "library")
        XCTAssertEqual(Demo.values("-open"), ["list/anime", "title/anime:1"])
        XCTAssertNil(Demo.value("-sheet"))
    }

    func testFixtureNames() {
        XCTAssertEqual(Demo.file("titles/anime:210482"), "api/titles/anime_210482.json")
        XCTAssertEqual(Demo.file("search", variant: "One Piece!"), "api/search/one-piece.json")
        XCTAssertEqual(Demo.file("lists", method: "POST"), "api/lists.post.json")
    }

    func testDemoTransportAnswersFromFixtures() async throws {
        let api = APIClient(transport: DemoTransport(), token: "demo")
        let me = try await api.me()
        XCTAssertEqual(me.me.username, "mika")
        let server = try await api.server()
        XCTAssertEqual(server.app, AppAPI.app)
        let ok: OKReply = try await api.send("POST", "anything/at/all")
        XCTAssertTrue(ok.ok)
        await assertThrows(APIError.server(404, "not_found", "Nothing here in the demo.")) {
            let _: OKReply = try await api.get("nope")
        }
    }

    func testDemoOffline() async {
        let api = APIClient(transport: DemoTransport(offline: true), token: "demo")
        await assertThrows(APIError.unreachable("This iPhone is offline.")) { _ = try await api.server() }
    }
}

func assertThrows(_ expected: APIError, file: StaticString = #filePath, line: UInt = #line,
                  _ work: () async throws -> Void) async {
    do {
        try await work()
        XCTFail("no error, expected \(expected)", file: file, line: line)
    } catch let e as APIError {
        XCTAssertEqual(e, expected, file: file, line: line)
    } catch {
        XCTFail("\(error)", file: file, line: line)
    }
}
